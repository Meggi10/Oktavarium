defmodule Oktavarium.Cli.Keyfile do
  @moduledoc false
  alias Oktavarium.Cli.Files
  alias Oktavarium.Crypto

  @version 1

  @type kind :: :signing | :auth
  @type t :: %{kind: kind(), public: binary(), private: binary()}

  @spec generate(kind()) :: t()
  def generate(kind) when kind in [:signing, :auth] do
    %{public: public, private: private} = Crypto.generate_keypair()
    %{kind: kind, public: public, private: private}
  end

  @doc "Identyfikator klucza (zob. `Oktavarium.Crypto.key_id/1`)."
  @spec id(t()) :: String.t()
  def id(%{public: public}), do: Crypto.key_id(public)

  @doc "Para kluczy w postaci oczekiwanej przez `Oktavarium.Crypto` i `Oktavarium.Envelope`."
  @spec keypair(t()) :: Crypto.keypair()
  def keypair(%{public: public, private: private}), do: %{public: public, private: private}

  @spec write_new(Path.t(), t()) :: :ok | {:error, term()}
  def write_new(path, %{kind: kind, public: public, private: private}) do
    content =
      Jason.encode!(
        %{
          "v" => @version,
          "kind" => Atom.to_string(kind),
          "algo" => "ed25519",
          "public" => Crypto.encode(public),
          "private" => Crypto.encode(private)
        },
        pretty: true
      )

    Files.write_new(path, content <> "\n", 0o600)
  end

  @spec read(Path.t()) :: {:ok, t()} | {:error, term()}
  def read(path) do
    with {:ok, raw} <- Files.read(path),
         {:ok, fields} <- parse(raw) do
      build(fields)
    end
  end

  defp parse(raw) do
    case Jason.decode(raw) do
      {:ok, %{} = fields} -> {:ok, fields}
      _ -> {:error, :invalid_keyfile}
    end
  end

  defp build(%{
         "v" => @version,
         "algo" => "ed25519",
         "kind" => kind,
         "public" => public,
         "private" => private
       })
       when is_binary(kind) and is_binary(public) and is_binary(private) do
    with {:ok, kind} <- parse_kind(kind),
         {:ok, public} <- Crypto.decode(public),
         {:ok, private} <- Crypto.decode(private),
         {:ok, derived} <- Crypto.public_from_private(private) do
      if derived == public do
        {:ok, %{kind: kind, public: public, private: private}}
      else
        {:error, :key_mismatch}
      end
    else
      _ -> {:error, :invalid_keyfile}
    end
  end

  defp build(_), do: {:error, :invalid_keyfile}

  defp parse_kind("signing"), do: {:ok, :signing}
  defp parse_kind("auth"), do: {:ok, :auth}
  defp parse_kind(_), do: :error
end
