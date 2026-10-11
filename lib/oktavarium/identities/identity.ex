defmodule Oktavarium.Identities.Identity do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  alias Oktavarium.Identities.Rules
  @kinds Rules.kinds()
  @visibilities Rules.visibilities()

  schema "identities" do
    field :kind, Ecto.Enum, values: @kinds
    field :handle, :string
    field :profile, :map, default: %{}
    field :visibility, Ecto.Enum, values: @visibilities, default: :public
    timestamps()
  end

  def kinds, do: @kinds

  @doc "Zmienia wyłącznie profil (projekcja zdarzenia `profile.update`)."
  def profile_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:profile])
    |> validate_required([:profile])
  end

  @doc "Projekcja podpisanej operacji `identity.visibility.set`."
  def visibility_changeset(identity, attrs) do
    identity
    |> cast(attrs, [:visibility])
    |> validate_required([:visibility])
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:id, :kind, :handle, :profile, :visibility])
    |> validate_required([:id, :kind])
    |> validate_format(:handle, Rules.handle_format(),
      message: "dozwolone: a-z, 0-9, _ i -, 2-32 znaki"
    )
    |> unique_constraint(:handle)
    |> unique_constraint(:id)
  end
end
