defmodule Mix.Tasks.Oktavarium.Submit do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.Cli

  @switches [url: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    with {:ok, opts, files} <- Cli.parse_args(args, @switches, allow_args: true),
         url = opts[:url] || System.get_env("ATELIER_URL") || "http://localhost:4000",
         {:ok, results} <- Cli.submit(files, url, []) do
      for %{path: path, seq: seq, identity: identity} <- results do
        Mix.shell().info("#{path}: przyjęto jako zdarzenie ##{seq} tożsamości #{identity}")
      end
    else
      {:error, error} -> Mix.raise(Cli.format_error(error))
    end
  end
end
