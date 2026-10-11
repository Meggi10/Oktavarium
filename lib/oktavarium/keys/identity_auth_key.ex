defmodule Oktavarium.Keys.IdentityAuthKey do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :string

  schema "identity_auth_keys" do
    belongs_to :identity, Oktavarium.Identities.Identity, primary_key: true
    belongs_to :key, Oktavarium.Keys.Key, primary_key: true
    field :status, Ecto.Enum, values: [:active, :revoked], default: :active
    field :added_event_id, :string
    timestamps()
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:identity_id, :key_id, :status, :added_event_id])
    |> validate_required([:identity_id, :key_id, :added_event_id])
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:key_id)
    |> unique_constraint([:identity_id, :key_id])
  end
end
