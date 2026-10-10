defmodule Oktavarium.Authz do
  @moduledoc false
  alias Oktavarium.Delegation

  @type grant :: map()

  @doc """
  Czy `signer` może wystawić grant `child` w tej tożsamości.

  `child` ma pola `:action`, `:resource`, `:not_before`, `:expires_at` oraz
  `:parent_grant_id`. Zwraca `:ok` albo błąd: `:not_authorized`,
  `:unexpected_parent_grant` (klucz założycielski nie wskazuje grantu nadrzędnego),
  `:unknown_parent_grant`, `:parent_not_delegable`, `{:grant_inactive, id}`,
  `{:broken_chain, id}`, `:not_covered`, `:window_exceeds_parent`.
  """
  @spec authorize_issue(map(), String.t(), String.t() | nil, [grant()], DateTime.t()) ::
          :ok | {:error, term()}
  def authorize_issue(%{parent_grant_id: nil}, signer, founding, _grants, _now) do
    if signer == founding, do: :ok, else: {:error, :not_authorized}
  end

  def authorize_issue(%{parent_grant_id: _parent}, signer, founding, _grants, _now)
      when signer == founding,
      do: {:error, :unexpected_parent_grant}

  def authorize_issue(%{parent_grant_id: parent_id} = child, signer, founding, grants, now) do
    index = Map.new(grants, &{&1.id, &1})

    with {:ok, parent} <- fetch(index, parent_id, :unknown_parent_grant),
         :ok <- check(parent.subject_key_id == signer, :not_authorized),
         :ok <- check(parent.delegable == true, :parent_not_delegable),
         :ok <- chain_valid(parent, index, founding, now),
         :ok <- Delegation.delegate(parent, child) do
      :ok
    end
  end

  @doc """
  Czy `key_id` ma w chwili `now` prawo do `action` na `resource` w tej tożsamości.

  Klucz założycielski ma je zawsze. 
  Inny klucz potrzebuje ważnego grantu (patrz moduł), który obejmuje akcję i zasób.
  """
  @spec permits?([grant()], String.t() | nil, String.t(), String.t(), String.t(), DateTime.t()) ::
          boolean()
  def permits?(_grants, founding, key_id, _action, _resource, _now) when key_id == founding,
    do: true

  def permits?(grants, founding, key_id, action, resource, now) do
    index = Map.new(grants, &{&1.id, &1})

    Enum.any?(grants, fn grant ->
      grant.subject_key_id == key_id and
        Delegation.permits?(grant, action, resource, now) and
        chain_valid(grant, index, founding, now) == :ok
    end)
  end

  @doc """
  Czy łańcuch grantu `grant` prowadzi do klucza założycielskiego i każde jego
  ogniwo jest w chwili `now` aktywne.
  """
  @spec chain_valid(grant(), %{optional(String.t()) => grant()}, String.t() | nil, DateTime.t()) ::
          :ok | {:error, term()}
  def chain_valid(grant, index, founding, now),
    do: chain_valid(grant, index, founding, now, MapSet.new())

  defp chain_valid(grant, index, founding, now, seen) do
    cond do
      grant.id in seen ->
        {:error, {:broken_chain, grant.id}}

      not Delegation.active_at?(grant, now) ->
        {:error, {:grant_inactive, grant.id}}

      is_nil(grant.parent_grant_id) ->
        check(grant.issuer_key_id == founding, {:broken_chain, grant.id})

      true ->
        with {:ok, parent} <- fetch(index, grant.parent_grant_id, {:broken_chain, grant.id}),
             :ok <- check(parent.subject_key_id == grant.issuer_key_id, {:broken_chain, grant.id}),
             :ok <- check(parent.delegable == true, {:broken_chain, grant.id}) do
          chain_valid(parent, index, founding, now, MapSet.put(seen, grant.id))
        end
    end
  end

  defp fetch(index, id, error) do
    case Map.fetch(index, id) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, error}
    end
  end

  defp check(true, _error), do: :ok
  defp check(false, error), do: {:error, error}
end
