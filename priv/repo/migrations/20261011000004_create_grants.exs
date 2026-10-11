defmodule Oktavarium.Repo.Migrations.CreateGrants do
  use Ecto.Migration

  def change do
    create table(:grants) do
      add :identity_id, references(:identities, type: :string, on_delete: :restrict),
        null: false

      add :issuer_key_id, references(:keys, type: :string, on_delete: :restrict), null: false
      add :subject_key_id, references(:keys, type: :string, on_delete: :restrict), null: false
      add :parent_grant_id, references(:grants, type: :string, on_delete: :restrict)
      add :action, :string, null: false
      add :resource, :string, null: false
      add :not_before, :utc_datetime
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(updated_at: false)
    end

    create index(:grants, [:identity_id])
    create index(:grants, [:subject_key_id])
    create index(:grants, [:issuer_key_id])
    create index(:grants, [:parent_grant_id])
  end
end
