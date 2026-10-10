defmodule Oktavarium.Keys.Key do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "keys" do
    field :kind, Ecto.Enum, values: [:signing, :auth]
    field :algo, :string, default: "ed25519"
    field :public_key, :binary
    field :status, Ecto.Enum, values: [:active, :revoked], default: :active

    belongs_to :home_identity, Oktavarium.Identities.Identity

    timestamps()
  end

  def changeset(key, attrs) do
    key
    |> cast(attrs, [:id, :kind, :algo, :public_key, :status, :home_identity_id])
    |> validate_required([:id, :kind, :public_key])
    |> validate_auth_has_no_home()
    |> unique_constraint(:id)
    |> foreign_key_constraint(:home_identity_id)
  end

  # Klucz sygnowania ma tożsamość domową tylko wtedy, gdy jest kluczem założycielskim;
  # klucz dopisany przez `key.add` (urządzenie) jest tylko członkiem tożsamości.
  # Klucz autoryzacji nigdy nie ma domu.
  defp validate_auth_has_no_home(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :home_identity_id)} do
      {:auth, id} when not is_nil(id) ->
        add_error(changeset, :home_identity_id, "klucz autoryzacji nie ma tożsamości domowej")

      _ ->
        changeset
    end
  end
end
