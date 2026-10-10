defmodule Mix.Tasks.Oktavarium.Key.Show do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.Cli

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    with {:ok, _opts, [path]} <- Cli.parse_args(args, [], allow_args: true),
         {:ok, key} <- Cli.show_key(path) do
      Mix.shell().info("#{key.kind} #{key.id}")
    else
      {:ok, _opts, _rest} -> Mix.raise("podaj dokładnie jeden plik klucza")
      {:error, error} -> Mix.raise(Cli.format_error(error))
    end
  end
end
