defmodule Mix.Tasks.Oktavarium.Resource do
  @moduledoc false
  use Mix.Task
  alias Oktavarium.Cli

  @switches [
    key: :string,
    after: :string,
    out: :string,
    id: :string,
    path: :string,
    project: :string,
    root: :boolean,
    hash: :string,
    size: :integer,
    media_type: :string,
    title: :string,
    alt: :string,
    description: :string,
    collection: :string
  ]

  @impl Mix.Task
  def run([operation | args]) do
    Mix.Task.run("app.config")

    with {:ok, opts, []} <- Cli.parse_args(args, @switches),
         {:ok, %{envelope: envelope}} <- Cli.resource_event(opts[:key], operation, opts),
         :ok <- Cli.output_envelope(envelope, opts[:out]) do
      :ok
    else
      {:error, reason} -> Mix.raise(Cli.format_error(reason))
    end
  end

  def run([]), do: Mix.raise("Podaj operacje: put, delete.")
end
