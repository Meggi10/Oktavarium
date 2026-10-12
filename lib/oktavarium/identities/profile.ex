defmodule Oktavarium.Identities.Profile do
  @moduledoc false
  @action "profile.update"

  # pole => {maksymalna długość, wiele linii?}
  @fields %{
    "display_name" => {80, false},
    "bio" => {2000, true},
    "website" => {200, false},
    "location" => {80, false}
  }
  @type changes :: %{optional(String.t()) => String.t() | nil}

  @doc "Nazwa akcji, o którą pyta `Oktavarium.Authz`."
  @spec action() :: String.t()
  def action, do: @action

  @doc "Dozwolone pola profilu, posortowane."
  @spec fields() :: [String.t()]
  def fields, do: @fields |> Map.keys() |> Enum.sort()

  @doc "Zasób, na którym `profile.update` zmienia `field` w tożsamości `identity_id`."
  @spec resource(String.t(), String.t()) :: String.t()
  def resource(identity_id, field), do: identity_id <> "/profile/" <> field

  @doc """
  Sprawdza zmiany profilu z ładunku zdarzenia.

  Zwraca `{:ok, zmiany}` albo `{:error, {:invalid_body, "fields"}}` (zły kształt:
  nie mapa, pusta mapa) lub `{:error, {:invalid_body, "fields.<pole>"}}` 
  (nieznane pole albo zła wartość).
  """
  @spec parse_changes(term()) :: {:ok, changes()} | {:error, {:invalid_body, String.t()}}
  def parse_changes(changes) when is_map(changes) and map_size(changes) > 0 do
    changes
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}}, fn {field, value}, {:ok, acc} ->
      case check_value(field, value) do
        :ok -> {:cont, {:ok, Map.put(acc, field, value)}}
        :error -> {:halt, {:error, {:invalid_body, "fields." <> printable_name(field)}}}
      end
    end)
  end

  def parse_changes(_other), do: {:error, {:invalid_body, "fields"}}

  # Replay po skasowaniu historycznych bajtów nadal musi sprawdzić nazwę pola
  # i uprawnienie, choć nie da się już zweryfikować wartości. Brak treści
  # reprezentuje nil, zaś ref przechowuje oddzielna projekcja profile_refs.
  def parse_changes_for_replay(changes, true) when is_map(changes) and map_size(changes) > 0 do
    if Enum.all?(changes, fn {field, value} ->
         field in fields() and (is_nil(value) or check_value(field, value) == :ok)
       end),
       do: {:ok, changes},
       else: {:error, {:invalid_body, "fields"}}
  end

  def parse_changes_for_replay(changes, _), do: parse_changes(changes)

  @doc "Profil po zastosowaniu zmian: `nil` usuwa pole, pozostałe pola zostają."
  @spec apply_changes(map() | nil, changes()) :: map()
  def apply_changes(profile, changes) do
    Enum.reduce(changes, profile || %{}, fn
      {field, nil}, acc -> Map.delete(acc, field)
      {field, value}, acc -> Map.put(acc, field, value)
    end)
  end

  defp check_value(field, nil) when is_binary(field),
    do: if(Map.has_key?(@fields, field), do: :ok, else: :error)

  defp check_value(field, value) when is_binary(field) and is_binary(value) do
    case Map.fetch(@fields, field) do
      {:ok, {max, multiline?}} -> check_text(field, value, max, multiline?)
      :error -> :error
    end
  end

  defp check_value(_field, _value), do: :error

  # znaki sterujące (C0, DEL, C1) są zabronione; w polu wielolinijkowym wolno tylko
  # nową linię i tabulator (CR odrzucamy, żeby nie było dwóch zapisów końca linii)
  defp control_chars(false), do: ~r/[\x00-\x1F\x7F\x{80}-\x{9F}]/u
  defp control_chars(true), do: ~r/[\x00-\x08\x0B-\x1F\x7F\x{80}-\x{9F}]/u

  defp check_text(field, value, max, multiline?) do
    control = control_chars(multiline?)

    cond do
      not String.valid?(value) -> :error
      value == "" -> :error
      String.length(value) > max -> :error
      Regex.match?(control, value) -> :error
      field == "website" and not web_url?(value) -> :error
      true -> :ok
    end
  end

  defp web_url?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        not String.contains?(value, [" ", "\t"])

      _other ->
        false
    end
  end

  # nazwa pola trafia do komunikatu błędu, więc nie wypisujemy surowych bajtów
  defp printable_name(field) when is_binary(field) do
    if String.printable?(field), do: String.slice(field, 0, 40), else: "?"
  end

  defp printable_name(_field), do: "?"
end
