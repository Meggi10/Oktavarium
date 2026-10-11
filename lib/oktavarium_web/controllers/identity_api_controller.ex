defmodule OktavariumWeb.IdentityApiController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.{Directory, Log}
  alias OktavariumWeb.ApiError

  # Dostępny bez sesji katalog. Tożsamości unlisted są odczytywalne przez show/2,
  # ale nie trafiają do publicznego indeksu.
  def index(conn, _params) do
    identities =
      Directory.list_identities()
      |> Enum.map(fn %{identity: identity} ->
        %{
          id: identity.id,
          handle: identity.handle,
          kind: identity.kind,
          display_name: (identity.profile || %{})["display_name"]
        }
      end)

    json(conn, %{identities: identities})
  end

  def show(conn, %{"ref" => ref}) do
    with %{} = identity <- Directory.get_identity(ref),
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
