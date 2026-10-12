defmodule Oktavarium.Envelope do
  @moduledoc false
  alias Oktavarium.{Content, Crypto}
  @version 2
  @genesis_type "identity.genesis"

  @enforce_keys [:payload, :signer, :signature]
  defstruct [:payload, :signer, :signature, attachments: %{}]

  @type t :: %__MODULE__{
          payload: binary(),
          signer: binary(),
          signature: binary(),
          attachments: %{optional(String.t()) => String.t()}
        }

  @type event :: %{
          id: String.t(),
          identity: String.t(),
          seq: non_neg_integer(),
          prev: String.t() | nil,
          type: String.t(),
          body: map(),
          ts: integer(),
          signer: String.t(),
          signer_public: binary(),
          genesis?: boolean()
        }

  @doc "Typ zdarzenia zakładającego tożsamość."
  def genesis_type, do: @genesis_type

  @doc """
  Buduje ładunek z `attrs` i podpisuje go kluczem `keypair`.

  `attrs`: `:type` i `:seq` są wymagane; `:identity`, `:prev` (domyślnie `nil`),
  `:body` (domyślnie `%{}`) oraz `:ts` (domyślnie teraz).
  """
  @spec sign(map(), Crypto.keypair()) :: t()
  def sign(attrs, %{public: public, private: private}) when is_map(attrs) do
    {body, attachments} = Content.detach(Map.fetch!(attrs, :type), Map.get(attrs, :body, %{}))

    payload =
      %{
        "v" => @version,
        # klucz podpisujący jest częścią podpisanej treści: id zdarzenia (a więc id
        # tożsamości) zależy od klucza, więc nikt nie przejmie cudzego id kopiując treść
        "signer" => Crypto.key_id(public),
        "identity" => Map.get(attrs, :identity),
        "seq" => Map.fetch!(attrs, :seq),
        "prev" => Map.get(attrs, :prev),
        "type" => Map.fetch!(attrs, :type),
        "body" => body,
        "ts" => Map.get_lazy(attrs, :ts, fn -> System.system_time(:second) end)
      }
      |> Jason.encode!()

    %__MODULE__{
      payload: payload,
      signer: public,
      signature: Crypto.sign(:event, payload, private),
      attachments: attachments
    }
  end

  @doc "Skrót pomocniczy: podpisuje zdarzenie genesis dla nowej tożsamości."
  @spec genesis(map(), Crypto.keypair()) :: t()
  def genesis(body, keypair) when is_map(body) do
    sign(%{type: @genesis_type, seq: 0, identity: nil, prev: nil, body: body}, keypair)
  end

  @doc """
  Weryfikuje podpis i strukturę ładunku.

  Zwraca `{:ok, event}` z już zdekodowanym zdarzeniem albo `{:error, powód}`.
  Sprawdza wyłącznie to, co wynika z samej koperty; reguły zależne od stanu
  (poprawność `seq`/`prev`, uprawnienia) należą do warstwy logu.
  """
  @spec verify(t()) :: {:ok, event()} | {:error, term()}
  def verify(%__MODULE__{} = envelope) do
    if Crypto.verify(:event, envelope.payload, envelope.signature, envelope.signer) do
      with {:ok, fields} <- decode_payload(envelope.payload),
           :ok <- check_signer(fields, envelope),
           :ok <- Content.validate_attachments(envelope.attachments, fields["body"]) do
        {:ok, build_event(fields, envelope)}
      end
    else
      {:error, :bad_signature}
    end
  end

  @doc "Identyfikator zdarzenia (skrót ładunku, tekstowo)."
  @spec id(t()) :: String.t()
  def id(%__MODULE__{payload: payload}), do: payload |> Crypto.event_hash() |> Crypto.encode()

  @doc "Postać przesyłana po sieci (mapa gotowa do zakodowania w JSON)."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = envelope) do
    data = %{
      "payload" => Crypto.encode(envelope.payload),
      "signer" => Crypto.key_id(envelope.signer),
      "signature" => Crypto.encode(envelope.signature)
    }

    if map_size(envelope.attachments) == 0,
      do: data,
      else: Map.put(data, "attachments", envelope.attachments)
  end

  @doc "Odwrotność `to_map/1`. Nie weryfikuje podpisu — użyj `verify/1`."
  @spec from_map(term()) :: {:ok, t()} | {:error, :malformed}
  def from_map(%{"payload" => payload, "signer" => signer, "signature" => signature} = data)
      when is_binary(payload) and is_binary(signer) and is_binary(signature) do
    with {:ok, payload} <- Crypto.decode(payload),
         {:ok, signer} <- Crypto.decode_key_id(signer),
         {:ok, signature} <- Crypto.decode(signature) do
      attachments = Map.get(data, "attachments", %{})

      if is_map(attachments) and not is_struct(attachments),
        do:
          {:ok,
           %__MODULE__{
             payload: payload,
             signer: signer,
             signature: signature,
             attachments: attachments
           }},
        else: {:error, :malformed}
    else
      _ -> {:error, :malformed}
    end
  end

  def from_map(_), do: {:error, :malformed}

  # wewnętrzne

  defp decode_payload(payload) do
    case Jason.decode(payload) do
      {:ok, %{"v" => @version} = fields} -> validate(fields)
      {:ok, %{"v" => _}} -> {:error, :unsupported_version}
      {:ok, _} -> {:error, {:invalid_field, "v"}}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp validate(%{"type" => type, "seq" => seq, "body" => body, "ts" => ts} = fields)
       when is_binary(type) and type != "" and is_integer(seq) and seq >= 0 and is_map(body) and
              is_integer(ts) do
    identity = Map.get(fields, "identity")
    prev = Map.get(fields, "prev")

    cond do
      not (is_nil(identity) or is_binary(identity)) -> {:error, {:invalid_field, "identity"}}
      not (is_nil(prev) or is_binary(prev)) -> {:error, {:invalid_field, "prev"}}
      type == @genesis_type -> validate_genesis(identity, seq, prev, fields)
      true -> validate_regular(identity, seq, prev, fields)
    end
  end

  defp validate(_), do: {:error, :invalid_payload}

  defp validate_genesis(nil, 0, nil, fields), do: {:ok, fields}
  defp validate_genesis(_, _, _, _), do: {:error, :invalid_genesis}

  defp validate_regular(identity, seq, prev, fields)
       when is_binary(identity) and seq >= 1 and is_binary(prev),
       do: {:ok, fields}

  defp validate_regular(_, _, _, _), do: {:error, :invalid_chain_fields}

  # klucz zadeklarowany w ładunku musi być tym, który faktycznie podpisał
  defp check_signer(%{"signer" => signer}, envelope) when is_binary(signer) do
    if signer == Crypto.key_id(envelope.signer), do: :ok, else: {:error, :signer_mismatch}
  end

  defp check_signer(_fields, _envelope), do: {:error, {:invalid_field, "signer"}}

  defp build_event(fields, envelope) do
    id = id(envelope)
    genesis? = fields["type"] == @genesis_type

    %{
      id: id,
      identity: if(genesis?, do: id, else: fields["identity"]),
      seq: fields["seq"],
      prev: fields["prev"],
      type: fields["type"],
      body: fields["body"],
      ts: fields["ts"],
      signer: Crypto.key_id(envelope.signer),
      signer_public: envelope.signer,
      genesis?: genesis?
    }
  end
end
