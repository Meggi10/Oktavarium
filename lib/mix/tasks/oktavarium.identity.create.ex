defmodule Mix.Tasks.Oktavarium.Identity.Create do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.Cli

  @switches [
    key: :string,
    kind: :string,
    visibility: :string,
    handle: :string,
    auth_key: [:string, :keep],
    out: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    with {:ok, opts, _} <- Cli.parse_args(args, @switches),
         {:ok, %{envelope: envelope, event: event}} <-
           Cli.create_identity(opts[:key], [
             {:kind, opts[:kind]},
             {:visibility, opts[:visibility]},
             {:handle, opts[:handle]},
             {:auth_keys, Keyword.get_values(opts, :auth_key)}
           ]),
         :ok <- Cli.output_envelope(envelope, opts[:out]) do
      say(opts[:out], "Tożsamość #{event.identity}")
      say(opts[:out], "Klucz założycielski #{event.signer}")

      if opts[:out], do: say(opts[:out], "Koperta zapisana w #{opts[:out]}")

      if Keyword.get_values(opts, :auth_key) == [] do
        say(
          opts[:out],
          "Uwaga: nie podano --auth-key; serwer będzie wymagał co najmniej jednego klucza autoryzacji."
        )
      end
    else
      {:error, error} -> Mix.raise(Cli.format_error(error))
    end
  end

  defp say(nil, message), do: IO.puts(:stderr, message)
  defp say(_out, message), do: Mix.shell().info(message)
end
