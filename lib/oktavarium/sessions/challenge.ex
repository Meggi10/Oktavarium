defmodule Oktavarium.Sessions.Challenge do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:nonce, :string, autogenerate: false}

  schema "login_challenges" do
    field :host, :string
    field :expires_at, :utc_datetime
    timestamps(updated_at: false)
  end
end
