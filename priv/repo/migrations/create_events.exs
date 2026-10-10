defmodule Oktavarium.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :identity_id, references(:identities, type: :string, on_delete: :restrict),
        null: false

      add :seq, :integer, null: false
      add :prev, :string
      add :type, :string, null: false
      add :ts, :integer, null: false
      # surowe bajty ładunku dokładnie tak, jak zostały podpisane
      add :payload, :binary, null: false
      add :signature, :binary, null: false
      add :signer_key_id, references(:keys, type: :string, on_delete: :restrict), null: false

      timestamps(updated_at: false)
    end

    # jedna liniowa historia na tożsamość (brak rozwidleń)
    create unique_index(:events, [:identity_id, :seq])
    create index(:events, [:signer_key_id])
    create index(:events, [:type])
  end
end
