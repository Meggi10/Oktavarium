defmodule Oktavarium.Identities.Rules do
  @moduledoc false
  @kinds [:user, :org, :project, :repo]

  @doc "Dozwolone rodzaje tożsamości."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @doc "Zamienia nazwę rodzaju na atom (bez tworzenia nowych atomów)."
  @spec parse_kind(String.t()) :: {:ok, atom()} | :error
  def parse_kind(string) when is_binary(string) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == string)) do
      nil -> :error
      kind -> {:ok, kind}
    end
  end

  @doc "Wyrażenie regularne poprawnego uchwytu (handle)."
  @spec handle_format() :: Regex.t()
  def handle_format, do: ~r/\A[a-z0-9][a-z0-9_-]{1,31}\z/

  @spec valid_handle?(term()) :: boolean()
  def valid_handle?(handle) when is_binary(handle), do: Regex.match?(handle_format(), handle)
  def valid_handle?(_), do: false
end
