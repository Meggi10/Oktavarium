defmodule Oktavarium.Repo.Migrations.CreateIdentities do
  use Ecto.Migration

  def change do
    create table(:identities, primary_key: [name: :id, type: :string]) do
      add :kind, :string, null: false
      add :handle, :string
      add :profile, :map, null: false, default: %{}
      add :profile_refs, :map, null: false, default: %{}
      add :visibility, :string, null: false, default: "public"

      timestamps()
    end

    # SQLite dopuszcza wiele NULL-i w indeksie unikalnym, więc handle jest opcjonalny
    create unique_index(:identities, [:handle])
    create index(:identities, [:kind])
  end
end
