defmodule OktavariumWeb.ProjectIntegrationTest do
  use OktavariumWeb.ConnCase
  import Oktavarium.Fixtures

  alias Oktavarium.{Blobs, Envelope}
  alias OktavariumWeb.SitePlug

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    old = Application.fetch_env!(:oktavarium, :blob_dir)
    Application.put_env(:oktavarium, :blob_dir, dir)
    on_exit(fn -> Application.put_env(:oktavarium, :blob_dir, old) end)
    :ok
  end

  defp project(a, slug) do
    next_event!(a, "project.create", %{"slug" => slug, "meta" => %{"title" => slug}})
  end

  defp site_file(a, project_id, bytes, path \\ "site/index.html") do
    {:ok, blob} = Blobs.put(bytes, "text/html")

    next_event!(a, "resource.put", %{
      "path" => path,
      "hash" => blob.hash,
      "size" => blob.size,
      "media_type" => blob.media_type,
      "project_id" => project_id
    })
  end

  test "unlisted project details and access snapshots are public", %{conn: conn} do
    a = found!(visibility: "unlisted")
    {a, project} = project(a, "one")
    key = keypair()
    a = next!(a, "key.add", %{"key" => key_id(key)})
    {_a, grant} = grant!(a, key, "resource.put", "/projects/" <> project.id <> "/*")
    body = conn |> get(~p"/api/identities/#{a.id}/projects/#{project.id}") |> json_response(200)
    assert body["project"]["id"] == project.id
    assert body["resources"] == []
    out = build_conn() |> get(~p"/api/identities/#{a.id}/access/#{key_id(key)}")
    assert get_resp_header(out, "cache-control") == ["no-store"]
    access = json_response(out, 200)
    assert access["signing_key"] and not access["founder"]
    assert Enum.map(access["grants"], & &1["id"]) == [grant.id]
    assert %{"identities" => []} = build_conn() |> get(~p"/api/identities") |> json_response(200)
  end

  test "project details never resolve another identity's project", %{conn: conn} do
    a = found!()
    b = found!()
    {_a, project} = project(a, "one")

    assert %{"error" => %{"code" => "unknown_project"}} =
             conn |> get(~p"/api/identities/#{b.id}/projects/#{project.id}") |> json_response(404)
  end

  test "known public key without grants has an empty access snapshot", %{conn: conn} do
    a = found!()
    b = found!()

    access =
      conn |> get(~p"/api/identities/#{a.id}/access/#{key_id(b.founder)}") |> json_response(200)

    assert access["signing_key"]
    refute access["founder"]
    assert access["grants"] == []
  end

  test "signed project edits need a capability, not a login session", %{conn: conn} do
    a = found!()
    {a, project} = project(a, "one")
    key = keypair()
    a = next!(a, "key.add", %{"key" => key_id(key)})
    {a, _} = grant!(a, key, "project.update", "/projects/" <> project.id)

    envelope =
      Envelope.sign(
        %{
          type: "project.update",
          seq: a.seq + 1,
          prev: a.head,
          identity: a.id,
          body: %{"id" => project.id, "slug" => "renamed"}
        },
        key
      )

    result =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/events", Jason.encode!(Envelope.to_map(envelope)))
      |> json_response(201)

    assert result["type"] == "project.update"
  end

  test "source HTML downloads as an attachment, without exposing unrelated blobs", %{conn: conn} do
    a = found!(visibility: "unlisted")
    html = "<!doctype html><h1>Source</h1>"
    {a, resource} = site_file(a, nil, html)
    out = conn |> get(~p"/api/identities/#{a.id}/resources/#{resource.id}/download")
    assert response(out, 200) == html
    assert get_resp_header(out, "content-type") == ["application/octet-stream"]
    assert get_resp_header(out, "content-disposition") == [~s(attachment; filename="index.html")]
    assert get_resp_header(out, "content-security-policy") == ["sandbox; default-src 'none'"]
    other = found!()

    assert build_conn()
           |> get(~p"/api/identities/#{other.id}/resources/#{resource.id}/download")
           |> response(404)
  end

  test "each project has its own stable DNS origin and no application API", %{conn: conn} do
    a = found!(handle: "atlas", visibility: "unlisted")
    {a, one} = project(a, "one")
    {a, two} = project(a, "two")
    {a, _} = site_file(a, one.id, "<h1>One</h1>")
    {a, _} = site_file(a, two.id, "<h1>Two</h1>")
    url_one = SitePlug.project_url(one.id)
    url_two = SitePlug.project_url(two.id)
    host_one = URI.parse(url_one).host
    host_two = URI.parse(url_two).host
    refute host_one == host_two
    assert String.length(hd(String.split(host_one, "."))) <= 63
    assert {:ok, id} = SitePlug.project_id(host_one, "sites.test")
    assert id == one.id
    assert conn |> Map.put(:host, host_one) |> get("/") |> response(200) == "<h1>One</h1>"
    assert build_conn() |> Map.put(:host, host_two) |> get("/") |> response(200) == "<h1>Two</h1>"
    assert build_conn() |> Map.put(:host, host_one) |> get("/api/me") |> response(404)
    _a = next!(a, "project.update", %{"id" => one.id, "slug" => "renamed"})
    assert SitePlug.project_url(one.id) == url_one
    assert build_conn() |> Map.put(:host, host_one) |> get("/") |> response(200) == "<h1>One</h1>"
  end

  test "unrecognized nested sites hosts never fall through to the application", %{conn: conn} do
    assert conn |> Map.put(:host, "nested.invalid.sites.test") |> get("/studio") |> response(404)
  end

  test "HEAD on a project site returns headers, not a file body", %{conn: conn} do
    a = found!()
    {a, project} = project(a, "one")
    {_a, _} = site_file(a, project.id, "<h1>Head</h1>")
    host = URI.parse(SitePlug.project_url(project.id)).host
    out = conn |> Map.put(:host, host) |> head("/")
    assert response(out, 200) == ""
    assert get_resp_header(out, "content-length") == ["13"]
  end
end
