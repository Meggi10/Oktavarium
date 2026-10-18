defmodule OktavariumWeb.BlobController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.{Blobs, Directory, Resources}
  alias OktavariumWeb.ApiError

  def create(conn, _params) do
    declared = conn |> get_req_header("content-type") |> List.first()
    max = Resources.max_blob_size()

    with :ok <- check_length(conn, max),
         {:ok, bytes, conn} <- read_all(conn, max),
         {:ok, blob} <- Blobs.put(bytes, declared) do
      conn
      |> put_status(:created)
      |> json(%{hash: blob.hash, size: blob.size, media_type: blob.media_type})
    else
      {:error, reason} -> ApiError.send(conn, reason)
    end
  end

  def show(conn, %{"hash" => hash}) do
    with true <- Resources.valid_hash?(hash),
         %{media_type: type, size: size} <- Directory.public_media(hash),
         {:ok, file} <- Blobs.path(hash),
         true <- File.regular?(file) do
      conn
      |> put_resp_header("content-type", type)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
      |> put_resp_header("cross-origin-resource-policy", "same-origin")
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_header("etag", ~s("#{hash}"))
      |> put_resp_header("accept-ranges", "bytes")
      |> send_blob(file, size)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  # A source download is not an executable website. In particular, HTML/SVG/JS
  # must never run with access to the application's origin or local key vault.
  def download(conn, %{"ref" => ref, "resource_id" => id}) do
    with %{} = identity <- Directory.get_identity(ref),
         %{} = resource <- Directory.file(identity, id),
         {:ok, path} <- Blobs.path(resource.hash),
         true <- File.regular?(path) do
      filename = Path.basename(resource.path)

      conn
      |> put_resp_header("content-type", "application/octet-stream")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cross-origin-resource-policy", "same-origin")
      |> put_resp_header("cache-control", "no-store")
      |> send_file(200, path)
    else
      _ -> ApiError.send(conn, :unknown_resource)
    end
  end

  defp send_blob(conn, file, size) do
    case get_req_header(conn, "range") do
      ["bytes=" <> spec] ->
        case parse_range(spec, size) do
          {:ok, first, last} ->
            conn
            |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
            |> send_file(206, file, first, last - first + 1)

          :error ->
            conn |> put_resp_header("content-range", "bytes */#{size}") |> send_resp(416, "")
        end

      _ ->
        send_file(conn, 200, file)
    end
  end

  @doc false
  def parse_range(spec, size) do
    case Regex.run(~r/\A(\d*)-(\d*)\z/, spec) do
      [_, "", ""] ->
        :error

      [_, "", suffix] ->
        suffix_range(String.to_integer(suffix), size)

      [_, first, ""] ->
        bounded(String.to_integer(first), size - 1, size)

      [_, first, last] ->
        bounded(String.to_integer(first), min(String.to_integer(last), size - 1), size)

      _ ->
        :error
    end
  end

  defp suffix_range(0, _size), do: :error
  defp suffix_range(n, size), do: {:ok, max(size - n, 0), size - 1}

  defp bounded(first, last, size) when first <= last and first < size, do: {:ok, first, last}
  defp bounded(_first, _last, _size), do: :error

  defp check_length(conn, max) do
    case get_req_header(conn, "content-length") do
      [len] ->
        case Integer.parse(len) do
          {n, ""} when n > max -> {:error, :too_large}
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  # `read_body` oddaje porcje; przerywamy, gdy suma przekroczy limit.
  defp read_all(conn, max, acc \\ [], size \\ 0) do
    case read_body(conn, length: max + 1, read_length: 1_000_000, read_timeout: 30_000) do
      {:ok, chunk, conn} ->
        finish(conn, [acc, chunk], size + byte_size(chunk), max)

      {:more, chunk, conn} ->
        if size + byte_size(chunk) > max,
          do: {:error, :too_large},
          else: read_all(conn, max, [acc, chunk], size + byte_size(chunk))

      {:error, _reason} ->
        {:error, :invalid_body}
    end
  end

  defp finish(conn, acc, size, max) do
    if size > max, do: {:error, :too_large}, else: {:ok, IO.iodata_to_binary(acc), conn}
  end
end
