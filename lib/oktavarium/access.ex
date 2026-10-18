defmodule Oktavarium.Access do
  @moduledoc false

  alias Oktavarium.{Directory, Repo}
  alias Oktavarium.Keys.Key

  @doc "Public snapshot of a signing key's effective grants. Not a write token."
  def snapshot(identity, key_id, now \\ DateTime.utc_now()) do
    active? = match?(%Key{kind: :signing, status: :active}, Repo.get(Key, key_id))

    grants =
      if active? do
        identity
        |> Directory.grants(now)
        |> Enum.filter(&(&1.subject_key_id == key_id and &1.status == :active))
      else
        []
      end

    %{
      identity: identity.id,
      key: key_id,
      signing_key: active?,
      founder: active? and key_id == Directory.founding_key_id(identity),
      grants: grants,
      checked_at: now
    }
  end
end
