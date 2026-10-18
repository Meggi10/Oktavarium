defmodule Mix.Tasks.Oktavarium.Blob.Put do
  @moduledoc false
  use Mix.Task
  alias Oktavarium.{Blobs, Cli, Resources}

  # Local operator operation: uploads bytes only. Publishing still requires
  # resource.put with a valid signature and capability.
  @impl Mix.Task
  def run(args) do
    with {:ok, opts, []} <- Cli.parse_args(args, file: :string, type: :string),
         path when is_binary(path) <- opts[:file],
         {:ok, %{size: size}} <- File.stat(path),
         true <- size <= Resources.max_blob_size() do
      Mix.Oktavarium.start_repo!()

      with {:ok, bytes} <- File.read(path),
           {:ok, blob} <- Blobs.put(bytes, opts[:type]) do
        IO.puts(Jason.encode!(%{hash: blob.hash, size: blob.size, media_type: blob.media_type}))
      else
        {:error, reason} -> Mix.raise(Cli.format_error(reason))
      end
    else
      nil -> Mix.raise(Cli.format_error({:missing_option, :file}))
      false -> Mix.raise(Cli.format_error(:too_large))
      {:error, reason} -> Mix.raise(Cli.format_error(reason))
    end
  end
end
