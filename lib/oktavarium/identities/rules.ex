defmodule Oktavarium.Identities.Rules do
  @moduledoc false
  @kinds [:person, :collective]
  @visibilities [:public, :unlisted]

  @doc "Dozwolone rodzaje tożsamości."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  @doc "Dozwolone poziomy widoczności. `:unlisted` oznacza brak w katalogu, a nie prywatność."
  @spec visibilities() :: [atom()]
  def visibilities, do: @visibilities

  @doc "Zamienia nazwę rodzaju na atom (bez tworzenia nowych atomów)."
  @spec parse_kind(String.t()) :: {:ok, atom()} | :error
  def parse_kind(string) when is_binary(string) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == string)) do
      nil -> :error
      kind -> {:ok, kind}
    end
  end

  def parse_kind(_other), do: :error

  @doc "Zamienia widoczność na atom, bez tworzenia nowych atomów."
  @spec parse_visibility(term()) :: {:ok, :public | :unlisted} | :error
  def parse_visibility("public"), do: {:ok, :public}
  def parse_visibility("unlisted"), do: {:ok, :unlisted}
  def parse_visibility(_other), do: :error

  @doc "Wyrażenie regularne poprawnego uchwytu (handle)."
  @spec handle_format() :: Regex.t()
  def handle_format, do: ~r/\A[a-z0-9][a-z0-9_-]{1,31}\z/

  @spec valid_handle?(term()) :: boolean()
  def valid_handle?(handle) when is_binary(handle), do: Regex.match?(handle_format(), handle)
  def valid_handle?(_), do: false
end
