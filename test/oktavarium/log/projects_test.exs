defmodule Oktavarium.Log.ProjectsTest do
  use Oktavarium.DataCase

  import Oktavarium.Fixtures

  alias Oktavarium.{Directory, Envelope, Log, Replay}
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Resources.Resource

  @hash String.duplicate("a", 64)

  defp project_body(slug, title \\ "Wspólna pracownia") do
    %{"slug" => slug, "meta" => %{"title" => title}}
  end

  defp file_body(path, extra \\ %{}) do
    Map.merge(
      %{"path" => path, "hash" => @hash, "size" => 10, "media_type" => "image/png"},
      extra
    )
  end

  defp try_event(state, type, body, signer \\ nil) do
    Envelope.sign(
      %{type: type, seq: state.seq + 1, identity: state.id, prev: state.head, body: body},
      signer || state.founder
    )
    |> Log.append()
  end

  test "projekt jest zasobem bez bloba, a jego ID to podpisane zdarzenie create" do
    a = found!()
    {a, event} = next_event!(a, "project.create", project_body("atlas"))

    assert %Resource{
             id: id,
             kind: :project,
             identity_id: identity_id,
             project_id: nil,
             path: "projects/atlas",
             hash: nil,
             size: nil,
             media_type: nil,
             meta: %{"title" => "Wspólna pracownia"}
           } = Repo.get!(Resource, event.id)

    assert id == event.id
    assert identity_id == a.id
    assert :ok == Log.verify(a.id)
    assert [%{id: ^id, path: "projects/atlas"}] = Directory.projects(Repo.get!(Identity, a.id))
  end

  test "slugi są unikalne wewnątrz tożsamości, ale nie globalnie" do
    a = found!()
    b = found!()
    {a, _} = next_event!(a, "project.create", project_body("atlas"))

    assert {:error, :project_slug_taken} = try_event(a, "project.create", project_body("atlas"))
    assert {:ok, _} = try_event(b, "project.create", project_body("atlas"))
    assert Repo.aggregate(Resource, :count) == 2
  end

  test "zmiana slugu nie może przejąć innego projektu" do
    a = found!()
    {a, first} = next_event!(a, "project.create", project_body("pierwszy"))
    {a, _second} = next_event!(a, "project.create", project_body("drugi"))

    assert {:error, :project_slug_taken} =
             try_event(a, "project.update", %{"id" => first.id, "slug" => "drugi"})

    assert Repo.get!(Resource, first.id).path == "projects/pierwszy"
  end

  test "projekt waliduje slug i metadane" do
    a = found!()

    for slug <- ["A", "", "../etc", "zla/nazwa", "-zly", String.duplicate("x", 61)] do
      assert {:error, {:invalid_body, "slug"}} =
               try_event(a, "project.create", project_body(slug))
    end

    assert {:error, {:invalid_body, "meta.title"}} =
             try_event(a, "project.create", %{"slug" => "dobry", "meta" => %{}})

    assert {:error, {:invalid_body, "meta.alt"}} =
             try_event(a, "project.create", %{
               "slug" => "dobry",
               "meta" => %{"title" => "Tytuł", "alt" => "nie dla projektów"}
             })
  end

  test "zmiana nazwy projektu i opisu nie zmienia ID ani przypisania plików" do
    a = found!()
    {a, project} = next_event!(a, "project.create", project_body("atlas"))

    {a, file} =
      next_event!(a, "resource.put", file_body("images/ok.png", %{"project_id" => project.id}))

    a =
      next!(a, "project.update", %{
        "id" => project.id,
        "slug" => "nowy-atlas",
        "meta" => %{"title" => "Atlas II", "description" => "Dalsze prace"}
      })

    assert %Resource{path: "projects/nowy-atlas", meta: %{"title" => "Atlas II"}} =
             Repo.get!(Resource, project.id)

    assert %Resource{project_id: project_id} = Repo.get!(Resource, file.id)
    assert project_id == project.id
    assert [%{id: file_id}] = Directory.project_resources(Repo.get!(Identity, a.id), project.id)
    assert file_id == file.id
    assert :ok = Log.verify(a.id)
  end

  test "ta sama ścieżka może wystąpić w różnych projektach i w przestrzeni głównej" do
    a = found!(handle: "atelier")
    {a, one} = next_event!(a, "project.create", project_body("one"))
    {a, two} = next_event!(a, "project.create", project_body("two"))
    {a, root_file} = next_event!(a, "resource.put", file_body("images/ok.png"))

    {a, first_file} =
      next_event!(a, "resource.put", file_body("images/ok.png", %{"project_id" => one.id}))

    {a, second_file} =
      next_event!(a, "resource.put", file_body("images/ok.png", %{"project_id" => two.id}))

    assert Repo.aggregate(Resource, :count) == 5
    assert Repo.get!(Resource, root_file.id).project_id == nil
    assert Repo.get!(Resource, first_file.id).project_id == one.id
    assert Repo.get!(Resource, second_file.id).project_id == two.id

    a = next!(a, "resource.delete", %{"path" => "images/ok.png", "project_id" => one.id})
    assert Repo.get(Resource, first_file.id) == nil
    assert Repo.get!(Resource, root_file.id)
    assert Repo.get!(Resource, second_file.id)
    assert :ok = Log.verify(a.id)
    assert {:ok, %{in_sync?: true}} = Replay.run()
  end

  test "strony projektów nie nadpisują strony głównej tożsamości" do
    a = found!(handle: "atelier")
    {a, project} = next_event!(a, "project.create", project_body("atlas"))

    _a =
      next!(a, "resource.put", %{
        "path" => "site/index.html",
        "hash" => @hash,
        "size" => 10,
        "media_type" => "text/html",
        "project_id" => project.id
      })

    refute Directory.has_site?(Repo.get!(Identity, a.id))
    assert :error == Directory.site_file("atelier", "index.html")
  end

  test "grant do ścieżek jednego projektu nie działa w innym projekcie" do
    a = found!()
    helper = keypair()
    a = next!(a, "key.add", %{"key" => key_id(helper)})
    {a, one} = next_event!(a, "project.create", project_body("one"))
    {a, two} = next_event!(a, "project.create", project_body("two"))
    {a, _} = grant!(a, helper, "resource.put", "/projects/" <> one.id <> "/images/*")

    {a, _event} =
      next_event!(
        a,
        "resource.put",
        file_body("images/ok.png", %{"project_id" => one.id}),
        helper
      )

    assert {:error, :not_authorized} =
             try_event(
               a,
               "resource.put",
               file_body("images/ok.png", %{"project_id" => two.id}),
               helper
             )
  end

  test "ID pliku nie zmienia się po aktualizacji, zmianie ścieżki ani projektu" do
    a = found!()
    {a, project} = next_event!(a, "project.create", project_body("atlas"))
    {a, created} = next_event!(a, "resource.put", file_body("images/original.png"))
    id = created.id

    a =
      next!(
        a,
        "resource.put",
        file_body("images/original.png", %{"hash" => String.duplicate("b", 64)})
      )

    assert Repo.get!(Resource, id).hash == String.duplicate("b", 64)

    a =
      next!(
        a,
        "resource.put",
        file_body("images/renamed.png", %{
          "id" => id,
          "project_id" => project.id
        })
      )

    assert %Resource{id: ^id, path: "images/renamed.png", project_id: project_id} =
             Repo.get!(Resource, id)

    assert project_id == project.id
    refute Repo.get_by(Resource, identity_id: a.id, path: "images/original.png")
    assert Repo.aggregate(Resource, :count) == 2

    a =
      next!(
        a,
        "resource.put",
        file_body("images/renamed.png", %{"id" => id, "project_id" => nil})
      )

    assert Repo.get!(Resource, id).project_id == nil

    a = next!(a, "resource.delete", %{"id" => id})
    assert Repo.get(Resource, id) == nil
    assert {:error, :unknown_resource} = try_event(a, "resource.delete", %{"id" => id})
  end

  test "nie pozwala ukraść ścieżki, cudzych ID i przypisywać do projektu innej tożsamości" do
    a = found!()
    b = found!()
    {a, project} = next_event!(a, "project.create", project_body("atlas"))
    {a, file_a} = next_event!(a, "resource.put", file_body("images/a.png"))
    {a, file_b} = next_event!(a, "resource.put", file_body("images/b.png"))

    assert {:error, :resource_path_taken} =
             try_event(a, "resource.put", file_body("images/b.png", %{"id" => file_a.id}))

    assert {:error, :unknown_resource} =
             try_event(b, "resource.put", file_body("images/a.png", %{"id" => file_a.id}))

    assert {:error, :unknown_project} =
             try_event(
               b,
               "resource.put",
               file_body("images/z.png", %{"project_id" => project.id})
             )

    assert {:error, :unknown_project} =
             try_event(a, "resource.put", file_body("images/z.png", %{"project_id" => file_b.id}))

    assert {:error, :unknown_resource} =
             try_event(a, "resource.delete", %{"id" => file_a.id, "path" => "images/b.png"})
  end

  test "nie można usunąć niepustego projektu ani skasować go jako pliku" do
    a = found!()
    {a, project} = next_event!(a, "project.create", project_body("atlas"))

    {a, file} =
      next_event!(a, "resource.put", file_body("images/a.png", %{"project_id" => project.id}))

    assert {:error, :project_not_empty} = try_event(a, "project.delete", %{"id" => project.id})
    assert {:error, :not_a_file} = try_event(a, "resource.delete", %{"id" => project.id})

    a = next!(a, "resource.delete", %{"id" => file.id})
    a = next!(a, "project.delete", %{"id" => project.id})
    assert Repo.get(Resource, project.id) == nil
    assert {:error, :unknown_project} = try_event(a, "project.delete", %{"id" => project.id})
  end

  test "granty dla projektów działają na dotychczasowym mechanizmie i są sprawdzane przy zmianie slug" do
    a = found!()
    key = keypair()
    a = next!(a, "key.add", %{"key" => key_id(key)})

    assert {:error, :not_authorized} = try_event(a, "project.create", project_body("atlas"), key)

    {a, _} = grant!(a, key, "project.create", "/projects/*")
    {:ok, created} = try_event(a, "project.create", project_body("atlas"), key)
    a = %{a | seq: created.seq, head: created.id}

    assert %Resource{kind: :project} = Repo.get!(Resource, created.id)

    assert {:error, :not_authorized} =
             try_event(a, "project.update", %{"id" => created.id, "slug" => "atlas-nowy"}, key)
  end

  test "Replay odtwarza projekt, przypisania i stabilne ID po ręcznym uszkodzeniu projekcji" do
    a = found!()
    {a, project} = next_event!(a, "project.create", project_body("atlas"))

    {a, file} =
      next_event!(a, "resource.put", file_body("images/ok.png", %{"project_id" => project.id}))

    _ = next!(a, "resource.put", file_body("images/now.png", %{"id" => file.id}))

    good = Replay.snapshot()
    assert {:ok, %{in_sync?: true}} = Replay.run()

    Repo.update_all(from(r in Resource, where: r.id == ^file.id), set: [project_id: nil])

    assert {:ok, %{in_sync?: false, drift: %{resources: %{changed: [{id, [:project_id]}]}}}} =
             Replay.run()

    assert id == file.id
    assert {:ok, %{applied?: true}} = Replay.run(apply: true)
    assert Replay.snapshot() == good
    assert Repo.get!(Resource, file.id).project_id == project.id
  end
end
