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

  # The avatar is a normal signed resource in the identity's root namespace.
  # Updating it by resource.put keeps its stable ID and does not change the
  # profile event schema. Project files with the same path are not avatars.
  @avatar_path "images/avatar"
  def avatar_path, do: @avatar_path

  def avatar(resources) when is_list(resources) do
    Enum.find(resources, fn r ->
      r.kind == :image and is_nil(r.project_id) and r.path == @avatar_path
    end)
  end

  @doc "Publiczne tożsamości, najnowsze pierwsze, z liczbą zdarzeń i głową dziennika."
  @spec list_identities() :: [
          %{
            identity: %Identity{},
            events: non_neg_integer(),
            head: String.t() | nil,
            avatar_hash: String.t() | nil
          }
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

    avatar_hashes =
      Repo.all(
        from r in Resource,
          where:
            r.identity_id in ^ids and r.kind == ^:image and is_nil(r.project_id) and
              r.path == ^@avatar_path,
          select: {r.identity_id, r.hash}
      )
      |> Map.new()

    Enum.map(identities, fn i ->
      %{
        identity: i,
        events: Map.get(counts, i.id, 0),
        head: Map.get(heads, i.id),
        avatar_hash: Map.get(avatar_hashes, i.id)
      }
    end)
  end

  @doc "Tożsamość po uchwycie albo id, również `unlisted`; `nil` dla nieznanej."
  @spec get_identity(String.t()) :: %Identity{} | nil
  def get_identity(ref) when is_binary(ref) do
    Repo.one(
      from i in Identity,
        where: i.handle == ^ref or i.id == ^ref
    )
  end

  # Public project index: unlisted owners remain readable by address, not discoverable.
  def list_projects(opts \\ []) do
    Repo.all(
      from p in Resource,
        join: i in Identity,
        on: i.id == p.identity_id,
        where: p.kind == ^:project and i.visibility == ^:public,
        order_by: [desc: p.updated_at, asc: p.id],
        limit: ^Keyword.get(opts, :limit, 48),
        select: %{project: map(p, [:id, :path, :meta, :meta_refs, :updated_at]), identity: i}
    )
  end

  # zasoby

  @doc """
  Pliki tożsamości (`:image`, `:audio`, `:site` albo wszystkie), z trwałymi
  identyfikatorami i opcjonalnym `project_id`. Projekty są udostępniane osobno.
  """
  @spec resources(%Identity{}, atom() | nil) :: [map()]
  def resources(%Identity{id: id}, kind \\ nil) do
    query =
      from r in Resource,
        where: r.identity_id == ^id and r.kind != ^:project,
        order_by: [asc: r.kind, asc: r.path],
        select:
          map(r, [
            :id,
            :project_id,
            :path,
            :kind,
            :hash,
            :size,
            :media_type,
            :meta,
            :meta_refs,
            :updated_at
          ])

    query = if kind, do: where(query, [r], r.kind == ^kind), else: query
    Repo.all(query)
  end

  @doc "Projekty tożsamości. Sam projekt nie ma bloba; jest kontenerem zasobów."
  @spec projects(%Identity{}) :: [map()]
  def projects(%Identity{id: id}) do
    Repo.all(
      from r in Resource,
        where: r.identity_id == ^id and r.kind == ^:project,
        order_by: [asc: r.path],
        select: map(r, [:id, :path, :meta, :meta_refs, :updated_at])
    )
  end

  @doc "Pliki z danego projektu tej samej tożsamości."
  @spec project_resources(%Identity{}, String.t()) :: [map()]
  def project_resources(%Identity{id: id}, project_id) do
    Repo.all(
      from r in Resource,
        where: r.identity_id == ^id and r.project_id == ^project_id and r.kind != ^:project,
        order_by: [asc: r.kind, asc: r.path],
        select:
          map(r, [
            :id,
            :project_id,
            :path,
            :kind,
            :hash,
            :size,
            :media_type,
            :meta,
            :meta_refs,
            :updated_at
          ])
    )
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
        where:
          r.kind == ^kind and i.visibility == ^:public and
            not (is_nil(r.project_id) and r.path == ^@avatar_path),
        order_by: [desc: r.updated_at, desc: r.inserted_at, asc: r.path],
        limit: ^Keyword.get(opts, :limit, 48),
        select: %{
          id: r.id,
          project_id: r.project_id,
          path: r.path,
          hash: r.hash,
          media_type: r.media_type,
          meta: r.meta,
          meta_refs: r.meta_refs,
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
  Także `unlisted`: kto zna adres strony, może ją otworzyć.
  """
  @spec site_file(String.t(), String.t()) :: {:ok, map()} | :error
  def site_file(handle, relative) when is_binary(handle) and is_binary(relative) do
    row =
      Repo.one(
        from r in Resource,
          join: i in Identity,
          on: i.id == r.identity_id,
          where:
            i.handle == ^handle and r.kind == ^:site and is_nil(r.project_id) and
              r.path == ^("site/" <> relative),
          select: %{hash: r.hash, media_type: r.media_type, size: r.size}
      )

    if row, do: {:ok, row}, else: :error
  end

  @doc "Czy tożsamość ma stronę (plik `site/index.html`)."
  def has_site?(%Identity{id: id}),
    do:
      Repo.exists?(
        from r in Resource,
          where: r.identity_id == ^id and r.path == "site/index.html" and is_nil(r.project_id)
      )

  @doc "Blob obrazu/nagrania dostępny pod bezpośrednim adresem, także z tożsamości `unlisted`."
  @spec public_media(String.t()) :: map() | nil
  def public_media(hash) do
    Repo.one(
      from r in Resource,
        join: i in Identity,
        on: i.id == r.identity_id,
        where: r.hash == ^hash and r.kind in [:image, :audio],
        limit: 1,
        select: %{hash: r.hash, media_type: r.media_type, size: r.size}
    )
  end

  @doc "Czy tożsamość o `id` istnieje (także niepubliczna); do API zalogowanych."
  def identity_exists?(id), do: Repo.exists?(from i in Identity, where: i.id == ^id)

  @doc "A project in its owner's namespace, including unlisted identities."
  def project(%Identity{id: identity_id}, project_id) do
    Repo.get_by(Resource, id: project_id, identity_id: identity_id, kind: :project)
  end

  @doc "Published file by ID. Never returns a project or another owner's file."
  def file(%Identity{id: identity_id}, resource_id) do
    Repo.one(
      from r in Resource,
        where: r.id == ^resource_id and r.identity_id == ^identity_id and r.kind != ^:project
    )
  end

  @doc "A website file in a project's isolated origin."
  def project_site_file(project_id, relative) do
    row =
      Repo.one(
        from r in Resource,
          join: p in Resource,
          on: p.id == r.project_id and p.identity_id == r.identity_id,
          where:
            p.id == ^project_id and p.kind == ^:project and
              r.kind == ^:site and r.path == ^("site/" <> relative),
          select: %{hash: r.hash, media_type: r.media_type, size: r.size}
      )

    if row, do: {:ok, row}, else: :error
  end

  def project_has_site?(project_id) do
    Repo.exists?(
      from r in Resource,
        where: r.project_id == ^project_id and r.kind == ^:site and r.path == "site/index.html"
    )
  end

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
