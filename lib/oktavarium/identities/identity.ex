defmodule Oktavarium.Identities.Identity do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  alias Oktavarium.Identities.Rules
  @kinds Rules.kinds()

  schema "identities" do
    field :kind, Ecto.Enum, values: @kinds
    field :handle, :string
    field :profile, :map, default: %{}
    field :visibility, Ecto.Enum, values: [:public, :restricted], default: :public
    belongs_to :parent, __MODULE__
    timestamps()
  end

  def kinds, do: @kinds

  @doc "Zmienia wyłącznie profil (projekcja zdarzenia `profile.update`)."
  def profile_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:profile])
    |> validate_required([:profile])
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:id, :kind, :handle, :profile, :visibility, :parent_id])
    |> validate_required([:id, :kind])
    |> validate_format(:handle, Rules.handle_format(),
      message: "dozwolone: a-z, 0-9, _ i -, 2-32 znaki"
    )
    |> unique_constraint(:handle)
    |> unique_constraint(:id)
    |> foreign_key_constraint(:parent_id)
  end
end
