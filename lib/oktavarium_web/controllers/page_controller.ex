defmodule OktavariumWeb.PageController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.Directory

  # jawna lista
  @views ~w(all images audio people projects)

  def home(conn, params) do
    view = if params["view"] in @views, do: params["view"], else: "all"

    conn
    |> assign(:page_title, "Odkrywaj")
    |> render(:home,
      view: view,
      entries: Directory.list_identities(),
      projects: if(view in ["all", "projects"], do: Directory.list_projects(), else: []),
      images: if(view in ["all", "images"], do: Directory.gallery(:image), else: []),
      tracks: if(view in ["all", "audio"], do: Directory.gallery(:audio, limit: 12), else: [])
    )
  end
end
