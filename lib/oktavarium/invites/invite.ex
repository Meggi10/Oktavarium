defmodule Oktavarium.Invites.Invite do
  @moduledoc "Zaproszenie. W bazie leży tylko skrót tokenu."
  use Ecto.Schema

  @primary_key {:token_hash, :string, autogenerate: false}

  schema "invites" do
    field :note, :string
    field :max_uses, :integer, default: 1
    field :uses, :integer, default: 0
    field :expires_at, :utc_datetime
    timestamps(updated_at: false)
  end
end
