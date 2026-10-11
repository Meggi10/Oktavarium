defmodule Oktavarium.Repo.Migrations.BlobsSessionsInvites do
  use Ecto.Migration

  def change do
    # bajty zasobów leżą na dysku; tabela trzyma to, co serwer ustalił przy zapisie
    create table(:blobs, primary_key: false) do
      add :hash, :string, primary_key: true
      add :size, :integer, null: false
      add :media_type, :string, null: false
      timestamps(updated_at: false)
    end

    create table(:login_challenges, primary_key: false) do
      add :nonce, :string, primary_key: true
      add :host, :string, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps(updated_at: false)
    end

    # bez klucza obcego do `keys`: odbudowa projekcji czyści klucze
    create table(:sessions, primary_key: false) do
      add :token_hash, :string, primary_key: true
      add :key_id, :string, null: false
      add :csrf, :string, null: false
      add :expires_at, :utc_datetime, null: false
      timestamps(updated_at: false)
    end

    create index(:sessions, [:key_id])
    create index(:sessions, [:expires_at])

    # zaproszenia: polityka przyjmowania nowych tożsamości przy zamkniętej rejestracji
    create table(:invites, primary_key: false) do
      add :token_hash, :string, primary_key: true
      add :note, :string
      add :max_uses, :integer, null: false, default: 1
      add :uses, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      timestamps(updated_at: false)
    end
  end
end
