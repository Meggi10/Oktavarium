defmodule Oktavarium.Projects do
  @moduledoc """
  Prosty projekt jako kontener zasobów jednej tożsamości. Nie jest osobną
  tożsamością ani repozytorium Git. Jego id to id podpisanego `project.create`.
  """

  alias Oktavarium.Resources

  @slug ~r/\A[a-z0-9][a-z0-9-]{0,59}\z/

  @doc "Ścieżka projektu w katalogu; uprawnienia używają stabilnego ID."
  def path(slug), do: "projects/" <> slug

  @doc "Stable authorization namespace, independent of the display slug."
  def resource(identity_id, project_id), do: identity_id <> "/projects/" <> project_id

  @doc "The collection on which project.create is authorized."
  def collection(identity_id), do: identity_id <> "/projects"

  @doc "A grant suffix inside a project (wildcard or relative resource path)."
  def grant_resource(identity_id, project_id, suffix \\ "*") do
    if Resources.valid_id?(project_id) and is_binary(suffix) do
      full = resource(identity_id, project_id) <> "/" <> String.trim_leading(suffix, "/")

      if Oktavarium.Capability.valid_resource?(full),
        do: {:ok, full},
        else: {:error, {:invalid_resource, full}}
    else
      {:error, {:invalid_body, "project_id"}}
    end
  end

  @doc "Walidacja `project.create`: slug oraz meta z wymaganym title."
  def parse_create(body) when is_map(body) do
    with :ok <- fields(body, ~w(slug meta)),
         {:ok, slug} <- slug(body["slug"]),
         {:ok, meta} <- meta(body["meta"]) do
      {:ok, %{path: path(slug), meta: meta}}
    end
  end

  def parse_create(_), do: {:error, {:invalid_body, "body"}}

  @doc "Aktualizacja projektu po id; można zmienić jego slug i/lub metadane."
  def parse_update(body) when is_map(body) do
    with :ok <- fields(body, ~w(id slug meta)),
         :ok <- check(Resources.valid_id?(body["id"]), "id"),
         :ok <- check(Map.has_key?(body, "slug") or Map.has_key?(body, "meta"), "body"),
         {:ok, new_path} <- maybe_path(body),
         {:ok, new_meta} <- maybe_meta(body) do
      {:ok, %{id: body["id"], path: new_path, meta: new_meta}}
    end
  end

  def parse_update(_), do: {:error, {:invalid_body, "body"}}

  @doc "Usunięcie projektu po id, tylko gdy nie ma już przypisanych zasobów."
  def parse_delete(%{"id" => id} = body) do
    with :ok <- fields(body, ~w(id)),
         :ok <- check(Resources.valid_id?(id), "id") do
      {:ok, id}
    end
  end

  def parse_delete(_), do: {:error, {:invalid_body, "id"}}

  defp maybe_path(%{"slug" => slug}) do
    with {:ok, slug} <- slug(slug), do: {:ok, path(slug)}
  end

  defp maybe_path(_), do: {:ok, :unchanged}

  defp maybe_meta(%{"meta" => meta}), do: meta(meta)
  defp maybe_meta(_), do: {:ok, :unchanged}

  defp slug(value) when is_binary(value) do
    if Regex.match?(@slug, value), do: {:ok, value}, else: {:error, {:invalid_body, "slug"}}
  end

  defp slug(_), do: {:error, {:invalid_body, "slug"}}

  defp meta(map) when is_map(map) and not is_struct(map) do
    with :ok <- fields(map, ~w(title description), "meta."),
         :ok <- check(Map.has_key?(map, "title"), "meta.title"),
         {:ok, normalized} <- Resources.parse_meta(map) do
      {:ok, normalized}
    end
  end

  defp meta(_), do: {:error, {:invalid_body, "meta"}}

  defp fields(map, allowed, prefix \\ "") do
    case Enum.find(Map.keys(map), &(&1 not in allowed)) do
      nil -> :ok
      key when is_binary(key) -> {:error, {:invalid_body, prefix <> key}}
      _ -> {:error, {:invalid_body, prefix <> "?"}}
    end
  end

  defp check(true, _field), do: :ok
  defp check(false, field), do: {:error, {:invalid_body, field}}
end
