defmodule OktavariumWeb.PageController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.Directory

  def home(conn, _params) do
    conn
    |> assign(:page_title, "Tożsamości")
    |> render(:home,
      entries: Directory.list_identities(),
      images: Directory.gallery(:image),
      tracks: Directory.gallery(:audio, limit: 12)
    )
  end
end
