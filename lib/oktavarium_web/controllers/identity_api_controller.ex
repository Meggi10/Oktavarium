defmodule OktavariumWeb.IdentityApiController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.{Directory, Log, Sessions}
  alias OktavariumWeb.ApiError

  def show(conn, %{"ref" => ref}) do
    with %{} = identity <- visible(ref, conn.assigns[:session]),
         {:ok, head} <- Log.head(identity.id) do
      json(conn, %{
        id: identity.id,
        handle: identity.handle,
        kind: identity.kind,
        visibility: identity.visibility,
        profile: identity.profile || %{},
        founding_key: Directory.founding_key_id(identity),
        auth_keys: Directory.auth_keys(identity),
        members: Directory.members(identity),
        grants: Directory.grants(identity) |> Enum.map(&grant/1),
        resources: Directory.resources(identity) |> Enum.map(&resource/1),
        site_url:
          if(Directory.has_site?(identity), do: OktavariumWeb.SitePlug.site_url(identity.handle)),
        head: %{seq: head.seq, id: head.id}
      })
    else
      _ -> ApiError.send(conn, :unknown_identity)
    end
  end

  defp visible(ref, session) do
    Directory.get_identity(ref) || owned(ref, session)
  end

  defp owned(ref, %{key_id: key_id}) do
    case Enum.find(Sessions.identities(key_id), &(&1.id == ref or &1.handle == ref)) do
      nil -> nil
      %{id: id} -> Oktavarium.Repo.get(Oktavarium.Identities.Identity, id)
    end
  end

  defp owned(_ref, _session), do: nil

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
      path: r.path,
      kind: r.kind,
      hash: r.hash,
      size: r.size,
      media_type: r.media_type,
      meta: r.meta
    }
  end

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
