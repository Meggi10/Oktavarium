defmodule Oktavarium.Log.Facts do
  @moduledoc false
  @type key_info :: %{kind: :signing | :auth, status: :active | :revoked}

  @type t :: %__MODULE__{
          event_exists?: boolean(),
          signer_key: key_info() | nil,
          handle_taken?: boolean(),
          keys: %{optional(String.t()) => key_info()},
          identity: map() | nil,
          head: %{seq: non_neg_integer(), id: String.t()} | nil,
          founding_key_id: String.t() | nil,
          subject_key: key_info() | nil,
          grants: [map()],
          target_key: key_info() | nil,
          member: %{status: :active | :revoked} | nil,
          resource: map() | nil,
          path_resource: map() | nil,
          project: map() | nil,
          project_children?: boolean(),
          auth_count: non_neg_integer(),
          replaying?: boolean(),
          now: DateTime.t() | nil
        }

  defstruct event_exists?: false,
            signer_key: nil,
            handle_taken?: false,
            keys: %{},
            identity: nil,
            head: nil,
            founding_key_id: nil,
            subject_key: nil,
            grants: [],
            target_key: nil,
            member: nil,
            resource: nil,
            path_resource: nil,
            project: nil,
            project_children?: false,
            auth_count: 0,
            replaying?: false,
            now: nil
end
