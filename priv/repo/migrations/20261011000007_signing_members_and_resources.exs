defmodule Oktavarium.Repo.Migrations.SigningMembersAndResources do
  use Ecto.Migration

  def change do
    # klucz sygnowania <-> tożsamość (wiele-do-wielu): urządzenia i boty dopisane
    # zdarzeniem `key.add`. Klucz założycielski nie jest tu wpisany.
    create table(:identity_signing_keys, primary_key: false) do
      add :identity_id, references(:identities, type: :string, on_delete: :restrict),
        null: false,
        primary_key: true

      add :key_id, references(:keys, type: :string, on_delete: :restrict),
        null: false,
        primary_key: true

      add :label, :string
      add :status, :string, null: false, default: "active"
      add :added_event_id, :string, null: false

      timestamps()
    end

    create index(:identity_signing_keys, [:key_id])

    # zasoby tożsamości: wskazanie na blob (po hashu), projekcja zdarzeń resource.*
    create table(:resources, primary_key: false) do
      add :identity_id, references(:identities, type: :string, on_delete: :restrict),
        null: false,
        primary_key: true

      add :path, :string, null: false, primary_key: true
      add :kind, :string, null: false
      add :hash, :string, null: false
      add :size, :integer, null: false
      add :media_type, :string, null: false
      add :meta, :map, null: false, default: %{}
      add :event_id, :string, null: false

      timestamps()
    end

    create index(:resources, [:hash])
    create index(:resources, [:kind, :inserted_at])
  end
end
