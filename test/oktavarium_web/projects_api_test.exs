defmodule OktavariumWeb.ProjectsApiTest do
  use OktavariumWeb.ConnCase

  import Oktavarium.Fixtures

  @hash String.duplicate("a", 64)

  test "projekty i ich pliki są widoczne w API bez sesji również dla unlisted", %{conn: conn} do
    a = found!(handle: "ukryty", visibility: "unlisted")

    {a, project} =
      next_event!(a, "project.create", %{
        "slug" => "warsztat",
        "meta" => %{"title" => "Nasz warsztat"}
      })

    {_a, file} =
      next_event!(a, "resource.put", %{
        "path" => "images/plakat.png",
        "hash" => @hash,
        "size" => 10,
        "media_type" => "image/png",
        "project_id" => project.id
      })

    body = conn |> get(~p"/api/identities/#{a.id}") |> json_response(200)

    assert [%{"id" => id, "slug" => "warsztat", "meta" => %{"title" => "Nasz warsztat"}}] =
             body["projects"]

    assert id == project.id

    assert [%{"id" => file_id, "project_id" => project_id, "path" => "images/plakat.png"}] =
             body["resources"]

    assert file_id == file.id
    assert project_id == project.id

    assert %{"identities" => []} = build_conn() |> get(~p"/api/identities") |> json_response(200)
  end
end
