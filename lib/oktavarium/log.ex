defmodule Oktavarium.Log do
  @moduledoc false
  import Ecto.Query, only: [from: 2]

  alias Oktavarium.{Crypto, Envelope, Repo}
  alias Oktavarium.Grants.Grant
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Keys.{IdentityAuthKey, IdentitySigningKey, Key}
  alias Oktavarium.Resources.Resource
  alias Oktavarium.Log.{Event, Facts, Planner}

  @spec append(Envelope.t()) :: {:ok, Envelope.event()} | {:error, term()}
  def append(%Envelope{} = envelope) do
    case Envelope.verify(envelope) do
      {:ok, event} -> append_verified(envelope, event)
      {:error, reason} -> {:error, {:invalid_envelope, reason}}
    end
  end

  defp append_verified(envelope, event) do
    Repo.transaction(fn ->
      case plan_verified(envelope, event, nil) do
        {:ok, ops} ->
          apply_ops(ops, nil)
          event

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  # wejście dla `Oktavarium.Replay` (odbudowa projekcji z zapisanych dzienników)

  @doc false
  # Ocena zdarzenia względem stanu bazy bez zapisywania. `now` to chwila, względem
  # której ocenia się uprawnienia: przy zwykłym przyjęciu `nil` (czas serwera), przy
  # odtwarzaniu moment, w którym serwer zdarzenie pierwotnie przyjął.
  @spec plan_verified(Envelope.t(), Envelope.event(), DateTime.t() | nil) ::
          {:ok, [Planner.op()]} | {:error, term()}
  def plan_verified(envelope, event, now),
    do: Planner.plan(envelope, event, load_facts(event, now))

  @doc false
  # Zapis operacji z planu. Musi być wywołany wewnątrz transakcji; błąd bazy kończy się
  # `Repo.rollback/1`. Z `received_at` znaczniki czasu wierszy dostają czas przyjęcia.
  @spec apply_ops([Planner.op()], DateTime.t() | nil) :: :ok
  def apply_ops(ops, received_at) do
    Enum.each(ops, &apply_op(&1, received_at))
  end

  @doc false
  # Weryfikacja zapisanego wiersza zdarzenia na podstawie samych bajtów: podpis,
  # struktura oraz zgodność `id`, tożsamości i `seq` z kolumnami. Klucz publiczny
  # podpisującego wynika z jego identyfikatora, więc nie trzeba tabeli `keys`.
  @spec verify_stored(Event.t()) :: {:ok, Envelope.t(), Envelope.event()} | {:error, term()}
  def verify_stored(%Event{} = stored) do
    with {:ok, public_key} <- stored_public_key(stored),
         envelope = %Envelope{
           payload: stored.payload,
           signature: stored.signature,
           signer: public_key
         },
         {:ok, event} <- Envelope.verify(envelope),
         :ok <- check_columns(stored, event) do
      {:ok, envelope, event}
    end
  end

  defp stored_public_key(%Event{signer_key_id: id}) do
    case Crypto.decode_key_id(id) do
      {:ok, public_key} -> {:ok, public_key}
      :error -> {:error, :bad_signer_key}
    end
  end

  defp check_columns(stored, event) do
    cond do
      event.id != stored.id -> {:error, :id_mismatch}
      event.identity != stored.identity_id -> {:error, :identity_mismatch}
      event.seq != stored.seq -> {:error, :bad_seq}
      true -> :ok
    end
  end

  @doc """
  Zapisane zdarzenia jednej tożsamości w kolejności `seq`, jako koperty gotowe do
  przekazania dalej (np. do repliki albo do ponownej weryfikacji). Z `after_seq`
  tylko zdarzenia o `seq` większym od podanego.
  """
  @spec envelopes(String.t(), integer()) :: [Envelope.t()]
  def envelopes(identity_id, after_seq \\ -1) do
    identity_id
    |> stored_events(after_seq)
    |> Enum.map(fn {event, public_key} ->
      %Envelope{payload: event.payload, signature: event.signature, signer: public_key}
    end)
  end

  @doc """
  Głowa dziennika: `seq` i id ostatniego zdarzenia tożsamości. To z niej piszący
  (zwłaszcza delegat dopisujący do cudzego dziennika) bierze `seq + 1` i `prev`
  następnego zdarzenia.
  """
  @spec head(String.t()) ::
          {:ok, %{seq: non_neg_integer(), id: String.t()}} | {:error, :unknown_identity}
  def head(identity_id) when is_binary(identity_id) do
    case latest_event(identity_id) do
      nil -> {:error, :unknown_identity}
      head -> {:ok, head}
    end
  end

  @doc """
  Sprawdza dziennik tożsamości od zera, wyłącznie na podstawie zapisanych bajtów:
  podpisy, identyfikatory, ciągłość `seq` i `prev`. Niczego nie ufa projekcji w
  tabelach, więc wykrywa także ręczne grzebanie w bazie.

  Zwraca `:ok`, `{:error, :unknown_identity}` albo
  `{:error, {:corrupt, seq, powód}}` dla pierwszego uszkodzonego zdarzenia.
  """
  @spec verify(String.t()) :: :ok | {:error, term()}
  def verify(identity_id) do
    case stored_events(identity_id) do
      [] -> {:error, :unknown_identity}
      rows -> verify_rows(rows)
    end
  end

  defp verify_rows(rows) do
    rows
    |> Enum.reduce_while(nil, fn {stored, _public_key}, previous ->
      with {:ok, _envelope, event} <- verify_stored(stored),
           :ok <- check_link(event, previous) do
        {:cont, event}
      else
        {:error, reason} -> {:halt, {:error, {:corrupt, stored.seq, reason}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      _last_event -> :ok
    end
  end

  # ciągłość łańcucha: `seq` bez dziur, `prev` wskazuje poprzednie zdarzenie
  defp check_link(event, previous) do
    expected_seq = if previous, do: previous.seq + 1, else: 0

    cond do
      event.seq != expected_seq -> {:error, :bad_seq}
      event.prev != if(previous, do: previous.id) -> {:error, :bad_prev}
      true -> :ok
    end
  end

  defp stored_events(identity_id, after_seq \\ -1) do
    Repo.all(
      from e in Event,
        join: k in Key,
        on: k.id == e.signer_key_id,
        where: e.identity_id == ^identity_id and e.seq > ^after_seq,
        order_by: [asc: e.seq],
        select: {e, k.public_key}
    )
  end

  # fakty

  defp load_facts(%{genesis?: true} = event, _now) do
    %Facts{
      event_exists?: event_exists?(event.id),
      signer_key: key_info(event.signer),
      handle_taken?: handle_taken?(event.body["handle"]),
      keys: key_infos(auth_key_ids(event.body))
    }
  end

  defp load_facts(event, now) do
    %Facts{
      event_exists?: event_exists?(event.id),
      identity: identity_info(event.identity),
      head: latest_event(event.identity),
      founding_key_id: founding_key_id(event.identity),
      signer_key: key_info(event.signer),
      subject_key: key_info(event.body["subject"]),
      grants: grants_of(event.identity),
      now: now || DateTime.utc_now()
    }
    |> type_facts(event)
  end

  # Fakty potrzebne tylko niektórym typom zdarzeń.
  defp type_facts(facts, %{type: type, body: body, identity: identity})
       when type in ["key.add", "key.revoke"] do
    key_id = body["key"]
    %{facts | target_key: key_info(key_id), member: member_info(identity, key_id)}
  end

  defp type_facts(facts, %{type: type, body: body, identity: identity})
       when type in ["auth_key.add", "auth_key.revoke"] do
    key_id = body["key"]

    member =
      if is_binary(key_id),
        do:
          Repo.one(
            from l in IdentityAuthKey,
              where: l.identity_id == ^identity and l.key_id == ^key_id,
              select: %{status: l.status}
          )

    count =
      Repo.aggregate(
        from(l in IdentityAuthKey, where: l.identity_id == ^identity and l.status == :active),
        :count
      )

    %{facts | target_key: key_info(key_id), member: member, auth_count: count}
  end

  defp type_facts(facts, %{type: type, body: body, identity: identity})
       when type in ["resource.put", "resource.delete"] do
    %{facts | resource: resource_info(identity, body["path"])}
  end

  defp type_facts(facts, _event), do: facts

  defp member_info(identity_id, key_id) when is_binary(key_id),
    do:
      Repo.one(
        from m in IdentitySigningKey,
          where: m.identity_id == ^identity_id and m.key_id == ^key_id,
          select: %{status: m.status}
      )

  defp member_info(_identity_id, _key_id), do: nil

  defp resource_info(identity_id, path) when is_binary(path),
    do:
      Repo.one(
        from r in Resource,
          where: r.identity_id == ^identity_id and r.path == ^path,
          select: %{kind: r.kind, hash: r.hash}
      )

  defp resource_info(_identity_id, _path), do: nil

  defp grants_of(identity_id) do
    Repo.all(
      from g in Grant,
        where: g.identity_id == ^identity_id,
        select: %{
          id: g.id,
          issuer_key_id: g.issuer_key_id,
          subject_key_id: g.subject_key_id,
          parent_grant_id: g.parent_grant_id,
          action: g.action,
          resource: g.resource,
          not_before: g.not_before,
          expires_at: g.expires_at,
          revoked_at: g.revoked_at,
          delegable: g.delegable
        }
    )
  end

  defp event_exists?(id), do: Repo.exists?(from e in Event, where: e.id == ^id)

  defp handle_taken?(handle) when is_binary(handle),
    do: Repo.exists?(from i in Identity, where: i.handle == ^handle)

  defp handle_taken?(_other), do: false

  defp identity_info(id) when is_binary(id),
    do: Repo.one(from i in Identity, where: i.id == ^id, select: %{id: i.id, profile: i.profile})

  defp latest_event(identity_id) do
    Repo.one(
      from e in Event,
        where: e.identity_id == ^identity_id,
        order_by: [desc: e.seq],
        limit: 1,
        select: %{seq: e.seq, id: e.id}
    )
  end

  defp founding_key_id(identity_id) do
    Repo.one(
      from e in Event,
        where: e.identity_id == ^identity_id and e.seq == 0,
        select: e.signer_key_id
    )
  end

  defp key_info(id) when is_binary(id),
    do: Repo.one(from k in Key, where: k.id == ^id, select: %{kind: k.kind, status: k.status})

  defp key_info(_other), do: nil

  defp key_infos([]), do: %{}

  defp key_infos(ids) do
    from(k in Key, where: k.id in ^ids, select: {k.id, %{kind: k.kind, status: k.status}})
    |> Repo.all()
    |> Map.new()
  end

  defp auth_key_ids(%{"auth_keys" => ids}) when is_list(ids), do: Enum.filter(ids, &is_binary/1)
  defp auth_key_ids(_body), do: []

  # zapis

  defp apply_op({:identity, attrs}, at), do: insert!(Identity, attrs, at)
  defp apply_op({:key, attrs}, at), do: insert!(Key, attrs, at)
  defp apply_op({:event, attrs}, at), do: insert!(Event, attrs, at)
  defp apply_op({:auth_link, attrs}, at), do: insert!(IdentityAuthKey, attrs, at)
  defp apply_op({:grant, attrs}, at), do: insert!(Grant, attrs, at)

  # Projekcja profilu: planner dał cały nowy profil. Odczyt i zapis są w tej samej
  # transakcji `BEGIN IMMEDIATE`, więc nikt nie zmieni profilu pomiędzy nimi.
  defp apply_op({:visibility, %{identity_id: id, visibility: visibility}}, at) do
    changeset =
      Identity
      |> Repo.get!(id)
      |> Identity.visibility_changeset(%{visibility: visibility})
      |> stamp([:updated_at], at)

    case Repo.update(changeset) do
      {:ok, _identity} -> :ok
      {:error, changeset} -> Repo.rollback({:rejected, Identity, changeset_errors(changeset)})
    end
  end

  defp apply_op({:profile, %{identity_id: id, profile: profile}}, at) do
    identity = Repo.get!(Identity, id)

    changeset =
      identity
      |> Identity.profile_changeset(%{profile: profile})
      |> stamp([:updated_at], at)

    case Repo.update(changeset) do
      {:ok, _identity} -> :ok
      {:error, changeset} -> Repo.rollback({:rejected, Identity, changeset_errors(changeset)})
    end
  end

  # Cofnięcie grantu: `at` pochodzi z plannera (czas przyjęcia zdarzenia), więc
  # odtworzenie daje to samo `revoked_at`.
  defp apply_op({:grant_revoke, %{id: id, at: at}}, _received_at) do
    revoke_grants(from(g in Grant, where: g.id == ^id), at)
  end

  # Klucz logowania dopisany do tożsamości (albo ponownie włączony po cofnięciu).
  defp apply_op({:auth_link_set, attrs}, at) do
    case Repo.get_by(IdentityAuthKey, identity_id: attrs.identity_id, key_id: attrs.key_id) do
      nil ->
        insert!(IdentityAuthKey, attrs, at)

      existing ->
        changeset = existing |> IdentityAuthKey.changeset(attrs) |> stamp([:updated_at], at)

        case Repo.update(changeset) do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            Repo.rollback({:rejected, IdentityAuthKey, changeset_errors(changeset)})
        end
    end
  end

  defp apply_op(
         {:auth_link_revoke, %{identity_id: identity_id, key_id: key_id, at: at}},
         _received_at
       ) do
    from(l in IdentityAuthKey, where: l.identity_id == ^identity_id and l.key_id == ^key_id)
    |> Repo.update_all(
      set: [status: :revoked, updated_at: NaiveDateTime.truncate(DateTime.to_naive(at), :second)]
    )

    :ok
  end

  # Członkostwo klucza sygnowania: dopisanie albo ponowne włączenie po cofnięciu.
  defp apply_op({:member, attrs}, at) do
    case Repo.get_by(IdentitySigningKey, identity_id: attrs.identity_id, key_id: attrs.key_id) do
      nil ->
        insert!(IdentitySigningKey, attrs, at)

      existing ->
        changeset = existing |> IdentitySigningKey.changeset(attrs) |> stamp([:updated_at], at)

        case Repo.update(changeset) do
          {:ok, _} ->
            :ok

          {:error, changeset} ->
            Repo.rollback({:rejected, IdentitySigningKey, changeset_errors(changeset)})
        end
    end
  end

  # Cofnięcie członkostwa gasi też granty, którymi ten klucz dysponował w tej tożsamości.
  defp apply_op(
         {:member_revoke, %{identity_id: identity_id, key_id: key_id, at: at}},
         _received_at
       ) do
    from(m in IdentitySigningKey, where: m.identity_id == ^identity_id and m.key_id == ^key_id)
    |> Repo.update_all(
      set: [status: :revoked, updated_at: NaiveDateTime.truncate(DateTime.to_naive(at), :second)]
    )

    revoke_grants(
      from(g in Grant, where: g.identity_id == ^identity_id and g.subject_key_id == ^key_id),
      at
    )
  end

  defp apply_op({:resource, attrs}, at) do
    case Repo.get_by(Resource, identity_id: attrs.identity_id, path: attrs.path) do
      nil ->
        insert!(Resource, attrs, at)

      existing ->
        changeset = existing |> Resource.changeset(attrs) |> stamp([:updated_at], at)

        case Repo.update(changeset) do
          {:ok, _} -> :ok
          {:error, changeset} -> Repo.rollback({:rejected, Resource, changeset_errors(changeset)})
        end
    end
  end

  defp apply_op({:resource_delete, %{identity_id: identity_id, path: path}}, _at) do
    Repo.delete_all(from r in Resource, where: r.identity_id == ^identity_id and r.path == ^path)
    :ok
  end

  # Nie nadpisuje wcześniejszego cofnięcia.
  defp revoke_grants(query, at) do
    at = DateTime.truncate(at, :second)
    Repo.update_all(from(g in query, where: is_nil(g.revoked_at)), set: [revoked_at: at])
    :ok
  end

  defp insert!(schema, attrs, received_at) do
    changeset =
      schema
      |> struct()
      |> schema.changeset(attrs)
      |> stamp([:inserted_at, :updated_at], received_at)

    case Repo.insert(changeset) do
      {:ok, _record} -> :ok
      {:error, changeset} -> Repo.rollback({:rejected, schema, changeset_errors(changeset)})
    end
  end

  # Przy odtwarzaniu wiersze dostają czas pierwotnego przyjęcia zdarzenia zamiast
  # czasu odbudowy. Ecto nie nadpisuje pól, które już ma w zmianach.
  defp stamp(changeset, _fields, nil), do: changeset

  defp stamp(changeset, fields, %DateTime{} = received_at) do
    naive = received_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
    present = changeset.data.__struct__.__schema__(:fields)

    fields
    |> Enum.filter(&(&1 in present))
    |> Enum.reduce(changeset, &Ecto.Changeset.put_change(&2, &1, naive))
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
