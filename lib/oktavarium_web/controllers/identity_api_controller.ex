defmodule OktavariumWeb.IdentityApiController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.{Access, Crypto, Directory, Log, Projects}
  alias OktavariumWeb.ApiError

  # Dostępny bez sesji katalog. Tożsamości unlisted są odczytywalne przez show/2,
  # ale nie trafiają do publicznego indeksu.
  def index(conn, _params) do
    identities =
      Directory.list_identities()
      |> Enum.map(fn %{identity: identity, avatar_hash: hash} ->
        %{
          id: identity.id,
          handle: identity.handle,
          kind: identity.kind,
          display_name: (identity.profile || %{})["display_name"],
          avatar_url: avatar_url(hash)
        }
      end)

    json(conn, %{identities: identities})
  end

  def show(conn, %{"ref" => ref}) do
    with %{} = identity <- Directory.get_identity(ref),
         {:ok, head} <- Log.head(identity.id) do
      resources = Directory.resources(identity)
      avatar = Directory.avatar(resources)

      json(conn, %{
        id: identity.id,
        handle: identity.handle,
        kind: identity.kind,
        visibility: identity.visibility,
        profile: identity.profile || %{},
        profile_refs: identity.profile_refs || %{},
        avatar_url: avatar_url(avatar && avatar.hash),
        founding_key: Directory.founding_key_id(identity),
        auth_keys: Directory.auth_keys(identity),
        members: Directory.members(identity),
        grants: Directory.grants(identity) |> Enum.map(&grant/1),
        resources: Enum.map(resources, &resource/1),
        projects: Directory.projects(identity) |> Enum.map(&project/1),
        site_url:
          if(Directory.has_site?(identity), do: OktavariumWeb.SitePlug.site_url(identity.handle)),
        integrity: if(Log.verify(identity.id) == :ok, do: "ok", else: "error"),
        head: %{seq: head.seq, id: head.id}
      })
    else
      _ -> ApiError.send(conn, :unknown_identity)
    end
  end

  def projects(conn, %{"ref" => ref}) do
    case Directory.get_identity(ref) do
      nil ->
        ApiError.send(conn, :unknown_identity)

      identity ->
        json(conn, %{
          identity: identity.id,
          projects: Enum.map(Directory.projects(identity), &project/1)
        })
    end
  end

  def project_show(conn, %{"ref" => ref, "project_id" => id}) do
    with %{} = identity <- Directory.get_identity(ref),
         %{} = entry <- Directory.project(identity, id) do
      json(conn, %{
        identity: identity.id,
        project: Map.put(project(entry), :scope, Projects.resource(identity.id, id) <> "/*"),
        resources: Enum.map(Directory.project_resources(identity, id), &resource/1)
      })
    else
      _ -> ApiError.send(conn, :unknown_project)
    end
  end

  def access(conn, %{"ref" => ref, "key" => key}) do
    with %{} = identity <- Directory.get_identity(ref),
         {:ok, _public} <- Crypto.decode_key_id(key) do
      snapshot = Access.snapshot(identity, key)

      conn
      |> put_resp_header("cache-control", "no-store")
      |> json(%{
        snapshot
        | grants: Enum.map(snapshot.grants, &grant/1),
          checked_at: iso(snapshot.checked_at)
      })
    else
      nil -> ApiError.send(conn, :unknown_identity)
      _ -> ApiError.send(conn, {:invalid_body, "key"})
    end
  end

  defp grant(g) do
    Map.take(g, [
      :id,
      :action,
      :resource,
      :delegable,
      :issuer_key_id,
      :subject_key_id,
      :parent_grant_id,
      :status
    ])
    |> Map.merge(%{
      not_before: iso(g.not_before),
      expires_at: iso(g.expires_at),
      revoked_at: iso(g.revoked_at)
    })
  end

  defp resource(r) do
    %{
      id: r.id,
      project_id: r.project_id,
      path: r.path,
      kind: r.kind,
      available: Oktavarium.Blobs.exists?(r.hash),
      hash: r.hash,
      size: r.size,
      media_type: r.media_type,
      meta: r.meta,
      meta_refs: r.meta_refs
    }
  end

  defp project(p) do
    %{
      id: p.id,
      slug: String.replace_prefix(p.path, "projects/", ""),
      meta: p.meta,
      meta_refs: p.meta_refs,
      site_url:
        if(Directory.project_has_site?(p.id), do: OktavariumWeb.SitePlug.project_url(p.id))
    }
  end

  defp avatar_url(hash) when is_binary(hash) do
    if Oktavarium.Blobs.exists?(hash), do: "/blobs/" <> hash
  end

  defp avatar_url(_), do: nil

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
