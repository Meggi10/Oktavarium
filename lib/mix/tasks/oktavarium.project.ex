defmodule Mix.Tasks.Oktavarium.Project do
  @moduledoc false
  use Mix.Task
  alias Oktavarium.Cli

  @switches [
    key: :string,
    after: :string,
    out: :string,
    slug: :string,
    id: :string,
    title: :string,
    description: :string
  ]

  @impl Mix.Task
  def run([operation | args]) do
    Mix.Task.run("app.config")

    with {:ok, opts, []} <- Cli.parse_args(args, @switches),
         {:ok, %{envelope: envelope}} <- Cli.project_event(opts[:key], operation, opts),
         :ok <- Cli.output_envelope(envelope, opts[:out]) do
      :ok
    else
      {:error, reason} -> Mix.raise(Cli.format_error(reason))
    end
  end

  def run([]), do: Mix.raise("Podaj operacje: create, update, delete.")
end
