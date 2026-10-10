defmodule Oktavarium.Crypto do
  @moduledoc false
  @type keypair :: %{public: binary(), private: binary()}
  @type domain :: :event | :login | :event_id

  @domains %{
    event: "oktavarium/event/v1\0",
    login: "oktavarium/login/v1\0",
    event_id: "oktavarium/event-id/v1\0"
  }

  @doc "Generuje nową parę kluczy Ed25519."
  @spec generate_keypair() :: keypair()
  def generate_keypair do
    {public, private} = :crypto.generate_key(:eddsa, :ed25519)
    %{public: public, private: private}
  end

  @doc "Podpisuje `message` kluczem prywatnym w podanej domenie."
  @spec sign(domain(), binary(), binary()) :: binary()
  def sign(domain, message, private) when is_binary(message) and is_binary(private) do
    :crypto.sign(:eddsa, :none, domain_prefix(domain) <> message, [private, :ed25519])
  end

  @doc """
  Weryfikuje podpis. Zwraca `false` także przy źle sformatowanym kluczu lub podpisie
  (nigdy nie rzuca wyjątku na danych z zewnątrz).
  """
  @spec verify(domain(), binary(), binary(), binary()) :: boolean()
  def verify(domain, message, signature, public)
      when is_binary(message) and is_binary(signature) and is_binary(public) do
    :crypto.verify(:eddsa, :none, domain_prefix(domain) <> message, signature, [
      public,
      :ed25519
    ])
  rescue
    _ -> false
  end

  def verify(_domain, _message, _signature, _public), do: false

  @doc "Wyprowadza klucz publiczny z 32-bajtowego klucza prywatnego."
  @spec public_from_private(binary()) :: {:ok, binary()} | :error
  def public_from_private(private) when is_binary(private) and byte_size(private) == 32 do
    {public, _private} = :crypto.generate_key(:eddsa, :ed25519, private)
    {:ok, public}
  end

  def public_from_private(_), do: :error

  @doc "Skrót SHA-256 `bytes` w domenie identyfikatorów zdarzeń (surowe bajty)."
  @spec event_hash(binary()) :: binary()
  def event_hash(bytes) when is_binary(bytes) do
    :crypto.hash(:sha256, domain_prefix(:event_id) <> bytes)
  end

  @doc "Identyfikator klucza publicznego (tekstowy)."
  @spec key_id(binary()) :: String.t()
  def key_id(public) when byte_size(public) == 32, do: encode(public)

  @doc "Dekoduje identyfikator klucza z powrotem do 32 bajtów klucza publicznego."
  @spec decode_key_id(String.t()) :: {:ok, binary()} | :error
  def decode_key_id(id) when is_binary(id) do
    case decode(id) do
      {:ok, <<_::binary-size(32)>> = public} -> {:ok, public}
      _ -> :error
    end
  end

  @doc "base64url bez paddingu."
  @spec encode(binary()) :: String.t()
  def encode(bytes) when is_binary(bytes), do: Base.url_encode64(bytes, padding: false)

  @doc "Odwrotność `encode/1`."
  @spec decode(String.t()) :: {:ok, binary()} | :error
  def decode(string) when is_binary(string), do: Base.url_decode64(string, padding: false)

  defp domain_prefix(domain), do: Map.fetch!(@domains, domain)
end
