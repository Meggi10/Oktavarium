defmodule OktavariumWeb.EventController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.{Blobs, Envelope, Invites, Log, Repo, Resources}
  alias OktavariumWeb.ApiError

  def create(conn, _params) do
    with {:ok, envelope} <- parse(conn.body_params),
         {:ok, event} <- append(envelope, conn) do
      conn
      |> put_status(:created)
      |> json(%{
        id: event.id,
        identity: event.identity || event.id,
        seq: event.seq,
        type: event.type
      })
    else
      {:error, reason} -> ApiError.send(conn, reason)
    end
  end

  def head(conn, %{"id" => id}) do
    case Log.head(id) do
      {:ok, head} -> json(conn, %{identity: id, seq: head.seq, id: head.id})
      {:error, reason} -> ApiError.send(conn, reason)
    end
  end

  def index(conn, %{"id" => id} = params) do
    with {:ok, after_seq} <- after_param(params["after"]),
         {:ok, head} <- Log.head(id) do
      envelopes = id |> Log.envelopes(after_seq) |> Enum.map(&Envelope.to_map/1)
      json(conn, %{identity: id, head: head.seq, events: envelopes})
    else
      {:error, reason} -> ApiError.send(conn, reason)
    end
  end

  defp parse(body) when is_map(body) and not is_struct(body) do
    case Envelope.from_map(body) do
      {:ok, envelope} -> {:ok, envelope}
      {:error, reason} -> {:error, {:invalid_envelope, reason}}
    end
  end

  defp parse(_other), do: {:error, {:invalid_envelope, :invalid_json}}

  # Genesis zakłada tożsamość, więc przy zamkniętej rejestracji idzie tylko przez
  # operatora. Uszkodzoną kopertę zgłosi dopiero `Log.append/1`.
  defp append(envelope, conn) do
    case Envelope.verify(envelope) do
      {:ok, %{genesis?: true}} ->
        append_genesis(envelope, conn)

      {:ok, %{type: "resource.put"} = event} ->
        with :ok <- check_blob(event.body), do: Log.append(envelope)

      _ ->
        Log.append(envelope)
    end
  end

  defp append_genesis(envelope, conn) do
    case Application.get_env(:oktavarium, :registration, :open) do
      :open ->
        Log.append(envelope)

      _closed ->
        token = conn |> get_req_header("x-oktavarium-invite") |> List.first()

        with :ok <- if(is_nil(token), do: {:error, :registration_closed}, else: :ok) do
          result =
            Repo.transaction(fn ->
              with :ok <- Invites.consume(token),
                   {:ok, event} <- Log.append(envelope) do
                event
              else
                {:error, reason} -> Repo.rollback(reason)
              end
            end)

          case result do
            {:ok, event} -> {:ok, event}
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  # Blob musi już leżeć w magazynie i zgadzać się z tym, co zdarzenie deklaruje.
  defp check_blob(body) do
    with hash when is_binary(hash) <- Map.get(body, "hash"),
         true <- Resources.valid_hash?(hash),
         %{size: size, media_type: type} <- Blobs.get(hash),
         true <- Blobs.exists?(hash) do
      if body["size"] == size and body["media_type"] == type,
        do: :ok,
        else: {:error, {:invalid_body, "size"}}
    else
      _ -> {:error, :blob_not_found}
    end
  end

  defp after_param(nil), do: {:ok, -1}

  defp after_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, {:invalid_body, "after"}}
    end
  end

  defp after_param(_value), do: {:error, {:invalid_body, "after"}}
end
