defmodule OktavariumWeb.SitePlug do
  @moduledoc false
  import Plug.Conn

  alias Oktavarium.{Blobs, Directory}

  @label ~r/\A[a-z0-9][a-z0-9-]{1,31}\z/

  @csp "default-src 'self'; img-src 'self' data:; media-src 'self'; style-src 'self' 'unsafe-inline'; " <>
         "font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"

  def init(opts), do: opts

  def call(conn, _opts) do
    domain = Application.get_env(:oktavarium, :sites_domain)

    if is_binary(domain) and String.ends_with?(conn.host, "." <> domain) do
      case site_target(conn.host, domain) do
        {:ok, target} -> serve(conn, target)
        :error -> conn |> send_resp(404, "Nie ma takiej strony.") |> halt()
      end
    else
      conn
    end
  end

  defp site_target(host, domain) do
    case project_id(host, domain) do
      {:ok, id} ->
        {:ok, {:project, id}}

      :error ->
        case handle(host, domain) do
          {:ok, label} -> {:ok, {:identity, label}}
          :error -> :error
        end
    end
  end

  @doc "Round-trippable project host: p-<lowercase base32 digest>, below 63 characters."
  def project_id(host, domain) do
    suffix = "." <> domain

    with true <- String.ends_with?(host, suffix),
         label = String.replace_suffix(host, suffix, ""),
         "p-" <> encoded <- label,
         true <- Regex.match?(~r/\A[a-z2-7]{52}\z/, encoded),
         {:ok, <<_::binary-size(32)>> = bytes} <-
           Base.decode32(String.upcase(encoded), padding: false),
         true <- String.downcase(Base.encode32(bytes, padding: false)) == encoded do
      {:ok, Oktavarium.Crypto.encode(bytes)}
    else
      _ -> :error
    end
  end

  def project_url(id) do
    domain = Application.get_env(:oktavarium, :sites_domain)

    with true <- is_binary(domain),
         {:ok, <<_::binary-size(32)>> = bytes} <- Oktavarium.Crypto.decode(id) do
      main = URI.parse(OktavariumWeb.Endpoint.url())
      port = if main.port in [nil, 80, 443], do: "", else: ":#{main.port}"
      label = "p-" <> String.downcase(Base.encode32(bytes, padding: false))
      "#{main.scheme}://#{label}.#{domain}#{port}/"
    else
      _ -> nil
    end
  end

  @doc "Uchwyt z hosta `<uchwyt>.<domena>`, jeśli host pasuje."
  @spec handle(String.t(), String.t()) :: {:ok, String.t()} | :error
  def handle(host, domain) do
    suffix = "." <> domain

    with true <- String.ends_with?(host, suffix),
         label = binary_part(host, 0, byte_size(host) - byte_size(suffix)),
         true <- Regex.match?(@label, label) do
      {:ok, label}
    else
      _ -> :error
    end
  end

  @doc "Adres strony tożsamości (`nil`, gdy nie ma domeny stron albo uchwytu pasującego do DNS)."
  @spec site_url(String.t() | nil) :: String.t() | nil
  def site_url(handle) when is_binary(handle) do
    domain = Application.get_env(:oktavarium, :sites_domain)

    if is_binary(domain) and Regex.match?(@label, handle) do
      main = URI.parse(OktavariumWeb.Endpoint.url())
      port = if main.port in [nil, 80, 443], do: "", else: ":#{main.port}"
      "#{main.scheme}://#{handle}.#{domain}#{port}/"
    end
  end

  def site_url(_other), do: nil

  # serwowanie

  defp serve(%{method: method} = conn, handle) when method in ["GET", "HEAD"] do
    with {:ok, relative} <- relative_path(conn.path_info),
         {:ok, file} <- find_file(handle, relative),
         {:ok, path} <- Blobs.path(file.hash),
         true <- File.regular?(path) do
      etag = ~s("#{file.hash}")

      conn =
        conn
        |> put_resp_header("content-type", content_type(file.media_type))
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-security-policy", @csp)
        |> put_resp_header("referrer-policy", "no-referrer")
        |> put_resp_header("cache-control", "no-cache")
        |> put_resp_header("etag", etag)

      if etag in get_req_header(conn, "if-none-match") do
        conn |> send_resp(304, "") |> halt()
      else
        if conn.method == "HEAD" do
          conn
          |> put_resp_header("content-length", Integer.to_string(file.size))
          |> send_resp(200, "")
          |> halt()
        else
          conn |> send_file(200, path) |> halt()
        end
      end
    else
      _ -> conn |> send_resp(404, "Nie ma takiej strony.") |> halt()
    end
  end

  defp serve(conn, _handle),
    do: conn |> put_resp_header("allow", "GET, HEAD") |> send_resp(405, "") |> halt()

  # `/blog` może być plikiem albo katalogiem z `index.html`
  defp find_file(handle, relative) do
    case site_file(handle, relative) do
      {:ok, file} -> {:ok, file}
      :error -> site_file(handle, relative <> "/index.html")
    end
  end

  defp site_file({:identity, handle}, relative), do: Directory.site_file(handle, relative)
  defp site_file({:project, id}, relative), do: Directory.project_site_file(id, relative)

  @doc false
  def relative_path(segments) do
    segments = if segments == [], do: ["index.html"], else: segments

    cond do
      Enum.any?(segments, &(&1 in ["", ".", ".."])) -> :error
      length(segments) > 8 -> :error
      true -> {:ok, Enum.join(segments, "/")}
    end
  end

  defp content_type("text/" <> _ = type), do: type <> "; charset=utf-8"
  defp content_type("application/json"), do: "application/json; charset=utf-8"
  defp content_type("image/svg+xml"), do: "image/svg+xml; charset=utf-8"
  defp content_type(type), do: type
end
