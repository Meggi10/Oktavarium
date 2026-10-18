defmodule Oktavarium.CliProjectsTest do
  use ExUnit.Case, async: false
  alias Oktavarium.{Cli, Content, Envelope, Projects}
  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    key = Path.join(dir, "sign.key")
    auth = Path.join(dir, "auth.key")
    {:ok, _} = Cli.gen_key("signing", key)
    {:ok, %{id: auth_id}} = Cli.gen_key("auth", auth)

    {:ok, %{envelope: genesis, event: event}} =
      Cli.create_identity(key, kind: "collective", auth_keys: [auth_id])

    prev = Path.join(dir, "genesis.json")
    :ok = Cli.write_envelope(prev, genesis)
    %{key: key, auth: auth, prev: prev, identity: event.id}
  end

  test "project CLI signs v2 metadata and preserves the event chain", ctx do
    assert {:ok, %{envelope: env, event: event}} =
             Cli.project_event(ctx.key, "create",
               after: ctx.prev,
               slug: "atlas",
               title: "Atlas",
               description: "Collective work"
             )

    assert {:ok, %{seq: 1, type: "project.create"}} = Envelope.verify(env)
    assert event.identity == ctx.identity
    assert event.body["meta"]["title"] == %{"sha256" => Content.hash("Atlas")}
    prev = Path.join(ctx.tmp_dir, "project.json")
    :ok = Cli.write_envelope(prev, env)

    assert {:ok, %{event: updated}} =
             Cli.project_event(ctx.key, "update", after: prev, id: event.id, slug: "new-atlas")

    assert updated.seq == 2 and updated.prev == event.id
    assert updated.body == %{"id" => event.id, "slug" => "new-atlas"}
    assert {:ok, _} = Cli.project_event(ctx.key, "delete", after: prev, id: event.id)
  end

  test "project validation runs before signing and authentication keys cannot sign", ctx do
    assert {:error, {:invalid_body, "slug"}} =
             Cli.project_event(ctx.key, "create", after: ctx.prev, slug: "../bad", title: "X")

    assert {:error, {:invalid_body, "meta.title"}} =
             Cli.project_event(ctx.key, "create", after: ctx.prev, slug: "ok")

    assert {:error, {:wrong_key_kind, :signing}} =
             Cli.project_event(ctx.auth, "create", after: ctx.prev, slug: "ok", title: "X")
  end

  test "resource CLI distinguishes preserving a project from explicit root", ctx do
    args = [
      after: ctx.prev,
      id: ctx.identity,
      path: "images/a.png",
      hash: String.duplicate("a", 64),
      size: 10,
      media_type: "image/png"
    ]

    assert {:ok, %{event: keep}} = Cli.resource_event(ctx.key, "put", args)
    refute Map.has_key?(keep.body, "project_id")
    assert {:ok, %{event: root}} = Cli.resource_event(ctx.key, "put", args ++ [root: true])
    assert Map.has_key?(root.body, "project_id") and is_nil(root.body["project_id"])

    assert {:ok, %{event: moved}} =
             Cli.resource_event(ctx.key, "put", args ++ [project: ctx.identity])

    assert moved.body["project_id"] == ctx.identity

    assert {:error, {:invalid_body, "project_id"}} =
             Cli.resource_event(ctx.key, "put", args ++ [root: true, project: ctx.identity])
  end

  test "grant CLI builds project scopes by ID and supports revocation", ctx do
    {:ok, %{id: recipient}} = Cli.gen_key("signing", Path.join(ctx.tmp_dir, "recipient.key"))

    assert {:ok, %{event: grant, envelope: env}} =
             Cli.create_grant(ctx.key,
               after: ctx.prev,
               to: recipient,
               action: "resource.put",
               project: ctx.identity,
               resource: "images/*"
             )

    assert grant.body["resource"] == Projects.resource(ctx.identity, ctx.identity) <> "/images/*"
    path = Path.join(ctx.tmp_dir, "grant.json")
    :ok = Cli.write_envelope(path, env)
    assert {:ok, %{event: revoked}} = Cli.revoke_grant(ctx.key, after: path, grant: grant.id)
    assert revoked.type == "grant.revoke" and revoked.body == %{"grant" => grant.id}
  end

  test "new Mix entrypoints accept project and resource arguments", ctx do
    out = Path.join(ctx.tmp_dir, "task-project.json")

    Mix.Tasks.Oktavarium.Project.run([
      "create",
      "--key",
      ctx.key,
      "--after",
      ctx.prev,
      "--slug",
      "task",
      "--title",
      "Task",
      "--out",
      out
    ])

    assert {:ok, %{type: "project.create"}} = Cli.read_event(out)
    deleted = Path.join(ctx.tmp_dir, "delete.json")

    Mix.Tasks.Oktavarium.Resource.run([
      "delete",
      "--key",
      ctx.key,
      "--after",
      ctx.prev,
      "--id",
      ctx.identity,
      "--out",
      deleted
    ])

    assert {:ok, %{type: "resource.delete"}} = Cli.read_event(deleted)
  end
end
