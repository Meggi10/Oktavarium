defmodule Oktavarium.Invites do
  @moduledoc false
  import Ecto.Query

  alias Oktavarium.{Crypto, Repo}
  alias Oktavarium.Invites.Invite

  @doc """
  Tworzy zaproszenie. Opcje: `:note`, `:max_uses` (domyślnie 1), `:days` (ważność,
  domyślnie bez końca). Zwraca `{:ok, token}`.
  """
  @spec create(keyword()) :: {:ok, String.t()}
  def create(opts \\ []) do
    token = :crypto.strong_rand_bytes(24) |> Crypto.encode()

    expires_at =
      case Keyword.get(opts, :days) do
        nil ->
          nil

        days ->
          DateTime.utc_now() |> DateTime.add(days * 86_400, :second) |> DateTime.truncate(:second)
      end

    Repo.insert!(%Invite{
      token_hash: hash(token),
      note: Keyword.get(opts, :note),
      max_uses: Keyword.get(opts, :max_uses, 1),
      expires_at: expires_at
    })

    {:ok, token}
  end

  @doc "Zużywa jedno użycie. `:ok` albo `{:error, :invalid_invite}`."
  @spec consume(String.t() | nil) :: :ok | {:error, :invalid_invite}
  def consume(token) when is_binary(token) and byte_size(token) in 10..100 do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(i in Invite,
          where:
            i.token_hash == ^hash(token) and i.uses < i.max_uses and
              (is_nil(i.expires_at) or i.expires_at > ^now)
        ),
        inc: [uses: 1]
      )

    if count == 1, do: :ok, else: {:error, :invalid_invite}
  end

  def consume(_other), do: {:error, :invalid_invite}

  @doc "Lista zaproszeń (bez tokenów, których nie da się odzyskać)."
  def list do
    Repo.all(
      from i in Invite,
        order_by: [desc: i.inserted_at],
        select: map(i, [:note, :max_uses, :uses, :expires_at, :inserted_at])
    )
  end

  defp hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end
