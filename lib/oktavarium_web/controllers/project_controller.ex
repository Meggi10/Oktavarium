defmodule OktavariumWeb.ProjectController do
  @moduledoc false
  use OktavariumWeb, :controller
  alias Oktavarium.{Directory, Log}

  def show(conn, %{"ref" => ref, "project_id" => project_id}) do
    with %{} = identity <- Directory.get_identity(ref),
         %{} = project <- Directory.project(identity, project_id) do
      if identity.handle && identity.handle != ref do
        redirect(conn, to: ~p"/i/#{identity.handle}/projects/#{project.id}")
      else
        conn
        |> assign(:page_title, project.meta["title"] || project.path)
        |> render(:show,
          identity: identity,
          project: project,
          resources: Directory.project_resources(identity, project.id),
          integrity: Log.verify(identity.id),
          site_url:
            if(Directory.project_has_site?(project.id),
              do: OktavariumWeb.SitePlug.project_url(project.id)
            )
        )
      end
    else
      _ -> raise OktavariumWeb.NotFoundError
    end
  end
end
