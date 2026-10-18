defmodule Oktavarium.Log.ProjectPermissionsTest do
  use Oktavarium.DataCase
  import Oktavarium.Fixtures

  alias Oktavarium.{Access, Authz, Directory, Envelope, Log, Projects, Replay}
  alias Oktavarium.Identities.Identity
  alias Oktavarium.Resources.Resource

  @expiry 4_070_908_800
  @hash String.duplicate("a", 64)

  defp attempt(a, type, body, signer) do
    Envelope.sign(%{type: type, seq: a.seq + 1, identity: a.id, prev: a.head, body: body}, signer)
    |> Log.append()
  end

  defp project(a, slug) do
    next_event!(a, "project.create", %{"slug" => slug, "meta" => %{"title" => slug}})
  end

  defp file(project_id, extra \\ %{}) do
    Map.merge(
      %{
        "path" => "images/a.png",
        "project_id" => project_id,
        "hash" => @hash,
        "size" => 10,
        "media_type" => "image/png"
      },
      extra
    )
  end

  setup do
    a = found!(kind: "collective")
    helper = keypair()
    leaf = keypair()
    a = next!(a, "key.add", %{"key" => key_id(helper)})
    a = next!(a, "key.add", %{"key" => key_id(leaf)})
    {a, one} = project(a, "one")
    {a, two} = project(a, "two")
    %{a: a, helper: helper, leaf: leaf, one: one.id, two: two.id}
  end

  test "project authorization survives renaming and does not transfer to a reused slug", ctx do
    %{a: a, helper: key, one: id} = ctx
    {a, _} = grant!(a, key, "project.update", "/projects/" <> id)
    a = next!(a, "project.update", %{"id" => id, "slug" => "renamed"}, key)
    {a, other} = project(a, "one")
    a = next!(a, "project.update", %{"id" => id, "meta" => %{"title" => "Still authorized"}}, key)

    assert {:error, :not_authorized} =
             attempt(a, "project.update", %{"id" => other.id, "slug" => "stolen"}, key)

    assert Repo.get!(Resource, id).meta["title"] == "Still authorized"
    assert {:ok, %{in_sync?: true}} = Replay.run()
  end

  test "a file publisher cannot edit project metadata, root files, or a sibling project", ctx do
    %{a: a, helper: key, one: one, two: two} = ctx
    {a, _} = grant!(a, key, "resource.put", "/projects/" <> one <> "/images/*")
    a = next!(a, "resource.put", file(one), key)
    assert {:error, :not_authorized} = attempt(a, "resource.put", file(two), key)
    assert {:error, :not_authorized} = attempt(a, "resource.put", file(nil), key)

    assert {:error, :not_authorized} =
             attempt(a, "project.update", %{"id" => one, "slug" => "no"}, key)
  end

  test "moving requires source delete and destination put, preserves ID and replays", ctx do
    %{a: a, helper: key, one: one, two: two} = ctx
    {a, created} = next_event!(a, "resource.put", file(one))
    {a, _} = grant!(a, key, "resource.put", "/projects/" <> two <> "/*")
    move = file(two, %{"id" => created.id, "path" => "images/moved.png"})
    assert {:error, :not_authorized} = attempt(a, "resource.put", move, key)
    assert Repo.get!(Resource, created.id).project_id == one
    {a, _} = grant!(a, key, "resource.delete", "/projects/" <> one <> "/*")
    a = next!(a, "resource.put", move, key)
    assert Repo.get!(Resource, created.id).project_id == two
    assert Repo.get!(Resource, created.id).path == "images/moved.png"

    assert {:error, :not_authorized} =
             attempt(a, "resource.put", file(one, %{"id" => created.id}), key)

    assert :ok = Log.verify(a.id)
    assert {:ok, %{in_sync?: true}} = Replay.run()
  end

  test "source delete alone cannot move a file to an unauthorized destination", ctx do
    %{a: a, helper: key, one: one, two: two} = ctx
    {a, created} = next_event!(a, "resource.put", file(one))
    {a, _} = grant!(a, key, "resource.delete", "/projects/" <> one <> "/*")

    assert {:error, :not_authorized} =
             attempt(a, "resource.put", file(two, %{"id" => created.id}), key)

    assert Repo.get!(Resource, created.id).project_id == one
  end

  test "renaming also removes an old path and requires delete there", ctx do
    %{a: a, helper: key, one: one} = ctx
    {a, created} = next_event!(a, "resource.put", file(one))
    {a, _} = grant!(a, key, "resource.put", "/projects/" <> one <> "/images/*")

    a =
      next!(
        a,
        "resource.put",
        file(one, %{"id" => created.id, "hash" => String.duplicate("b", 64)}),
        key
      )

    renamed = file(one, %{"id" => created.id, "path" => "images/renamed.png"})
    assert {:error, :not_authorized} = attempt(a, "resource.put", renamed, key)
    {a, _} = grant!(a, key, "resource.delete", "/projects/" <> one <> "/images/a.png")
    _a = next!(a, "resource.put", renamed, key)
    assert Repo.get!(Resource, created.id).path == "images/renamed.png"
  end

  test "delegation narrows actions, project, and time; revocation cuts descendants", ctx do
    %{a: a, helper: key, leaf: leaf, one: one, two: two} = ctx

    {a, parent} =
      grant!(a, key, "resource.*", "/projects/" <> one <> "/*", %{
        "delegable" => true,
        "expires_at" => @expiry
      })

    body = %{
      "subject" => key_id(leaf),
      "action" => "resource.put",
      "resource" => Projects.resource(a.id, one) <> "/images/*",
      "parent_grant" => parent.id,
      "expires_at" => @expiry
    }

    assert {:error, :not_covered} = attempt(a, "grant.create", Map.put(body, "action", "*"), key)

    assert {:error, :not_covered} =
             attempt(
               a,
               "grant.create",
               Map.put(body, "resource", Projects.resource(a.id, two) <> "/*"),
               key
             )

    assert {:error, :window_exceeds_parent} =
             attempt(a, "grant.create", Map.put(body, "expires_at", @expiry + 1), key)

    {a, child} = next_event!(a, "grant.create", body, key)
    a = next!(a, "resource.put", file(one), leaf)
    a = next!(a, "grant.revoke", %{"grant" => parent.id})
    assert {:error, :not_authorized} = attempt(a, "resource.put", file(one), leaf)
    identity = Repo.get!(Identity, a.id)
    assert Enum.find(Directory.grants(identity), &(&1.id == child.id)).status == :broken
    assert Access.snapshot(identity, key_id(leaf)).grants == []
    assert {:ok, %{in_sync?: true}} = Replay.run()
  end

  test "project administrator cannot issue grants without a delegable parent or administer keys",
       ctx do
    %{a: a, helper: key, leaf: leaf, one: one} = ctx
    {a, parent} = grant!(a, key, "*", "/projects/" <> one <> "/*")

    body = %{
      "subject" => key_id(leaf),
      "action" => "resource.put",
      "resource" => Projects.resource(a.id, one) <> "/*",
      "parent_grant" => parent.id
    }

    assert {:error, :parent_not_delegable} = attempt(a, "grant.create", body, key)
    assert {:error, :not_authorized} = attempt(a, "key.add", %{"key" => key_id(keypair())}, key)

    assert {:error, :not_authorized} =
             attempt(a, "identity.visibility.set", %{"visibility" => "unlisted"}, key)
  end

  test "a project administrator can revoke only grants wholly in their project", ctx do
    %{a: a, helper: key, leaf: leaf, one: one, two: two} = ctx
    {a, _manager} = grant!(a, key, "*", "/projects/" <> one <> "/*")
    {a, mine} = grant!(a, leaf, "resource.put", "/projects/" <> one <> "/*")
    {a, sibling} = grant!(a, leaf, "resource.put", "/projects/" <> two <> "/*")
    {a, global} = grant!(a, leaf, "resource.put", "/*")
    assert {:error, :not_authorized} = attempt(a, "grant.revoke", %{"grant" => sibling.id}, key)
    assert {:error, :not_authorized} = attempt(a, "grant.revoke", %{"grant" => global.id}, key)
    a = next!(a, "grant.revoke", %{"grant" => mine.id}, key)
    assert :ok = Log.verify(a.id)
    assert {:ok, %{in_sync?: true}} = Replay.run()
  end

  test "revoking and re-adding a signing member does not revive their project grants", ctx do
    %{a: a, helper: key, one: one} = ctx
    {a, _} = grant!(a, key, "resource.*", "/projects/" <> one <> "/*")
    a = next!(a, "key.revoke", %{"key" => key_id(key)})
    a = next!(a, "key.add", %{"key" => key_id(key)})
    assert {:error, :not_authorized} = attempt(a, "resource.put", file(one), key)
    assert Access.snapshot(Repo.get!(Identity, a.id), key_id(key)).grants == []
  end

  test "chain validation rejects a forged broader child even if its parent is active" do
    parent = %{
      id: "parent",
      issuer_key_id: "F",
      subject_key_id: "A",
      parent_grant_id: nil,
      action: "resource.put",
      resource: "I/projects/P/*",
      delegable: true,
      not_before: nil,
      expires_at: nil,
      revoked_at: nil
    }

    child = %{
      parent
      | id: "child",
        issuer_key_id: "A",
        subject_key_id: "B",
        parent_grant_id: "parent",
        resource: "I/*"
    }

    assert {:error, {:broken_chain, "child"}} =
             Authz.chain_valid(child, %{"parent" => parent}, "F", DateTime.utc_now())

    refute Authz.permits?(
             [parent, child],
             "F",
             "B",
             "resource.put",
             "I/images/a.png",
             DateTime.utc_now()
           )
  end
end
