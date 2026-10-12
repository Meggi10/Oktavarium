defmodule Oktavarium.Content do
  @moduledoc """
  Oddziela tekst użytkownika od podpisanego dziennika (koperty v2).

  Podpisany payload zawiera jedynie `%{"sha256" => hash}`. Opcjonalne
  `attachments` koperty przenoszą bajty przy zapisie i NIE są przechowywane
  w tabeli events. Replay może odtworzyć logikę operacji bez usuniętych bajtów.
  """

  alias Oktavarium.Blobs
  alias Oktavarium.Resources

  @max_text_bytes 10_000
  @max_attachments_bytes 65_536

  @doc "Zamienia tekst w wybranych polach na referencje, zwracając osobne bajty."
  def detach(type, body) when is_map(body) do
    key =
      case type do
        "profile.update" -> "fields"
        "project.create" -> "meta"
        "project.update" -> "meta"
        "resource.put" -> "meta"
        _ -> nil
      end

    case key do
      nil ->
        {body, %{}}

      _ ->
        case Map.fetch(body, key) do
          {:ok, fields} when is_map(fields) ->
            {refs, attachments} =
              Enum.reduce(fields, {%{}, %{}}, fn
                {field, text}, {refs, attachments} when is_binary(text) ->
                  hash = hash(text)
                  {Map.put(refs, field, %{"sha256" => hash}), Map.put(attachments, hash, text)}

                {field, value}, {refs, attachments} ->
                  {Map.put(refs, field, value), attachments}
              end)

            {Map.put(body, key, refs), attachments}

          _ ->
            {body, %{}}
        end
    end
  end

  def detach(_type, body), do: {body, %{}}

  @doc "Czy załączniki są małe, poprawnie zhashowane i wskazywane przez payload."
  def validate_attachments(attachments, body) when is_map(attachments) do
    refs = referenced_hashes(body)

    if map_size(attachments) <= 20 and
         Enum.reduce(attachments, 0, fn {_hash, text}, total ->
           total + if(is_binary(text), do: byte_size(text), else: @max_attachments_bytes + 1)
         end) <= @max_attachments_bytes and
         Enum.all?(attachments, fn {hash, text} ->
           is_binary(hash) and Resources.valid_hash?(hash) and is_binary(text) and
             String.valid?(text) and byte_size(text) <= @max_text_bytes and
             hash(text) == hash and MapSet.member?(refs, hash)
         end) do
      :ok
    else
      {:error, :invalid_attachments}
    end
  end

  def validate_attachments(_, _), do: {:error, :invalid_attachments}

  @doc """
  Odczytuje mapę referencji z podpisanej treści. Zwraca `{teksty, skróty}`.
  W replay brakująca treść daje `nil` (profil) lub jawny znacznik (meta), ale
  skrót pozostaje, więc brak bajtów nigdy nie staje się operacją usunięcia pola.
  """
  def materialize(fields, attachments, section, replay?) when is_map(fields) do
    Enum.reduce_while(fields, {:ok, {%{}, %{}}}, fn {field, ref}, {:ok, {values, hashes}} ->
      prefix = if(section == :profile, do: "fields.", else: "meta.")

      cond do
        not is_binary(field) ->
          {:halt, {:error, {:invalid_body, prefix <> "?"}}}

        is_nil(ref) and section == :profile ->
          {:cont, {:ok, {Map.put(values, field, nil), Map.put(hashes, field, nil)}}}

        is_map(ref) and map_size(ref) == 1 and Resources.valid_hash?(ref["sha256"]) ->
          hash = ref["sha256"]

          case text(hash, attachments) do
            {:ok, value} ->
              {:cont, {:ok, {Map.put(values, field, value), Map.put(hashes, field, hash)}}}

            :missing when replay? ->
              {:cont,
               {:ok,
                {Map.put(values, field, placeholder(section, field)),
                 Map.put(hashes, field, hash)}}}

            :missing ->
              {:halt, {:error, {:content_missing, hash}}}
          end

        true ->
          {:halt, {:error, {:invalid_body, prefix <> field}}}
      end
    end)
  end

  def materialize(_, _, section, _),
    do: {:error, {:invalid_body, if(section == :profile, do: "fields", else: "meta")}}

  defp text(hash, attachments) do
    case Map.fetch(attachments, hash) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> Blobs.read_text(hash)
    end
  end

  defp placeholder(:profile, _field), do: nil
  defp placeholder(:meta, "collection"), do: "unavailable"
  defp placeholder(:meta, _field), do: "Treść niedostępna"

  def hash(text) when is_binary(text),
    do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

  defp referenced_hashes(value) when is_map(value) do
    if map_size(value) == 1 and Resources.valid_hash?(value["sha256"]) do
      MapSet.new([value["sha256"]])
    else
      Enum.reduce(value, MapSet.new(), fn {_key, v}, acc ->
        MapSet.union(acc, referenced_hashes(v))
      end)
    end
  end

  defp referenced_hashes(values) when is_list(values),
    do:
      Enum.reduce(values, MapSet.new(), fn v, acc -> MapSet.union(acc, referenced_hashes(v)) end)

  defp referenced_hashes(_), do: MapSet.new()
end
