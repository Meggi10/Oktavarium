defmodule Oktavarium.Replay do
  @moduledoc false
  import Ecto.Query, only: [from: 2]

  alias Oktavarium.{Log, Repo}
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Keys.{IdentityAuthKey, IdentitySigningKey, Key}
  alias Oktavarium.Resources.Resource
  alias Oktavarium.Log.Event

  @tables [
    identities: {Identity, [:id, :kind, :handle, :profile, :profile_refs, :visibility], [:id]},
    keys: {Key, [:id, :kind, :algo, :public_key, :status, :home_identity_id], [:id]},
    auth_links:
      {IdentityAuthKey, [:identity_id, :key_id, :status, :added_event_id],
       [:identity_id, :key_id]},
    signing_members:
      {IdentitySigningKey, [:identity_id, :key_id, :label, :status, :added_event_id],
       [:identity_id, :key_id]},
    resources:
      {Resource,
       [
         :id,
         :identity_id,
         :project_id,
         :path,
         :kind,
         :hash,
         :size,
         :media_type,
         :meta,
         :meta_refs,
         :event_id
       ], [:id]},
    grants:
      {Grant,
       [
         :id,
         :identity_id,
         :issuer_key_id,
         :subject_key_id,
         :parent_grant_id,
         :action,
         :resource,
         :not_before,
         :expires_at,
         :revoked_at,
         :delegable
       ], [:id]}
  ]
  @type drift :: %{atom() => %{missing: [term()], extra: [term()], changed: [{term(), [atom()]}]}}

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    apply? = Keyword.get(opts, :apply, false)

    result =
      Repo.transaction(fn ->
        with {:ok, entries} <- load_entries() do
          before = snapshot()
          wipe()

          case replay(entries) do
            :ok -> finish(entries, before, apply?)
            {:error, reason} -> Repo.rollback(reason)
          end
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, report} -> {:ok, report}
      {:error, {:__report__, report}} -> {:ok, report}
      {:error, reason} -> {:error, reason}
    end
  end

  # Raport wraca z transakcji na dwa sposoby: przy zatwierdzeniu jako wynik, przy
  # wycofaniu (sprawdzanie albo brak rozbieżności) jako zawinięty powód wycofania.
  defp finish(entries, before, apply?) do
    drift = diff(before, snapshot())

    in_sync? =
      Enum.all?(drift, fn {_table, d} -> d.missing == [] and d.extra == [] and d.changed == [] end)

    report = %{
      events: length(entries),
      identities: Enum.count(entries, & &1.event.genesis?),
      in_sync?: in_sync?,
      applied?: apply? and not in_sync?,
      drift: drift
    }

    if report.applied?, do: report, else: Repo.rollback({:__report__, report})
  end

  # wczytanie i weryfikacja

  defp load_entries do
    # kolejność przyjęcia; remisy w obrębie sekundy rozstrzyga porządek deterministyczny
    rows =
      Repo.all(from e in Event, order_by: [asc: e.inserted_at, asc: e.identity_id, asc: e.seq])

    Enum.reduce_while(rows, {:ok, []}, fn stored, {:ok, acc} ->
      case Log.verify_stored(stored) do
        {:ok, envelope, event} ->
          entry = %{
            id: stored.id,
            envelope: envelope,
            event: event,
            received_at: received_at(stored)
          }

          {:cont, {:ok, [entry | acc]}}

        {:error, reason} ->
          {:halt, {:error, {:corrupt, stored.id, reason}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp received_at(%Event{inserted_at: %NaiveDateTime{} = naive}),
    do: DateTime.from_naive!(naive, "Etc/UTC")

  # odtwarzanie

  # Kolejność FK: granty (samoodwołanie), powiązania, zdarzenia, klucze, tożsamości.
  defp wipe do
    Repo.update_all(Grant, set: [parent_grant_id: nil])

    for schema <- [
          Resource,
          IdentitySigningKey,
          Grant,
          IdentityAuthKey,
          Event,
          Key,
          Identity
        ] do
      Repo.delete_all(schema)
    end

    :ok
  end

  defp replay([]), do: :ok

  defp replay(entries) do
    {applied, deferred} = pass(entries)

    cond do
      deferred == [] ->
        :ok

      applied == 0 ->
        {:error, {:stuck, Enum.map(deferred, fn {entry, reason} -> {entry.id, reason} end)}}

      true ->
        deferred |> Enum.map(&elem(&1, 0)) |> replay()
    end
  end

  # Jeden przebieg: stosuje wszystko, co planner dziś przyjmuje, resztę odkłada
  # (z powodem), zachowując kolejność.
  defp pass(entries) do
    {applied, deferred} =
      Enum.reduce(entries, {0, []}, fn entry, {applied, deferred} ->
        case Log.plan_verified(entry.envelope, entry.event, entry.received_at) do
          {:ok, ops} ->
            Log.apply_ops(ops, entry.received_at)
            {applied + 1, deferred}

          {:error, reason} ->
            {applied, [{entry, reason} | deferred]}
        end
      end)

    {applied, Enum.reverse(deferred)}
  end

  # porównanie

  @doc "Bieżąca projekcja jako mapy `tabela => %{klucz => pola}` (bez znaczników czasu)."
  @spec snapshot() :: %{atom() => %{term() => map()}}
  def snapshot do
    Map.new(@tables, fn {name, {schema, fields, key_fields}} ->
      rows = Repo.all(from s in schema, select: map(s, ^fields))
      {name, Map.new(rows, fn row -> {row_key(row, key_fields), row} end)}
    end)
  end

  defp row_key(row, [field]), do: Map.fetch!(row, field)
  defp row_key(row, fields), do: Enum.map(fields, &Map.fetch!(row, &1)) |> List.to_tuple()

  @doc false
  @spec diff(map(), map()) :: drift()
  def diff(before, after_) do
    Map.new(before, fn {table, old} ->
      new = Map.fetch!(after_, table)

      changed =
        for {key, old_row} <- old,
            new_row = Map.get(new, key),
            old_row != new_row,
            do:
              {key,
               for({field, value} <- old_row, Map.get(new_row, field) != value, do: field)
               |> Enum.sort()}

      {table,
       %{
         missing: new |> Map.keys() |> Enum.reject(&Map.has_key?(old, &1)) |> Enum.sort(),
         extra: old |> Map.keys() |> Enum.reject(&Map.has_key?(new, &1)) |> Enum.sort(),
         changed: Enum.sort(changed)
       }}
    end)
  end
end
