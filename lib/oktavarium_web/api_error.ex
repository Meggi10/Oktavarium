defmodule OktavariumWeb.ApiError do
  @moduledoc false
  import Plug.Conn, only: [put_status: 2]
  import Phoenix.Controller, only: [json: 2]

  @forbidden ~w(not_authorized unknown_signer not_signing_key key_revoked parent_not_delegable
                grant_inactive broken_chain registration_closed invalid_csrf invalid_invite)a
  @conflict ~w(duplicate_event bad_seq bad_prev handle_taken signing_key_already_registered conflict
               already_revoked already_member)a
  @unauthorized ~w(unauthenticated invalid_challenge bad_signature unknown_key)a
  @not_found ~w(unknown_identity unknown_resource unknown_grant blob_not_found)a

  @spec send(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def send(conn, reason) do
    {status, body} = describe(reason)
    conn |> put_status(status) |> json(%{error: body})
  end

  @spec describe(term()) :: {pos_integer(), map()}
  def describe({:invalid_envelope, reason}),
    do: {400, %{code: "invalid_envelope", reason: reason_text(reason)}}

  def describe({:bad_seq, expected}), do: {409, %{code: "bad_seq", expected_seq: expected}}
  def describe({:invalid_body, field}), do: {422, %{code: "invalid_body", field: field}}
  def describe({:not_authorized, field}), do: {403, %{code: "not_authorized", field: field}}
  def describe({:rejected, _schema, _errors}), do: {409, %{code: "conflict"}}

  def describe(reason) do
    {code, extra} = split(reason)
    {status_for(code), Map.put(extra, :code, Atom.to_string(code))}
  end

  defp split(code) when is_atom(code), do: {code, %{}}

  defp split({code, detail}) when is_atom(code) and (is_binary(detail) or is_integer(detail)),
    do: {code, %{detail: detail}}

  defp split({code, _a, _b}) when is_atom(code), do: {code, %{}}
  defp split(_other), do: {:invalid, %{}}

  defp status_for(code) when code in @not_found, do: 404
  defp status_for(code) when code in @unauthorized, do: 401
  defp status_for(:too_large), do: 413
  defp status_for(code) when code in [:unsupported_media_type, :media_type_mismatch], do: 415
  defp status_for(code) when code in @forbidden, do: 403
  defp status_for(code) when code in @conflict, do: 409
  defp status_for(_code), do: 422

  defp reason_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_text(reason) when is_binary(reason), do: reason
  defp reason_text(_reason), do: "invalid"
end
