defmodule OktavariumWeb.Auth do
  @moduledoc false
  import Plug.Conn

  alias Oktavarium.Sessions
  alias OktavariumWeb.ApiError

  @cookie "oktavarium_session"

  def cookie_name, do: @cookie

  def load_session(conn, _opts) do
    conn = fetch_cookies(conn)
    assign(conn, :session, Sessions.get(conn.cookies[@cookie]))
  end

  def require_session(%{assigns: %{session: %{}}} = conn, _opts), do: conn

  def require_session(conn, _opts), do: conn |> ApiError.send(:unauthenticated) |> halt()

  def verify_csrf(%{assigns: %{session: %{csrf: csrf}}} = conn, _opts) do
    with [given] <- get_req_header(conn, "x-csrf-token"),
         true <- byte_size(given) == byte_size(csrf) and Plug.Crypto.secure_compare(given, csrf) do
      conn
    else
      _ -> conn |> ApiError.send(:invalid_csrf) |> halt()
    end
  end

  def verify_csrf(conn, _opts), do: conn |> ApiError.send(:unauthenticated) |> halt()

  @doc "Ustawia ciasteczko sesji."
  def put_session_cookie(conn, token) do
    put_resp_cookie(conn, @cookie, token,
      http_only: true,
      same_site: "Strict",
      secure: Application.get_env(:oktavarium, :secure_cookies, false),
      max_age: Sessions.session_ttl(),
      path: "/"
    )
  end

  def delete_session_cookie(conn), do: delete_resp_cookie(conn, @cookie, path: "/")
end
