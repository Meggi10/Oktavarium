defmodule Oktavarium.Repo.Migrations.CreateKeys do
  use Ecto.Migration

  def change do
    create table(:keys, primary_key: [name: :id, type: :string]) do
      add :kind, :string, null: false
      add :algo, :string, null: false, default: "ed25519"
      add :public_key, :binary, null: false
      add :status, :string, null: false, default: "active"
      add :home_identity_id, references(:identities, type: :string, on_delete: :restrict)

      timestamps()
    end

    create index(:keys, [:home_identity_id])
    create index(:keys, [:kind, :status])

    # klucz autoryzacji <-> tożsamość (wiele-do-wielu)
    create table(:identity_auth_keys, primary_key: false) do
      add :identity_id, references(:identities, type: :string, on_delete: :restrict),
        null: false,
        primary_key: true

      add :key_id, references(:keys, type: :string, on_delete: :restrict),
        null: false,
        primary_key: true

      add :status, :string, null: false, default: "active"
      add :added_event_id, :string, null: false

      timestamps()
    end

    create index(:identity_auth_keys, [:key_id])
  end
end
