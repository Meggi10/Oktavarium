defmodule Oktavarium.Blobs.Blob do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:hash, :string, autogenerate: false}

  schema "blobs" do
    field :size, :integer
    field :media_type, :string
    timestamps(updated_at: false)
  end
end
