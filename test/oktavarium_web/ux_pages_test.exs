defmodule OktavariumWeb.UxPagesTest do
  use OktavariumWeb.ConnCase
  import Oktavarium.Fixtures
  alias Oktavarium.{Directory, Repo}
  alias Oktavarium.Log.Event

  test "project index only lists public owners; profiles link to stable project IDs" do
    a = found!(handle: "public-c2")

    {_a, p} =
      next_event!(a, "project.create", %{"slug" => "atlas", "meta" => %{"title" => "Atlas C2"}})

    b = found!(handle: "unlisted-c2", visibility: "unlisted")

    {_b, hidden} =
      next_event!(b, "project.create", %{"slug" => "quiet", "meta" => %{"title" => "Quiet C2"}})

    assert Enum.map(Directory.list_projects(), & &1.project.id) == [p.id]
    home = build_conn() |> get("/?view=projects") |> html_response(200)
    assert home =~ "Atlas C2"
    refute home =~ hidden.id
    profile = build_conn() |> get("/i/public-c2") |> html_response(200)
    assert profile =~ ~s(href="/i/public-c2/projects/#{p.id}")
  end

  test "unlisted project remains readable without cookies or a key" do
    a = found!(handle: "quiet-c2", visibility: "unlisted")

    {_a, p} =
      next_event!(a, "project.create", %{"slug" => "notes", "meta" => %{"title" => "Notes C2"}})

    conn = build_conn() |> get("/i/quiet-c2/projects/#{p.id}")
    body = html_response(conn, 200)
    assert body =~ "Notes C2"
    assert body =~ "Nieindeksowana"
    assert body =~ "Otwórz w Pracowni"
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "a project cannot be read under another owner" do
    a = found!(handle: "first-c2")
    found!(handle: "other-c2")

    {_a, p} =
      next_event!(a, "project.create", %{"slug" => "notes", "meta" => %{"title" => "Notes"}})

    assert_error_sent 404, fn -> get(build_conn(), "/i/other-c2/projects/#{p.id}") end
  end

  test "project URL redirects owner ID to handle and retains stable project ID" do
    a = found!(handle: "canonical-c2")

    {_a, p} =
      next_event!(a, "project.create", %{"slug" => "atlas", "meta" => %{"title" => "Atlas"}})

    c = get(build_conn(), "/i/#{a.id}/projects/#{p.id}")
    assert redirected_to(c) == "/i/canonical-c2/projects/#{p.id}"
  end

  test "project text is escaped and missing bytes are not rendered as broken media" do
    a = found!(handle: "safe-c2")

    {a, p} =
      next_event!(a, "project.create", %{"slug" => "safe", "meta" => %{"title" => "<b>Title</b>"}})

    {_a, _r} =
      next_event!(a, "resource.put", %{
        "project_id" => p.id,
        "path" => "images/absent.png",
        "hash" => String.duplicate("a", 64),
        "size" => 10,
        "media_type" => "image/png"
      })

    body = build_conn() |> get("/i/safe-c2/projects/#{p.id}") |> html_response(200)
    assert body =~ "&lt;b&gt;Title&lt;/b&gt;"
    refute body =~ "<b>Title</b>"
    assert body =~ "Treść niedostępna"
    refute body =~ "<img"
  end

  test "receipt lookup is public, exact, scoped to the identity and not cached" do
    a = found!(visibility: "unlisted")
    {a, e} = next_event!(a, "profile.update", %{"fields" => %{"bio" => "Receipt"}})
    stored = Repo.get!(Event, e.id)
    c = get(build_conn(), "/api/identities/#{a.id}/events/#{e.id}")
    out = json_response(c, 200)
    assert out["id"] == e.id
    assert out["identity"] == a.id
    assert out["envelope"]["payload"] == Base.url_encode64(stored.payload, padding: false)
    assert out["envelope"]["signature"] == Base.url_encode64(stored.signature, padding: false)
    assert get_resp_header(c, "cache-control") == ["no-store"]
    other = found!()

    assert %{"error" => %{"code" => "event_not_found"}} =
             build_conn()
             |> get("/api/identities/#{other.id}/events/#{e.id}")
             |> json_response(404)
  end

  test "unknown receipt is a 404, not a successful empty response" do
    a = found!()
    c = get(build_conn(), "/api/identities/#{a.id}/events/no-such-event")
    assert %{"error" => %{"code" => "event_not_found"}} = json_response(c, 404)
    assert get_resp_header(c, "cache-control") == ["no-store"]
  end
end
