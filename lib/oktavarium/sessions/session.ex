defmodule Oktavarium.Sessions.Session do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:token_hash, :string, autogenerate: false}

  schema "sessions" do
    field :key_id, :string
    field :csrf, :string
    field :expires_at, :utc_datetime
    timestamps(updated_at: false)
  end
end
