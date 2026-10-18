defmodule OktavariumWeb.AvatarTest do
  use OktavariumWeb.ConnCase
  import Oktavarium.Fixtures

  alias Oktavarium.{Blobs, Directory, Repo}
  alias Oktavarium.Resources.Resource

  @moduletag :tmp_dir
  @first <<0x89, "PNG\r\n", 0x1A, "\n", "test-avatar-one">>
  @second <<0x89, "PNG\r\n", 0x1A, "\n", "test-avatar-two">>

  setup %{tmp_dir: dir} do
    previous = Application.fetch_env!(:oktavarium, :blob_dir)
    Application.put_env(:oktavarium, :blob_dir, dir)
    on_exit(fn -> Application.put_env(:oktavarium, :blob_dir, previous) end)
    :ok
  end

  defp photo!(identity, bytes, opts \\ %{}) do
    {:ok, blob} = Blobs.put(bytes, "image/png")

    state =
      next!(
        identity,
        "resource.put",
        Map.merge(
          %{
            "path" => "images/avatar",
            "hash" => blob.hash,
            "size" => blob.size,
            "media_type" => "image/png"
          },
          opts
        )
      )

    {state, blob}
  end

  test "public profile and index show photo, ordinary gallery does not", %{conn: conn} do
    state = found!(handle: "profile-photo")
    {_state, blob} = photo!(state, @first)

    profile = conn |> get("/i/profile-photo") |> html_response(200)
    assert profile =~ ~s(src="/blobs/#{blob.hash}")
    assert profile =~ "Zdjęcie profilowe"

    home = build_conn() |> get("/?view=people") |> html_response(200)
    assert home =~ ~s(src="/blobs/#{blob.hash}")
    assert Directory.gallery(:image) == []

    body = build_conn() |> get("/api/identities/profile-photo") |> json_response(200)
    assert body["avatar_url"] == "/blobs/" <> blob.hash
    index = build_conn() |> get("/api/identities") |> json_response(200)
    assert [%{"avatar_url" => url}] = index["identities"]
    assert url == "/blobs/" <> blob.hash
  end

  test "replacing the profile photo keeps one stable resource ID", %{conn: conn} do
    state = found!(handle: "photo-edit")
    {state, first} = photo!(state, @first)
    [before] = Repo.all(Resource) |> Enum.filter(&(&1.path == "images/avatar"))
    {_state, second} = photo!(state, @second)
    [after_resource] = Repo.all(Resource) |> Enum.filter(&(&1.path == "images/avatar"))
    assert after_resource.id == before.id
    assert after_resource.hash != first.hash
    assert after_resource.hash == second.hash
    page = conn |> get("/i/photo-edit") |> html_response(200)
    assert page =~ ~s(src="/blobs/#{second.hash}")
  end

  test "unlisted photo remains readable by address but not indexable", %{conn: conn} do
    state = found!(handle: "quiet-photo", visibility: "unlisted")
    {_state, blob} = photo!(state, @first)
    profile = conn |> get("/i/quiet-photo") |> html_response(200)
    assert profile =~ ~s(src="/blobs/#{blob.hash}")
    home = build_conn() |> get("/") |> html_response(200)
    refute home =~ "quiet-photo"
    identity = build_conn() |> get("/api/identities/quiet-photo") |> json_response(200)
    assert identity["avatar_url"] == "/blobs/" <> blob.hash
  end

  test "missing photo bytes use the initial, not a broken image", %{conn: conn} do
    state = found!(handle: "photo-missing")
    {_state, blob} = photo!(state, @first)
    {:ok, file} = Blobs.path(blob.hash)
    File.rm!(file)
    page = conn |> get("/i/photo-missing") |> html_response(200)
    refute page =~ ~s(src="/blobs/#{blob.hash}")
    assert page =~ "avatar-large"
    identity = build_conn() |> get("/api/identities/photo-missing") |> json_response(200)
    assert identity["avatar_url"] == nil
  end
end
