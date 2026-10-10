defmodule Mix.Tasks.Oktavarium.Ingest do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.{Cli, Log}

  @impl Mix.Task
  def run(args) do
    Mix.Oktavarium.start_repo!()

    with {:ok, _opts, files} <- Cli.parse_args(args, [], allow_args: true),
         :ok <- ensure_files(files),
         :ok <- ingest(files) do
      :ok
    else
      {:error, error} -> Mix.raise(Cli.format_error(error))
    end
  end

  defp ensure_files([]), do: {:error, :no_files}
  defp ensure_files(_files), do: :ok

  defp ingest(files) do
    Enum.reduce_while(files, :ok, fn path, :ok ->
      with {:ok, envelope} <- Cli.read_envelope(path),
           {:ok, event} <- Log.append(envelope) do
        Mix.shell().info(
          "#{path}: przyjęto jako zdarzenie ##{event.seq} tożsamości #{event.identity || event.id}"
        )

        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, {:ingest_failed, path, reason}}}
      end
    end)
  end
end
