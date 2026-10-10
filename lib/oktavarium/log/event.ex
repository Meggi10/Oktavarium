defmodule Oktavarium.Log.Event do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "events" do
    field :seq, :integer
    field :prev, :string
    field :type, :string
    field :ts, :integer
    field :payload, :binary
    field :signature, :binary

    belongs_to :identity, Oktavarium.Identities.Identity
    belongs_to :signer_key, Oktavarium.Keys.Key

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :id,
      :identity_id,
      :seq,
      :prev,
      :type,
      :ts,
      :payload,
      :signature,
      :signer_key_id
    ])
    |> validate_required([
      :id,
      :identity_id,
      :seq,
      :type,
      :ts,
      :payload,
      :signature,
      :signer_key_id
    ])
    |> unique_constraint(:id)
    |> unique_constraint([:identity_id, :seq])
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:signer_key_id)
  end
end
