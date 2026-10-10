defmodule Oktavarium.Directory do
  @moduledoc false
  import Ecto.Query

  alias Oktavarium.{Authz, Delegation, Envelope, Repo}
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Keys.{IdentityAuthKey, Key}
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
