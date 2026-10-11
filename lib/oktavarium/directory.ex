defmodule Oktavarium.Directory do
  @moduledoc false
  import Ecto.Query

  alias Oktavarium.{Authz, Delegation, Envelope, Repo}
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Keys.{IdentityAuthKey, IdentitySigningKey, Key}
  alias Oktavarium.Resources.Resource
  alias Oktavarium.Log.Event

  @type grant_status :: :active | :revoked | :expired | :pending | :broken

  @doc "Publiczne tożsamości, najnowsze pierwsze, z liczbą zdarzeń i głową dziennika."
  @spec list_identities() :: [
          %{identity: %Identity{}, events: non_neg_integer(), head: String.t() | nil}
        ]
  def list_identities do
    identities =
      Repo.all(
        from i in Identity,
          where: i.visibility == ^:public,
          order_by: [desc: i.inserted_at, asc: i.handle, asc: i.id]
      )

    ids = Enum.map(identities, & &1.id)

    counts =
      from(e in Event,
        where: e.identity_id in ^ids,
        group_by: e.identity_id,
        select: {e.identity_id, count(e.id)}
      )
      |> Repo.all()
      |> Map.new()

    latest =
      from(e in Event,
        where: e.identity_id in ^ids,
        group_by: e.identity_id,
        select: %{identity_id: e.identity_id, seq: max(e.seq)}
      )

    heads =
      from(e in Event,
        join: l in subquery(latest),
        on: e.identity_id == l.identity_id and e.seq == l.seq,
        select: {e.identity_id, e.id}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(identities, fn i ->
      %{identity: i, events: Map.get(counts, i.id, 0), head: Map.get(heads, i.id)}
    end)
  end

  @doc "Publiczna tożsamość po uchwycie albo id; `nil`, gdy jej nie ma."
  @spec get_identity(String.t()) :: %Identity{} | nil
  def get_identity(ref) when is_binary(ref) do
    Repo.one(
      from i in Identity,
        where: i.visibility == ^:public and (i.handle == ^ref or i.id == ^ref)
    )
  end

  # zasoby

  @doc """
  Zasoby tożsamości (`:image`, `:audio`, `:site` albo wszystkie), posortowane po
  rodzaju i ścieżce. Każdy jako mapa z polami wpisu.
  """
  @spec resources(%Identity{}, atom() | nil) :: [map()]
  def resources(%Identity{id: id}, kind \\ nil) do
    query =
      from r in Resource,
        where: r.identity_id == ^id,
        order_by: [asc: r.kind, asc: r.path],
        select: map(r, [:path, :kind, :hash, :size, :media_type, :meta, :updated_at])

    query = if kind, do: where(query, [r], r.kind == ^kind), else: query
    Repo.all(query)
  end

  @doc """
  Najnowsze zasoby danego rodzaju ze wszystkich **publicznych** tożsamości (galeria na
  stronie głównej). Opcja `:limit` (domyślnie 48). Każdy wpis niesie też
  tożsamość, do której należy.
  """
  @spec gallery(:image | :audio, keyword()) :: [map()]
  def gallery(kind, opts \\ []) when kind in [:image, :audio] do
    Repo.all(
      from r in Resource,
        join: i in Identity,
        on: i.id == r.identity_id,
        where: r.kind == ^kind and i.visibility == ^:public,
        order_by: [desc: r.updated_at, desc: r.inserted_at, asc: r.path],
        limit: ^Keyword.get(opts, :limit, 48),
        select: %{
          path: r.path,
          hash: r.hash,
          media_type: r.media_type,
          meta: r.meta,
          at: r.updated_at,
          identity_id: i.id,
          handle: i.handle,
          profile: i.profile
        }
    )
  end

  @doc "Klucze sygnowania dopisane do tożsamości zdarzeniem `key.add` (bez klucza założycielskiego)."
  @spec members(%Identity{}) :: [map()]
  def members(%Identity{id: id}) do
    Repo.all(
      from m in IdentitySigningKey,
        where: m.identity_id == ^id,
        order_by: [asc: m.inserted_at, asc: m.key_id],
        select: %{key_id: m.key_id, label: m.label, status: m.status}
    )
  end

  @doc """
  Plik strony tożsamości o uchwycie `handle`: ścieżka względna do `site/`
  (`"index.html"`, `"css/a.css"`). `{:ok, %{hash, media_type, size}}` albo `:error`.
  Tylko tożsamości publiczne.
  """
  @spec site_file(String.t(), String.t()) :: {:ok, map()} | :error
  def site_file(handle, relative) when is_binary(handle) and is_binary(relative) do
    row =
      Repo.one(
        from r in Resource,
          join: i in Identity,
          on: i.id == r.identity_id,
          where:
            i.handle == ^handle and i.visibility == ^:public and r.kind == ^:site and
              r.path == ^("site/" <> relative),
          select: %{hash: r.hash, media_type: r.media_type, size: r.size}
      )

    if row, do: {:ok, row}, else: :error
  end

  @doc "Czy tożsamość ma stronę (plik `site/index.html`)."
  def has_site?(%Identity{id: id}),
    do:
      Repo.exists?(
        from r in Resource, where: r.identity_id == ^id and r.path == "site/index.html"
      )

  @doc "Blob dostępny publicznie: `hash` użyty przez zasób obrazu albo audio publicznej tożsamości."
  @spec public_media(String.t()) :: map() | nil
  def public_media(hash) do
    Repo.one(
      from r in Resource,
        join: i in Identity,
        on: i.id == r.identity_id,
        where: r.hash == ^hash and r.kind in [:image, :audio] and i.visibility == ^:public,
        limit: 1,
        select: %{hash: r.hash, media_type: r.media_type, size: r.size}
    )
  end

  @doc "Czy tożsamość o `id` istnieje (także niepubliczna); do API zalogowanych."
  def identity_exists?(id), do: Repo.exists?(from i in Identity, where: i.id == ^id)

  @doc "Id klucza założycielskiego (podpisał genesis)."
  @spec founding_key_id(%Identity{}) :: String.t() | nil
  def founding_key_id(%Identity{id: id}) do
    Repo.one(from e in Event, where: e.identity_id == ^id and e.seq == 0, select: e.signer_key_id)
  end

  @doc "Klucze autoryzacji tożsamości jako `%{key_id: id, status: status}`."
  @spec auth_keys(%Identity{}) :: [%{key_id: String.t(), status: :active | :revoked}]
  def auth_keys(%Identity{id: id}) do
    Repo.all(
      from l in IdentityAuthKey,
        where: l.identity_id == ^id,
        order_by: [asc: l.inserted_at, asc: l.key_id],
        select: %{key_id: l.key_id, status: l.status}
    )
  end

  @doc "Liczba zdarzeń w dzienniku tożsamości."
  @spec event_count(%Identity{}) :: non_neg_integer()
  def event_count(%Identity{id: id}),
    do: Repo.aggregate(from(e in Event, where: e.identity_id == ^id), :count)

  @doc """
  Granty tożsamości w kolejności nadania. Każdy jako mapa z polami grantu i
  `:status`: `:active`, `:revoked`, `:expired`, `:pending` (okno jeszcze się nie
  zaczęło) albo `:broken` (łańcuch do klucza założycielskiego nie jest ważny).
  """
  @spec grants(%Identity{}, DateTime.t()) :: [map()]
  def grants(%Identity{id: id} = identity, now \\ DateTime.utc_now()) do
    rows =
      Repo.all(
        from g in Grant, where: g.identity_id == ^id, order_by: [asc: g.inserted_at, asc: g.id]
      )

    index = Map.new(rows, &{&1.id, &1})
    founding = founding_key_id(identity)

    Enum.map(rows, fn grant ->
      grant
      |> Map.take([
        :id,
        :action,
        :resource,
        :not_before,
        :expires_at,
        :revoked_at,
        :delegable,
        :issuer_key_id,
        :subject_key_id,
        :parent_grant_id,
        :inserted_at
      ])
      |> Map.put(:status, grant_status(grant, index, founding, now))
    end)
  end

  defp grant_status(grant, index, founding, now) do
    cond do
      grant.revoked_at != nil and DateTime.compare(grant.revoked_at, now) != :gt -> :revoked
      grant.expires_at != nil and DateTime.compare(grant.expires_at, now) != :gt -> :expired
      grant.not_before != nil and DateTime.compare(grant.not_before, now) == :gt -> :pending
      not Delegation.active_at?(grant, now) -> :broken
      Authz.chain_valid(grant, index, founding, now) != :ok -> :broken
      true -> :active
    end
  end

  @doc """
  Kto stoi za kluczami: `%{key_id => %{identity_id: id, handle: handle | nil}}` dla
  kluczy sygnowania, które mają tożsamość domową. Klucze autoryzacji i nieznane nie występują w wyniku.
  """
  @spec key_homes([String.t()]) :: %{
          optional(String.t()) => %{identity_id: String.t(), handle: String.t() | nil}
        }
  def key_homes([]), do: %{}

  def key_homes(key_ids) do
    from(k in Key,
      join: i in Identity,
      on: i.id == k.home_identity_id,
      where: k.id in ^Enum.uniq(key_ids) and i.visibility == ^:public,
      select: {k.id, %{identity_id: i.id, handle: i.handle}}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Historia dziennika, najnowsze zdarzenia pierwsze. Opcje: `:limit` (domyślnie 50) i
  `:before` (tylko zdarzenia o `seq` mniejszym). Zwraca `{wpisy, następne_before}`,
  gdzie `następne_before` to `nil`, gdy nie ma starszych zdarzeń.

  Każdy wpis to mapa `:seq`, `:id`, `:type`, `:signer`, `:body`, `:received_at`
  (czas przyjęcia przez serwer) albo, gdy podpis nie przechodzi weryfikacji, `:corrupt` z powodem.
  """
  @spec timeline(%Identity{}, keyword()) :: {[map()], non_neg_integer() | nil}
  def timeline(%Identity{id: id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    query =
      from e in Event,
        join: k in Key,
        on: k.id == e.signer_key_id,
        where: e.identity_id == ^id,
        order_by: [desc: e.seq],
        limit: ^(limit + 1),
        select: {e, k.public_key}

    query =
      case Keyword.get(opts, :before) do
        nil -> query
        before -> where(query, [e], e.seq < ^before)
      end

    rows = Repo.all(query)
    {page, rest} = Enum.split(rows, limit)
    entries = Enum.map(page, &entry/1)
    next = if rest == [], do: nil, else: entries |> List.last() |> Map.fetch!(:seq)

    {entries, next}
  end

  defp entry({stored, public_key}) do
    base = %{
      seq: stored.seq,
      id: stored.id,
      type: stored.type,
      received_at: DateTime.from_naive!(stored.inserted_at, "Etc/UTC")
    }

    envelope = %Envelope{payload: stored.payload, signature: stored.signature, signer: public_key}

    case Envelope.verify(envelope) do
      {:ok, event} ->
        Map.merge(base, %{signer: event.signer, body: event.body})

      {:error, reason} ->
        Map.merge(base, %{signer: stored.signer_key_id, body: %{}, corrupt: reason})
    end
  end
end
