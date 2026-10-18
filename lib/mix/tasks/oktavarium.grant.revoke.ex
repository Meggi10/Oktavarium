defmodule Mix.Tasks.Oktavarium.Grant.Revoke do
  @moduledoc false
  use Mix.Task
  alias Oktavarium.Cli

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    with {:ok, opts, []} <-
           Cli.parse_args(args, key: :string, after: :string, grant: :string, out: :string),
         {:ok, %{envelope: envelope}} <- Cli.revoke_grant(opts[:key], opts),
         :ok <- Cli.output_envelope(envelope, opts[:out]) do
      :ok
    else
      {:error, reason} -> Mix.raise(Cli.format_error(reason))
    end
  end
end
