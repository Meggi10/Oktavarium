defmodule Mix.Tasks.Oktavarium.Profile do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.Cli

  @switches [
    key: :string,
    after: :string,
    set: [:string, :keep],
    unset: [:string, :keep],
    out: :string
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    with {:ok, opts, _} <- Cli.parse_args(args, @switches),
         {:ok, %{envelope: envelope, event: event}} <-
           Cli.update_profile(opts[:key],
             after: opts[:after],
             set: Keyword.get_values(opts, :set),
             unset: Keyword.get_values(opts, :unset)
           ),
         :ok <- Cli.output_envelope(envelope, opts[:out]) do
      say(opts[:out], "Zmiana profilu #{event.id}")

      say(
        opts[:out],
        "Pola: #{event.body["fields"] |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
      )

      if opts[:out], do: say(opts[:out], "Koperta zapisana w #{opts[:out]}")
    else
      {:error, error} -> Mix.raise(Cli.format_error(error))
    end
  end

  defp say(nil, message), do: IO.puts(:stderr, message)
  defp say(_out, message), do: Mix.shell().info(message)
end
