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

    # Projekcja podpisanych zdarzeń resource.* i project.*.
    # Id to ID zdarzenia tworzącego zasób. Ścieżka może się zmienić bez zmiany ID.
    create table(:resources, primary_key: false) do
      add :id, :string, null: false, primary_key: true
      add :identity_id, references(:identities, type: :string, on_delete: :restrict), null: false
      # Proste powiązanie z projektem w tej samej tożsamości; walidowane przez Planner.
      # Brak FK self-reference umożliwia odtwarzanie i czyszczenie projekcji w Replay.
      add :project_id, :string
      add :path, :string, null: false
      add :kind, :string, null: false
      add :hash, :string
      add :size, :integer
      add :media_type, :string
      add :meta, :map, null: false, default: %{}
      add :meta_refs, :map, null: false, default: %{}
      add :event_id, :string, null: false

      timestamps()
    end

    # Przestrzeń root oraz każdy projekt mają własne nazwy plików.
    # Dwa indeksy częściowe są potrzebne, bo SQLite dopuszcza wielokrotne NULL w UNIQUE.
    create unique_index(:resources, [:identity_id, :path],
             name: :resources_root_path_index,
             where: "project_id IS NULL"
           )

    create unique_index(:resources, [:identity_id, :project_id, :path],
             name: :resources_project_path_index,
             where: "project_id IS NOT NULL"
           )

    create index(:resources, [:project_id])
    create index(:resources, [:hash])
    create index(:resources, [:kind, :inserted_at])
  end
end
