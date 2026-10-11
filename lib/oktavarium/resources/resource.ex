defmodule Oktavarium.Resources.Resource do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :string

  schema "resources" do
    belongs_to :identity, Oktavarium.Identities.Identity, primary_key: true
    field :path, :string, primary_key: true
    field :kind, Ecto.Enum, values: [:image, :audio, :site]
    field :hash, :string
    field :size, :integer
    field :media_type, :string
    field :meta, :map, default: %{}
    field :event_id, :string
    timestamps()
  end

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [:identity_id, :path, :kind, :hash, :size, :media_type, :meta, :event_id])
    |> validate_required([:identity_id, :path, :kind, :hash, :size, :media_type, :event_id])
    |> foreign_key_constraint(:identity_id)
  end
end
