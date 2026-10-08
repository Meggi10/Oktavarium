defmodule OktavariumWeb.PageController do
  use OktavariumWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
