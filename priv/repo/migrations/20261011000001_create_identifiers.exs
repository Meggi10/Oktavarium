defmodule Oktavarium.Repo.Migrations.CreateIdentities do
  use Ecto.Migration

  def change do
    create table(:identities) do
      add :kind, :string, null: false
      add :handle, :string
      add :profile, :map, null: false, default: %{}
      add :visibility, :string, null: false, default: "public"
      add :parent_id, references(:identities, type: :string, on_delete: :restrict)

      timestamps()
    end

    # SQLite dopuszcza wiele NULL-i w indeksie unikalnym, więc handle jest opcjonalny
    create unique_index(:identities, [:handle])
    create index(:identities, [:parent_id])
    create index(:identities, [:kind])
  end
end
