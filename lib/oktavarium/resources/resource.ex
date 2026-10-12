defmodule Oktavarium.Resources.Resource do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "resources" do
    belongs_to :identity, Oktavarium.Identities.Identity
    # Projekt to także zasób. Zagnieżdżenie tylko o jeden poziom, bez drzewa katalogów.
    field :project_id, :string
    field :path, :string
    field :kind, Ecto.Enum, values: [:project, :image, :audio, :site]
    field :hash, :string
    field :size, :integer
    field :media_type, :string
    field :meta, :map, default: %{}
    field :meta_refs, :map, default: %{}
    field :event_id, :string
    timestamps()
  end

  def changeset(resource, attrs) do
    changeset =
      resource
      |> cast(attrs, [
        :id,
        :identity_id,
        :project_id,
        :path,
        :kind,
        :hash,
        :size,
        :media_type,
        :meta,
        :meta_refs,
        :event_id
      ])
      |> validate_required([:id, :identity_id, :path, :kind, :event_id])
      |> foreign_key_constraint(:identity_id)
      |> unique_constraint(:path, name: :resources_root_path_index)
      |> unique_constraint(:path, name: :resources_project_path_index)

    case get_field(changeset, :kind) do
      :project ->
        # Projekty nie posiadają bloba; ich opis należy do metadanych.
        changeset
        |> validate_change(:project_id, fn :project_id, id ->
          if is_nil(id), do: [], else: [project_id: "projekt nie może należeć do projektu"]
        end)

      _ ->
        validate_required(changeset, [:hash, :size, :media_type])
    end
  end
end
