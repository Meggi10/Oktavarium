defmodule Mix.Tasks.Oktavarium.Grant do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.Cli

  @switches [
    key: :string,
    after: :string,
    to: :string,
    action: :string,
    resource: :string,
    not_before: :string,
    expires: :string,
    parent_grant: :string,
    delegable: :boolean,
    out: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    with {:ok, opts, _} <- Cli.parse_args(args, @switches),
         {:ok, %{envelope: envelope, event: event}} <-
           Cli.create_grant(opts[:key],
             after: opts[:after],
             to: opts[:to],
             action: opts[:action],
             resource: opts[:resource],
             not_before: opts[:not_before],
             expires_at: opts[:expires],
             parent_grant: opts[:parent_grant],
             delegable: opts[:delegable]
           ),
         :ok <- Cli.output_envelope(envelope, opts[:out]) do
      say(opts[:out], "Grant #{event.id}")

      say(
        opts[:out],
        "#{event.body["action"]} na #{event.body["resource"]} dla #{event.body["subject"]}"
      )

      if opts[:out], do: say(opts[:out], "Koperta zapisana w #{opts[:out]}")
    else
      {:error, error} -> Mix.raise(Cli.format_error(error))
    end
  end

  defp say(nil, message), do: IO.puts(:stderr, message)
  defp say(_out, message), do: Mix.shell().info(message)
end
