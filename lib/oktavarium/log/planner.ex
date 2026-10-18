defmodule Oktavarium.Log.Planner do
  @moduledoc false
  alias Oktavarium.{Authz, Capability, Content, Crypto, Envelope}
  alias Oktavarium.Identities.{Profile, Rules}
  alias Oktavarium.{Projects, Resources}
  alias Oktavarium.Log.Facts

  @supported_types ~w(grant.create grant.revoke profile.update identity.visibility.set key.add key.revoke auth_key.add auth_key.revoke
                      resource.put resource.delete project.create project.update project.delete)

  @type op ::
          {:identity
           | :key
           | :event
           | :auth_link
           | :grant
           | :profile
           | :visibility
           | :grant_revoke
           | :auth_link_set
           | :auth_link_revoke
           | :member
           | :member_revoke
           | :resource
           | :resource_delete, map()}

  @doc "Typy zdarzeń inne niż genesis, które planner potrafi obsłużyć."
  @spec supported_types() :: [String.t()]
  def supported_types, do: @supported_types

  @spec plan(Envelope.t(), Envelope.event(), Facts.t()) :: {:ok, [op()]} | {:error, term()}
  def plan(_envelope, _event, %Facts{event_exists?: true}), do: {:error, :duplicate_event}

  def plan(envelope, %{genesis?: true} = event, %Facts{} = facts),
    do: plan_genesis(envelope, event, facts)

  def plan(envelope, event, %Facts{} = facts), do: plan_regular(envelope, event, facts)

  # genesis

  defp plan_genesis(envelope, event, facts) do
    with :ok <- genesis_fields(event.body),
         {:ok, kind} <- genesis_kind(event.body),
         {:ok, visibility} <- genesis_visibility(event.body),
         {:ok, handle} <- genesis_handle(event.body),
         {:ok, auth_keys} <- genesis_auth_keys(event.body),
         :ok <- check(is_nil(facts.signer_key), :signing_key_already_registered),
         :ok <-
           check(
             event.signer not in Enum.map(auth_keys, &elem(&1, 0)),
             {:key_kind_conflict, event.signer}
           ),
         :ok <- check_auth_keys(auth_keys, facts.keys),
         :ok <- check(not facts.handle_taken?, :handle_taken) do
      new_auth_keys =
        for {id, public} <- auth_keys, not Map.has_key?(facts.keys, id) do
          {:key,
           %{
             id: id,
             kind: :auth,
             algo: "ed25519",
             public_key: public,
             status: :active,
             home_identity_id: nil
           }}
        end

      links =
        for {id, _public} <- auth_keys do
          {:auth_link,
           %{identity_id: event.id, key_id: id, status: :active, added_event_id: event.id}}
        end

      {:ok,
       [
         {:identity,
          %{
            id: event.id,
            kind: kind,
            handle: handle,
            profile: %{},
            profile_refs: %{},
            visibility: visibility
          }},
         {:key,
          %{
            id: event.signer,
            kind: :signing,
            algo: "ed25519",
            public_key: event.signer_public,
            status: :active,
            home_identity_id: event.id
          }}
       ] ++ new_auth_keys ++ [event_op(envelope, event)] ++ links}
    end
  end

  defp genesis_fields(body) do
    allowed = ~w(kind handle auth_keys visibility)

    case body |> Map.keys() |> Enum.sort() |> Enum.find(&(&1 not in allowed)) do
      nil -> :ok
      field -> {:error, {:invalid_body, field}}
    end
  end

  defp genesis_visibility(%{"visibility" => visibility}) do
    case Rules.parse_visibility(visibility) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_body, "visibility"}}
    end
  end

  defp genesis_visibility(_body), do: {:ok, :public}

  defp genesis_kind(%{"kind" => kind}) when is_binary(kind) do
    case Rules.parse_kind(kind) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, {:invalid_body, "kind"}}
    end
  end

  defp genesis_kind(_body), do: {:error, {:invalid_body, "kind"}}

  defp genesis_handle(%{"handle" => handle}) when not is_nil(handle) do
    if Rules.valid_handle?(handle), do: {:ok, handle}, else: {:error, {:invalid_body, "handle"}}
  end

  defp genesis_handle(_body), do: {:ok, nil}

  # zwraca listę {id, klucz publiczny} bez powtórzeń
  defp genesis_auth_keys(%{"auth_keys" => [_ | _] = ids}) do
    ids
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn
      id, {:ok, acc} when is_binary(id) ->
        case Crypto.decode_key_id(id) do
          {:ok, public} -> {:cont, {:ok, [{id, public} | acc]}}
          :error -> {:halt, {:error, {:invalid_body, "auth_keys"}}}
        end

      _other, _acc ->
        {:halt, {:error, {:invalid_body, "auth_keys"}}}
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp genesis_auth_keys(%{"auth_keys" => list}) when is_list(list),
    do: {:error, :auth_key_required}

  defp genesis_auth_keys(%{"auth_keys" => _other}), do: {:error, {:invalid_body, "auth_keys"}}
  defp genesis_auth_keys(_body), do: {:error, :auth_key_required}

  defp check_auth_keys(auth_keys, known) do
    Enum.find_value(auth_keys, :ok, fn {id, _public} ->
      case Map.get(known, id) do
        %{kind: :signing} -> {:error, {:key_kind_conflict, id}}
        %{status: :revoked} -> {:error, {:key_revoked, id}}
        _ -> nil
      end
    end)
  end

  # zdarzenia zwykłe

  defp plan_regular(envelope, event, facts) do
    with :ok <- check(event.type in @supported_types, {:unsupported_type, event.type}),
         :ok <- check_chain(event, facts),
         :ok <- check_signer(event, facts) do
      plan_type(event.type, envelope, event, facts)
    end
  end

  defp check_chain(_event, %Facts{identity: nil}), do: {:error, :unknown_identity}
  defp check_chain(_event, %Facts{head: nil}), do: {:error, :unknown_identity}

  defp check_chain(event, %Facts{head: head}) do
    expected = head.seq + 1

    cond do
      event.seq != expected -> {:error, {:bad_seq, expected}}
      event.prev != head.id -> {:error, :bad_prev}
      true -> :ok
    end
  end

  # Czy podpisujący jest znanym, aktywnym kluczem sygnowania. To, czy ma prawo do
  # danej czynności, rozstrzyga `Oktavarium.Authz` dla konkretnego typu zdarzenia.
  defp check_signer(_event, facts) do
    cond do
      is_nil(facts.signer_key) -> {:error, :unknown_signer}
      facts.signer_key.kind != :signing -> {:error, :not_signing_key}
      facts.signer_key.status != :active -> {:error, :key_revoked}
      true -> :ok
    end
  end

  defp plan_type("grant.create", envelope, event, facts) do
    body = event.body

    with {:ok, subject} <- grant_subject(body),
         {:ok, action} <- grant_action(body),
         {:ok, resource} <- grant_resource(body, event.identity),
         {:ok, not_before} <- grant_time(body, "not_before"),
         {:ok, expires_at} <- grant_time(body, "expires_at"),
         :ok <- check_window(not_before, expires_at),
         {:ok, delegable} <- grant_delegable(body),
         {:ok, parent_grant} <- grant_parent(body),
         child = %{
           action: action,
           resource: resource,
           not_before: not_before,
           expires_at: expires_at,
           delegable: delegable,
           parent_grant_id: parent_grant
         },
         :ok <-
           Authz.authorize_issue(
             child,
             event.signer,
             facts.founding_key_id,
             facts.grants,
             facts.now || DateTime.utc_now()
           ),
         :ok <- check_subject_key(facts.subject_key) do
      {:ok,
       [
         event_op(envelope, event),
         {:grant,
          %{
            id: event.id,
            identity_id: event.identity,
            issuer_key_id: event.signer,
            subject_key_id: subject,
            parent_grant_id: parent_grant,
            action: action,
            resource: resource,
            not_before: not_before,
            expires_at: expires_at,
            delegable: delegable
          }}
       ]}
    end
  end

  defp plan_type("identity.visibility.set", envelope, event, facts) do
    with {:ok, visibility} <- genesis_visibility(event.body),
         :ok <- check(Map.keys(event.body) == ["visibility"], {:invalid_body, "visibility"}),
         :ok <-
           authorize(
             event,
             facts,
             "identity.visibility.set",
             event.identity <> "/settings/visibility"
           ) do
      {:ok,
       [
         event_op(envelope, event),
         {:visibility, %{identity_id: event.identity, visibility: visibility}}
       ]}
    end
  end

  defp plan_type("profile.update", envelope, event, facts) do
    with {:ok, {values, hashes}} <-
           Content.materialize(
             Map.get(event.body, "fields"),
             envelope.attachments,
             :profile,
             facts.replaying?
           ),
         {:ok, changes} <- Profile.parse_changes_for_replay(values, facts.replaying?),
         :ok <- authorize_profile(changes, event, facts) do
      profile = Profile.apply_changes(Map.get(facts.identity, :profile), changes)
      refs = Profile.apply_changes(Map.get(facts.identity, :profile_refs), hashes)

      {:ok,
       [
         event_op(envelope, event),
         {:profile, %{identity_id: event.identity, profile: profile, profile_refs: refs}}
       ]}
    end
  end

  defp plan_type("grant.revoke", envelope, event, facts) do
    with {:ok, grant_id} <- body_id(event.body, "grant"),
         {:ok, grant} <- find(facts.grants, grant_id, :unknown_grant),
         :ok <- check(is_nil(grant.revoked_at), :already_revoked),
         :ok <- authorize_revoke(event, facts, grant) do
      {:ok, [event_op(envelope, event), {:grant_revoke, %{id: grant.id, at: now(facts)}}]}
    end
  end

  defp plan_type("key.add", envelope, event, facts) do
    with {:ok, key_id} <- body_key(event.body, "key"),
         {:ok, label} <- body_label(event.body),
         :ok <- authorize(event, facts, "key.add", event.identity <> "/keys/" <> key_id),
         :ok <- check(key_id != facts.founding_key_id, :already_member),
         :ok <- check_member_target(key_id, facts.target_key),
         :ok <-
           check(
             match?(%{status: :revoked}, facts.member) or is_nil(facts.member),
             :already_member
           ) do
      {:ok, public} = Crypto.decode_key_id(key_id)

      new_key =
        if is_nil(facts.target_key),
          do: [
            {:key,
             %{
               id: key_id,
               kind: :signing,
               algo: "ed25519",
               public_key: public,
               status: :active,
               home_identity_id: nil
             }}
          ],
          else: []

      {:ok,
       new_key ++
         [
           event_op(envelope, event),
           {:member,
            %{
              identity_id: event.identity,
              key_id: key_id,
              label: label,
              status: :active,
              added_event_id: event.id
            }}
         ]}
    end
  end

  defp plan_type("auth_key.add", envelope, event, facts) do
    with {:ok, key_id} <- body_key(event.body, "key"),
         :ok <- authorize(event, facts, "auth_key.add", event.identity <> "/auth-keys/" <> key_id),
         :ok <- check_auth_target(key_id, facts.target_key),
         :ok <- check(not match?(%{status: :active}, facts.member), :already_member) do
      {:ok, public} = Crypto.decode_key_id(key_id)

      new_key =
        if is_nil(facts.target_key),
          do: [
            {:key,
             %{id: key_id, kind: :auth, algo: "ed25519", public_key: public, status: :active}}
          ],
          else: []

      {:ok,
       new_key ++
         [
           event_op(envelope, event),
           {:auth_link_set,
            %{
              identity_id: event.identity,
              key_id: key_id,
              status: :active,
              added_event_id: event.id
            }}
         ]}
    end
  end

  defp plan_type("auth_key.revoke", envelope, event, facts) do
    with {:ok, key_id} <- body_key(event.body, "key"),
         :ok <-
           authorize(event, facts, "auth_key.revoke", event.identity <> "/auth-keys/" <> key_id),
         :ok <- check(match?(%{status: :active}, facts.member), :not_a_member),
         :ok <- check(facts.auth_count > 1, :last_auth_key) do
      {:ok,
       [
         event_op(envelope, event),
         {:auth_link_revoke, %{identity_id: event.identity, key_id: key_id, at: now(facts)}}
       ]}
    end
  end

  defp plan_type("key.revoke", envelope, event, facts) do
    with {:ok, key_id} <- body_key(event.body, "key"),
         :ok <- authorize(event, facts, "key.revoke", event.identity <> "/keys/" <> key_id),
         :ok <- check(key_id != facts.founding_key_id, :cannot_revoke_founding_key),
         :ok <- check(match?(%{status: :active}, facts.member), :not_a_member) do
      {:ok,
       [
         event_op(envelope, event),
         {:member_revoke, %{identity_id: event.identity, key_id: key_id, at: now(facts)}}
       ]}
    end
  end

  defp plan_type("resource.put", envelope, event, facts) do
    with {:ok, {meta, hashes}} <-
           Content.materialize(
             Map.get(event.body, "meta", %{}),
             envelope.attachments,
             :meta,
             facts.replaying?
           ),
         {:ok, put} <- Resources.parse_put(Map.put(event.body, "meta", meta)),
         {:ok, attrs} <- resource_put_attrs(Map.put(put, :meta_refs, hashes), event, facts),
         :ok <-
           authorize(
             event,
             facts,
             Resources.put_action(),
             Resources.resource(event.identity, put.path, attrs.project_id)
           ),
         :ok <-
           authorize_old_path(
             event,
             facts,
             Resources.delete_action(),
             facts.resource,
             put.path,
             attrs.project_id
           ) do
      {:ok, [event_op(envelope, event), {:resource, attrs}]}
    end
  end

  defp plan_type("resource.delete", envelope, event, facts) do
    with {:ok, selector} <- Resources.parse_delete(event.body),
         :ok <- check(not is_nil(facts.resource), :unknown_resource),
         :ok <- check(facts.resource.kind != :project, :not_a_file),
         :ok <-
           check(is_nil(selector.path) or selector.path == facts.resource.path, :unknown_resource),
         :ok <-
           check(
             not Map.has_key?(event.body, "project_id") or
               selector.project_id == facts.resource.project_id,
             :unknown_resource
           ),
         :ok <-
           authorize(
             event,
             facts,
             Resources.delete_action(),
             Resources.resource(event.identity, facts.resource.path, facts.resource.project_id)
           ) do
      {:ok, [event_op(envelope, event), {:resource_delete, %{id: facts.resource.id}}]}
    end
  end

  # Projekt nie ma własnego bloba: metadane i przypisane pliki są projekcją
  # podpisanych zdarzeń w dzienniku właściciela (osoby lub kolektywu).
  defp plan_type("project.create", envelope, event, facts) do
    with {:ok, {meta, hashes}} <-
           Content.materialize(
             Map.get(event.body, "meta"),
             envelope.attachments,
             :meta,
             facts.replaying?
           ),
         {:ok, project} <- Projects.parse_create(Map.put(event.body, "meta", meta)),
         :ok <- check(is_nil(facts.path_resource), :project_slug_taken),
         :ok <-
           authorize(
             event,
             facts,
             "project.create",
             Projects.collection(event.identity)
           ) do
      attrs = %{
        id: event.id,
        identity_id: event.identity,
        project_id: nil,
        path: project.path,
        kind: :project,
        hash: nil,
        size: nil,
        media_type: nil,
        meta: project.meta,
        meta_refs: hashes,
        event_id: event.id
      }

      {:ok, [event_op(envelope, event), {:resource, attrs}]}
    end
  end

  defp plan_type("project.update", envelope, event, facts) do
    with {:ok, {meta, hashes}} <-
           project_update_content(event.body, envelope.attachments, facts.replaying?),
         {:ok, update} <-
           Projects.parse_update(
             if(meta == :unchanged, do: event.body, else: Map.put(event.body, "meta", meta))
           ),
         :ok <- check(match?(%{kind: :project}, facts.project), :unknown_project),
         path = if(update.path == :unchanged, do: facts.project.path, else: update.path),
         meta = if(update.meta == :unchanged, do: facts.project.meta, else: update.meta),
         meta_refs = if(update.meta == :unchanged, do: facts.project.meta_refs, else: hashes),
         :ok <-
           check(
             is_nil(facts.path_resource) or facts.path_resource.id == facts.project.id,
             :project_slug_taken
           ),
         :ok <-
           authorize(
             event,
             facts,
             "project.update",
             Projects.resource(event.identity, facts.project.id)
           ) do
      attrs = %{
        id: facts.project.id,
        identity_id: event.identity,
        path: path,
        kind: :project,
        meta: meta,
        meta_refs: meta_refs,
        event_id: event.id
      }

      {:ok, [event_op(envelope, event), {:resource, attrs}]}
    end
  end

  defp plan_type("project.delete", envelope, event, facts) do
    with {:ok, _project_id} <- Projects.parse_delete(event.body),
         :ok <- check(match?(%{kind: :project}, facts.project), :unknown_project),
         :ok <- check(not facts.project_children?, :project_not_empty),
         :ok <-
           authorize(
             event,
             facts,
             "project.delete",
             Projects.resource(event.identity, facts.project.id)
           ) do
      {:ok, [event_op(envelope, event), {:resource_delete, %{id: facts.project.id}}]}
    end
  end

  defp project_update_content(body, attachments, replay?) do
    if Map.has_key?(body, "meta"),
      do: Content.materialize(body["meta"], attachments, :meta, replay?) |> wrap_meta(),
      else: {:ok, {:unchanged, %{}}}
  end

  defp wrap_meta({:ok, {meta, refs}}), do: {:ok, {meta, refs}}
  defp wrap_meta(error), do: error

  # ID tworzy pierwsze zdarzenie. Nowsze zdarzenia mogą używać id zamiast
  # ścieżki jako selektora, a nawet zmienić path bez utraty tożsamości zasobu.
  # Brak id zachowuje dotychczasowe resource.put (nadpisanie po path).
  defp resource_put_attrs(put, event, facts) do
    old = facts.resource

    cond do
      not is_nil(put.id) and is_nil(old) ->
        {:error, :unknown_resource}

      not is_nil(old) and old.kind != put.kind ->
        {:error, :resource_kind_mismatch}

      not is_nil(facts.path_resource) and (is_nil(old) or facts.path_resource.id != old.id) ->
        {:error, :resource_path_taken}

      put.project_id != :unchanged and not is_nil(put.project_id) and
          not match?(%{kind: :project}, facts.project) ->
        {:error, :unknown_project}

      true ->
        project_id =
          if put.project_id == :unchanged,
            do: if(old, do: old.project_id, else: nil),
            else: put.project_id

        attrs =
          put
          |> Map.put(:id, if(old, do: old.id, else: event.id))
          |> Map.put(:identity_id, event.identity)
          |> Map.put(:project_id, project_id)
          |> Map.put(:event_id, event.id)

        {:ok, attrs}
    end
  end

  defp authorize_old_path(_event, _facts, _action, nil, _path, _project_id), do: :ok

  defp authorize_old_path(
         _event,
         _facts,
         _action,
         %{path: path, project_id: project_id},
         path,
         project_id
       ),
       do: :ok

  defp authorize_old_path(
         event,
         facts,
         action,
         %{path: path, project_id: project_id},
         _new_path,
         _new_project_id
       ),
       do: authorize(event, facts, action, Resources.resource(event.identity, path, project_id))

  # Każde zmieniane pole to osobny zasób, więc delegat z grantem na `<id>/profile/bio`
  # nie zmieni `display_name`. Błąd wskazuje pierwsze (alfabetycznie) niedozwolone pole.
  defp authorize_profile(changes, event, facts) do
    now = facts.now || DateTime.utc_now()

    changes
    |> Map.keys()
    |> Enum.sort()
    |> Enum.find_value(:ok, fn field ->
      resource = Profile.resource(event.identity, field)

      if not Authz.permits?(
           facts.grants,
           facts.founding_key_id,
           event.signer,
           Profile.action(),
           resource,
           now
         ) do
        {:error, {:not_authorized, field}}
      end
    end)
  end

  defp check_auth_target(_id, nil), do: :ok
  defp check_auth_target(id, %{kind: :signing}), do: {:error, {:key_kind_conflict, id}}
  defp check_auth_target(id, %{status: :revoked}), do: {:error, {:key_revoked, id}}
  defp check_auth_target(_id, _info), do: :ok

  # Grant cofa jego wystawca, klucz założycielski albo ktoś z capability `grant.revoke`.
  defp authorize_revoke(event, facts, grant) do
    cond do
      event.signer in [facts.founding_key_id, grant.issuer_key_id] ->
        :ok

      authorize(event, facts, "grant.revoke", grant.resource) == :ok ->
        # A project manager may revoke grants wholly inside that project,
        # but not a broader identity-wide grant or a sibling project's grant.
        :ok

      true ->
        authorize(event, facts, "grant.revoke", event.identity <> "/grants/" <> grant.id)
    end
  end

  defp authorize(event, facts, action, resource) do
    if Authz.permits?(
         facts.grants,
         facts.founding_key_id,
         event.signer,
         action,
         resource,
         now(facts)
       ),
       do: :ok,
       else: {:error, :not_authorized}
  end

  defp now(facts), do: (facts.now || DateTime.utc_now()) |> DateTime.truncate(:second)

  defp find(grants, id, error) do
    case Enum.find(grants, &(&1.id == id)) do
      nil -> {:error, error}
      grant -> {:ok, grant}
    end
  end

  defp body_id(body, field) do
    with id when is_binary(id) <- Map.get(body, field),
         {:ok, <<_::binary-size(32)>>} <- Crypto.decode(id) do
      {:ok, id}
    else
      _ -> {:error, {:invalid_body, field}}
    end
  end

  defp body_key(body, field) do
    with id when is_binary(id) <- Map.get(body, field),
         {:ok, _public} <- Crypto.decode_key_id(id) do
      {:ok, id}
    else
      _ -> {:error, {:invalid_body, field}}
    end
  end

  defp body_label(body) do
    case Map.get(body, "label") do
      nil ->
        {:ok, nil}

      label when is_binary(label) ->
        if valid_label?(label), do: {:ok, label}, else: {:error, {:invalid_body, "label"}}

      _other ->
        {:error, {:invalid_body, "label"}}
    end
  end

  defp valid_label?(label),
    do:
      label != "" and String.valid?(label) and String.length(label) <= 40 and
        not Regex.match?(~r/[\x00-\x1F\x7F\x{0085}]/u, label)

  defp check_member_target(_id, nil), do: :ok
  defp check_member_target(id, %{kind: :auth}), do: {:error, {:key_kind_conflict, id}}
  defp check_member_target(id, %{status: :revoked}), do: {:error, {:key_revoked, id}}
  defp check_member_target(_id, _info), do: :ok

  defp grant_subject(%{"subject" => subject}) when is_binary(subject) do
    case Crypto.decode_key_id(subject) do
      {:ok, _public} -> {:ok, subject}
      :error -> {:error, {:invalid_body, "subject"}}
    end
  end

  defp grant_subject(_body), do: {:error, {:invalid_body, "subject"}}

  defp grant_action(%{"action" => action}) when is_binary(action) do
    if Capability.valid_action?(action),
      do: {:ok, action},
      else: {:error, {:invalid_body, "action"}}
  end

  defp grant_action(_body), do: {:error, {:invalid_body, "action"}}

  defp grant_resource(%{"resource" => resource}, identity) when is_binary(resource) do
    if Capability.valid_resource?(resource) and Capability.in_identity?(resource, identity),
      do: {:ok, resource},
      else: {:error, {:invalid_body, "resource"}}
  end

  defp grant_resource(_body, _identity), do: {:error, {:invalid_body, "resource"}}

  defp grant_time(body, field) do
    case Map.get(body, field) do
      nil ->
        {:ok, nil}

      unix when is_integer(unix) ->
        case DateTime.from_unix(unix) do
          {:ok, datetime} -> {:ok, datetime}
          {:error, _} -> {:error, {:invalid_body, field}}
        end

      _other ->
        {:error, {:invalid_body, field}}
    end
  end

  defp grant_delegable(body) do
    case Map.get(body, "delegable") do
      nil -> {:ok, false}
      value when is_boolean(value) -> {:ok, value}
      _other -> {:error, {:invalid_body, "delegable"}}
    end
  end

  defp grant_parent(body) do
    case Map.get(body, "parent_grant") do
      nil ->
        {:ok, nil}

      id when is_binary(id) ->
        case Crypto.decode(id) do
          {:ok, <<_::binary-size(32)>>} -> {:ok, id}
          _ -> {:error, {:invalid_body, "parent_grant"}}
        end

      _other ->
        {:error, {:invalid_body, "parent_grant"}}
    end
  end

  defp check_window(%DateTime{} = not_before, %DateTime{} = expires_at) do
    if DateTime.compare(expires_at, not_before) == :gt, do: :ok, else: {:error, :invalid_window}
  end

  defp check_window(_not_before, _expires_at), do: :ok

  defp check_subject_key(nil), do: {:error, :unknown_subject_key}
  defp check_subject_key(%{kind: :signing}), do: :ok
  defp check_subject_key(_auth_key), do: {:error, :subject_not_signing_key}

  # wspólne

  defp event_op(envelope, event) do
    {:event,
     %{
       id: event.id,
       identity_id: event.identity,
       seq: event.seq,
       prev: event.prev,
       type: event.type,
       ts: event.ts,
       payload: envelope.payload,
       signature: envelope.signature,
       signer_key_id: event.signer
     }}
  end

  defp check(true, _error), do: :ok
  defp check(false, error), do: {:error, error}
end
