defmodule Oktavarium.Capability do
  @moduledoc false
  @type t :: %{
          required(:action) => String.t(),
          required(:resource) => String.t(),
          optional(any) => any
        }

  @doc "Czy wzorzec akcji ma poprawną postać."
  @spec valid_action?(term()) :: boolean()
  def valid_action?("*"), do: true

  def valid_action?(action) when is_binary(action) do
    segments = String.split(action, ".")
    {init, last} = Enum.split(segments, -1)

    Enum.all?(init, &plain_segment?/1) and (last == ["*"] or Enum.all?(last, &plain_segment?/1))
  end

  def valid_action?(_), do: false

  @doc "Czy wzorzec zasobu ma poprawną postać."
  @spec valid_resource?(term()) :: boolean()
  def valid_resource?(resource) when is_binary(resource) and resource != "" do
    segments = String.split(resource, "/")
    {init, last} = Enum.split(segments, -1)

    Enum.all?(init, &plain_segment?/1) and (last == ["*"] or Enum.all?(last, &plain_segment?/1))
  end

  def valid_resource?(_), do: false

  @doc """
  Czy zasób należy do przestrzeni tożsamości `identity_id`, czyli czy jego pierwszy
  segment to identyfikator tej tożsamości. Identyfikatory są w base64url, więc nie
  zawierają `/` ani `*`.
  """
  @spec in_identity?(String.t(), String.t()) :: boolean()
  def in_identity?(resource, identity_id) when is_binary(resource) and is_binary(identity_id) do
    resource |> String.split("/") |> hd() == identity_id
  end

  @doc "Czy capability `parent` obejmuje capability `child`."
  @spec covers?(t(), t()) :: boolean()
  def covers?(%{action: pa, resource: pr}, %{action: ca, resource: cr}) do
    valid_action?(pa) and valid_action?(ca) and valid_resource?(pr) and valid_resource?(cr) and
      action_covers?(pa, ca) and resource_covers?(pr, cr)
  end

  defp action_covers?("*", _child), do: true

  defp action_covers?(parent, child) do
    if String.ends_with?(parent, ".*") do
      prefix = String.slice(parent, 0, String.length(parent) - 1)
      String.starts_with?(child, prefix)
    else
      parent == child
    end
  end

  defp resource_covers?(parent, child) do
    match_segments(String.split(parent, "/"), String.split(child, "/"))
  end

  defp match_segments(["*"], _child), do: true
  defp match_segments([], []), do: true
  defp match_segments([s | parent], [s | child]) when s != "*", do: match_segments(parent, child)
  defp match_segments(_, _), do: false

  defp plain_segment?(segment),
    do: segment != "" and segment != "*" and not String.contains?(segment, "*")
end
