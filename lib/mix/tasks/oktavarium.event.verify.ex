defmodule Mix.Tasks.Oktavarium.Event.Verify do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.Cli

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    with {:ok, _opts, paths} <- Cli.parse_args(args, [], allow_args: true),
         {:ok, events} <- Cli.verify_files(paths) do
      paths
      |> Enum.zip(events)
      |> Enum.each(fn {path, event} ->
        Mix.shell().info("OK #{path}: #{event.type} seq=#{event.seq} id=#{event.id}")
      end)

      Mix.shell().info("Tożsamość #{hd(events).identity}")

      case events do
        [_single] ->
          Mix.shell().info("Podpis poprawny.")

        _many ->
          Mix.shell().info("Podpisy poprawne, łańcuch spójny (zdarzeń: #{length(events)}).")
      end
    else
      {:error, error} -> Mix.raise(Cli.format_error(error))
    end
  end
end
