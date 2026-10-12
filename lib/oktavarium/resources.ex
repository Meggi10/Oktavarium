defmodule Oktavarium.Resources do
  @moduledoc false
  @type kind :: :image | :audio | :site
  alias Oktavarium.Crypto

  @images ~w(image/png image/jpeg image/gif image/webp)
  @audio ~w(audio/mpeg audio/ogg audio/wav audio/flac audio/mp4)
  @site ~w(text/html text/css text/javascript text/plain application/json image/svg+xml
           image/png image/jpeg image/gif image/webp image/x-icon font/woff font/woff2
           audio/mpeg audio/ogg)

  @meta_limits %{"title" => 120, "alt" => 300, "description" => 1000, "collection" => 40}

  def put_action, do: "resource.put"
  def delete_action, do: "resource.delete"

  @doc "Zasób w sensie uprawnień. Projekty mają odizolowaną przestrzeń ścieżek."
  def resource(identity_id, path), do: resource(identity_id, path, nil)
  def resource(identity_id, path, nil), do: identity_id <> "/" <> path

  def resource(identity_id, path, project_id) when is_binary(project_id),
    do: identity_id <> "/projects/" <> project_id <> "/" <> path

  @doc "Dozwolone typy mediów dla rodzaju."
  @spec media_types(kind()) :: [String.t()]
  def media_types(:image), do: @images
  def media_types(:audio), do: @audio
  def media_types(:site), do: @site

  @doc "Limit rozmiaru bloba w bajtach dla rodzaju."
  @spec max_size(kind()) :: pos_integer()
  def max_size(:image), do: 10 * 1024 * 1024
  def max_size(:audio), do: 50 * 1024 * 1024
  def max_size(:site), do: 5 * 1024 * 1024

  @doc "Największy blob, jaki w ogóle przyjmie serwer."
  def max_blob_size, do: 50 * 1024 * 1024

  @doc "Wszystkie typy mediów, które serwer przyjmuje jako blob."
  def all_media_types, do: Enum.uniq(@images ++ @audio ++ @site)

  @doc """
  Rozbiera ścieżkę zasobu. `{:ok, kind, path}` albo `:error`.
  """
  @spec parse_path(term()) :: {:ok, kind(), String.t()} | :error
  def parse_path(path) when is_binary(path) and byte_size(path) <= 200 do
    case String.split(path, "/") do
      ["images", name] ->
        if media_name?(name), do: {:ok, :image, path}, else: :error

      ["audio", name] ->
        if media_name?(name), do: {:ok, :audio, path}, else: :error

      ["site" | [_ | _] = rest] when length(rest) <= 7 ->
        if Enum.all?(rest, &site_segment?/1), do: {:ok, :site, path}, else: :error

      _ ->
        :error
    end
  end

  def parse_path(_other), do: :error

  defp media_name?(name), do: Regex.match?(~r/\A[a-z0-9][a-z0-9._-]{0,79}\z/, name)
  defp site_segment?(seg), do: Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,79}\z/, seg)

  @doc "Czy tekst jest poprawnym hashem bloba (SHA-256, małe litery szesnastkowo)."
  def valid_hash?(hash) when is_binary(hash), do: Regex.match?(~r/\A[0-9a-f]{64}\z/, hash)
  def valid_hash?(_other), do: false

  @doc "Kanoniczny identyfikator zasobu: SHA-256 zakodowany jako base64url (43 znaki)."
  def valid_id?(id) when is_binary(id) do
    case Crypto.decode(id) do
      {:ok, <<_::binary-size(32)>> = bytes} -> Crypto.encode(bytes) == id
      _ -> false
    end
  end

  def valid_id?(_other), do: false

  @doc """
  Waliduje `resource.put`. `id` wskazuje istniejący zasób (także po zmianie ścieżki),
  `project_id` opcjonalnie przypisuje go do projektu. Brak `project_id` oznacza
  zachowanie obecnej przynależności podczas aktualizacji.
  Zwraca `{:ok, dane}` lub `{:error, {:invalid_body, pole}}`.
  """
  @spec parse_put(term()) :: {:ok, map()} | {:error, {:invalid_body, String.t()}}
  def parse_put(body) when is_map(body) do
    with {:ok, kind, path} <- field(parse_path(Map.get(body, "path")), "path"),
         :ok <- optional_id(body, "id"),
         :ok <- optional_project_id(body),
         :ok <- ensure(valid_hash?(Map.get(body, "hash")), "hash"),
         {:ok, size} <- parse_size(Map.get(body, "size"), kind),
         {:ok, media_type} <- parse_media_type(Map.get(body, "media_type"), kind),
         {:ok, meta} <- parse_meta(Map.get(body, "meta", %{})) do
      {:ok,
       %{
         id: body["id"],
         project_id:
           if(Map.has_key?(body, "project_id"), do: body["project_id"], else: :unchanged),
         path: path,
         kind: kind,
         hash: body["hash"],
         size: size,
         media_type: media_type,
         meta: meta
       }}
    end
  end

  def parse_put(_body), do: {:error, {:invalid_body, "body"}}

  @doc "Kasowanie po `id` albo po ścieżce wewnątrz root/projektu (`project_id`)."
  @spec parse_delete(term()) :: {:ok, map()} | {:error, {:invalid_body, String.t()}}
  def parse_delete(body) when is_map(body) do
    id = Map.get(body, "id")
    path = Map.get(body, "path")

    cond do
      optional_project_id(body) != :ok ->
        {:error, {:invalid_body, "project_id"}}

      Map.has_key?(body, "id") and not valid_id?(id) ->
        {:error, {:invalid_body, "id"}}

      Map.has_key?(body, "path") and not match?({:ok, _, _}, parse_path(path)) ->
        {:error, {:invalid_body, "path"}}

      is_nil(id) and is_nil(path) ->
        {:error, {:invalid_body, "id"}}

      true ->
        {:ok, %{id: id, path: path, project_id: Map.get(body, "project_id")}}
    end
  end

  def parse_delete(_body), do: {:error, {:invalid_body, "body"}}

  defp optional_id(body, field) do
    if not Map.has_key?(body, field) or valid_id?(Map.get(body, field)),
      do: :ok,
      else: {:error, {:invalid_body, field}}
  end

  defp optional_project_id(body) do
    value = Map.get(body, "project_id")

    if not Map.has_key?(body, "project_id") or is_nil(value) or valid_id?(value),
      do: :ok,
      else: {:error, {:invalid_body, "project_id"}}
  end

  defp field({:ok, kind, path}, _name), do: {:ok, kind, path}
  defp field(:error, name), do: {:error, {:invalid_body, name}}

  defp ensure(true, _name), do: :ok
  defp ensure(false, name), do: {:error, {:invalid_body, name}}

  defp parse_size(size, kind) when is_integer(size) and size > 0 do
    if size <= max_size(kind), do: {:ok, size}, else: {:error, {:invalid_body, "size"}}
  end

  defp parse_size(_size, _kind), do: {:error, {:invalid_body, "size"}}

  defp parse_media_type(type, kind) when is_binary(type) do
    if type in media_types(kind), do: {:ok, type}, else: {:error, {:invalid_body, "media_type"}}
  end

  defp parse_media_type(_type, _kind), do: {:error, {:invalid_body, "media_type"}}

  @doc false
  def parse_meta(meta) when is_map(meta) and not is_struct(meta) do
    Enum.reduce_while(Enum.sort(meta), {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      with {:ok, limit} <- Map.fetch(@meta_limits, key),
           true <- meta_text?(value, key, limit) do
        {:cont, {:ok, Map.put(acc, key, value)}}
      else
        _ -> {:halt, {:error, {:invalid_body, "meta." <> printable(key)}}}
      end
    end)
  end

  def parse_meta(_meta), do: {:error, {:invalid_body, "meta"}}

  defp meta_text?(value, key, limit) when is_binary(value) do
    value != "" and String.valid?(value) and String.length(value) <= limit and
      not Regex.match?(control_chars(key), value) and
      (key != "collection" or Regex.match?(~r/\A[a-z0-9][a-z0-9_-]*\z/, value))
  end

  defp meta_text?(_value, _key, _limit), do: false

  # nowe linie dozwolone tylko w opisie
  defp control_chars("description"), do: ~r/[\x00-\x09\x0B-\x1F\x7F\x{0085}]/u
  defp control_chars(_key), do: ~r/[\x00-\x1F\x7F\x{0085}]/u

  defp printable(key) when is_binary(key) do
    if String.valid?(key) and String.printable?(key) and byte_size(key) <= 40, do: key, else: "?"
  end

  defp printable(_key), do: "?"
end
