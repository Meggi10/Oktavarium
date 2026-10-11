defmodule OktavariumWeb.SessionController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.Sessions
  alias OktavariumWeb.{ApiError, Auth}

  def challenge(conn, _params) do
    c = Sessions.challenge(conn.host)

    json(conn, %{
      nonce: c.nonce,
      host: c.host,
      message: Sessions.challenge_message(c.host, c.nonce),
      expires_at: c.expires_at
    })
  end

  def create(conn, %{"nonce" => nonce, "key" => key, "signature" => signature}) do
    case Sessions.login(conn.host, nonce, key, signature) do
      {:ok, session} ->
        conn
        |> Auth.put_session_cookie(session.token)
        |> json(me_body(session.key_id, session.csrf))

      {:error, reason} ->
        ApiError.send(conn, reason)
    end
  end

  def create(conn, _params), do: ApiError.send(conn, {:invalid_body, "nonce"})

  def me(conn, _params) do
    case conn.assigns.session do
      nil -> ApiError.send(conn, :unauthenticated)
      session -> json(conn, me_body(session.key_id, session.csrf))
    end
  end

  def delete(conn, _params) do
    Sessions.logout(conn.cookies[Auth.cookie_name()])

    conn
    |> Auth.delete_session_cookie()
    |> json(%{ok: true})
  end

  defp me_body(key_id, csrf),
    do: %{key: key_id, csrf: csrf, identities: Sessions.identities(key_id)}
end
