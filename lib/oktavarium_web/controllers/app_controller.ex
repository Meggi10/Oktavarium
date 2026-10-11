defmodule OktavariumWeb.AppController do
  @moduledoc false
  use OktavariumWeb, :controller

  def join(conn, _params) do
    conn
    |> assign(:page_title, "Dołącz")
    |> render(:app, page: "join", heading: "Załóż tożsamość", registration: registration())
  end

  def login(conn, _params) do
    conn
    |> assign(:page_title, "Zaloguj")
    |> render(:app, page: "login", heading: "Zaloguj się kluczem", registration: registration())
  end

  def studio(conn, _params) do
    conn
    |> assign(:page_title, "Pracownia")
    |> render(:app, page: "studio", heading: "Pracownia", registration: registration())
  end

  defp registration, do: Application.get_env(:oktavarium, :registration, :open)
end
