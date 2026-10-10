defmodule Oktavarium.Grants.Grant do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Oktavarium.Capability

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "grants" do
    field :action, :string
    field :resource, :string
    field :not_before, :utc_datetime
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :delegable, :boolean, default: false

    belongs_to :identity, Oktavarium.Identities.Identity
    belongs_to :issuer_key, Oktavarium.Keys.Key
    belongs_to :subject_key, Oktavarium.Keys.Key
    belongs_to :parent_grant, __MODULE__

    timestamps(updated_at: false)
  end

  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [
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
    ])
    |> validate_required([:id, :identity_id, :issuer_key_id, :subject_key_id, :action, :resource])
    |> validate_change(:action, fn :action, v ->
      if Capability.valid_action?(v), do: [], else: [action: "niepoprawny wzorzec akcji"]
    end)
    |> validate_change(:resource, fn :resource, v ->
      if Capability.valid_resource?(v), do: [], else: [resource: "niepoprawny wzorzec zasobu"]
    end)
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:issuer_key_id)
    |> foreign_key_constraint(:subject_key_id)
    |> foreign_key_constraint(:parent_grant_id)
  end
end
