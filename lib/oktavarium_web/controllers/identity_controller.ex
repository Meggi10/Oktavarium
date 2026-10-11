defmodule OktavariumWeb.IdentityController do
  @moduledoc false
  use OktavariumWeb, :controller

  alias Oktavarium.{Directory, Log}

  def show(conn, %{"ref" => ref} = params) do
    case Directory.get_identity(ref) do
      nil ->
        raise OktavariumWeb.NotFoundError

      %{handle: handle} when is_binary(handle) and handle != ref ->
        # kanoniczny adres tożsamości z uchwytem to adres z uchwytem
        redirect(conn, to: canonical_path(handle, params))

      identity ->
        render_identity(conn, identity, before_param(params["before"]))
    end
  end

  defp render_identity(conn, identity, before) do
    {entries, next_before} = Directory.timeline(identity, before: before)
    grants = Directory.grants(identity)
    auth_keys = Directory.auth_keys(identity)

    key_ids =
      Enum.flat_map(grants, &[&1.subject_key_id, &1.issuer_key_id]) ++
        Enum.map(entries, & &1.signer) ++ Enum.flat_map(entries, &body_keys/1)

    conn
    |> assign(:page_title, title(identity))
    |> render(:show,
      identity: identity,
      founding_key: Directory.founding_key_id(identity),
      auth_keys: auth_keys,
      resources: Directory.resources(identity),
      members: Directory.members(identity),
      site_url:
        if(Directory.has_site?(identity), do: OktavariumWeb.SitePlug.site_url(identity.handle)),
      grants: grants,
      entries: entries,
      next_before: next_before,
      before: before,
      event_count: Directory.event_count(identity),
      integrity: Log.verify(identity.id),
      homes: Directory.key_homes(key_ids)
    )
  end

  defp body_keys(%{type: "grant.create", body: %{"subject" => subject}})
       when is_binary(subject), do: [subject]

  defp body_keys(%{type: type, body: %{"key" => key}})
       when type in ["key.add", "key.revoke"] and is_binary(key), do: [key]

  defp body_keys(_entry), do: []

  defp title(%{profile: %{"display_name" => name}}) when is_binary(name), do: name
  defp title(%{handle: handle}) when is_binary(handle), do: "@" <> handle
  defp title(%{id: id}), do: OktavariumWeb.Components.short(id)

  defp before_param(nil), do: nil

  defp before_param(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp before_param(_value), do: nil

  defp canonical_path(handle, %{"before" => before}) when is_binary(before),
    do: ~p"/i/#{handle}?#{[before: before]}"

  defp canonical_path(handle, _params), do: ~p"/i/#{handle}"
end
