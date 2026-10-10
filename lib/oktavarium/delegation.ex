defmodule Oktavarium.Delegation do
  @moduledoc false
  alias Oktavarium.Capability

  @type grant :: %{
          required(:action) => String.t(),
          required(:resource) => String.t(),
          optional(any) => any
        }

  @doc "Grant absolutny dla przestrzeni tożsamości `identity_id` (bez ograniczeń czasowych)."
  @spec root(String.t()) :: grant()
  def root(identity_id) when is_binary(identity_id) do
    %{
      action: "*",
      resource: identity_id <> "/*",
      not_before: nil,
      expires_at: nil,
      revoked_at: nil
    }
  end

  @doc """
  Czy `child` może zostać wystawiony na podstawie `parent`.

  Zwraca `:ok`, `{:error, :not_covered}` albo `{:error, :window_exceeds_parent}`.
  """
  @spec delegate(grant(), grant()) :: :ok | {:error, :not_covered | :window_exceeds_parent}
  def delegate(parent, child) do
    cond do
      not Capability.covers?(parent, child) -> {:error, :not_covered}
      not window_within?(child, parent) -> {:error, :window_exceeds_parent}
      true -> :ok
    end
  end

  @doc "Czy grant obowiązuje w chwili `at` (uwzględnia okno czasowe i unieważnienie)."
  @spec active_at?(grant(), DateTime.t()) :: boolean()
  def active_at?(grant, %DateTime{} = at) do
    not_before_ok?(Map.get(grant, :not_before), at) and
      expires_ok?(Map.get(grant, :expires_at), at) and
      not revoked?(Map.get(grant, :revoked_at), at)
  end

  @doc "Czy `grant` zezwala na `action` na `resource` w chwili `at`."
  @spec permits?(grant(), String.t(), String.t(), DateTime.t()) :: boolean()
  def permits?(grant, action, resource, %DateTime{} = at) do
    active_at?(grant, at) and Capability.covers?(grant, %{action: action, resource: resource})
  end

  # okno dziecka musi mieścić się w oknie rodzica
  defp window_within?(child, parent) do
    lower_within?(Map.get(child, :not_before), Map.get(parent, :not_before)) and
      upper_within?(Map.get(child, :expires_at), Map.get(parent, :expires_at))
  end

  # brak dolnej granicy u rodzica: wszystko jest dozwolone
  defp lower_within?(_child, nil), do: true
  # rodzic ma dolną granicę, dziecko nie ma: dziecko zaczynałoby się wcześniej
  defp lower_within?(nil, _parent), do: false
  defp lower_within?(child, parent), do: DateTime.compare(child, parent) != :lt

  defp upper_within?(_child, nil), do: true
  defp upper_within?(nil, _parent), do: false
  defp upper_within?(child, parent), do: DateTime.compare(child, parent) != :gt

  defp not_before_ok?(nil, _at), do: true
  defp not_before_ok?(not_before, at), do: DateTime.compare(at, not_before) != :lt

  defp expires_ok?(nil, _at), do: true
  defp expires_ok?(expires_at, at), do: DateTime.compare(at, expires_at) == :lt

  defp revoked?(nil, _at), do: false
  defp revoked?(revoked_at, at), do: DateTime.compare(at, revoked_at) != :lt
end
