defmodule Mix.Tasks.Oktavarium.Invite do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.{Cli, Invites}

  @switches [note: :string, uses: :integer, days: :integer, list: :boolean]

  @impl Mix.Task
  def run(args) do
    Mix.Oktavarium.start_repo!()

    case Cli.parse_args(args, @switches) do
      {:ok, opts, _} -> run_opts(opts)
      {:error, error} -> Mix.raise("błędne argumenty: #{inspect(error)}")
    end
  end

  defp run_opts(opts) do
    if opts[:list] do
      for i <- Invites.list() do
        Mix.shell().info(
          "#{i.uses}/#{i.max_uses} użyć, do #{i.expires_at || "bez końca"}  #{i.note}"
        )
      end
    else
      uses = Keyword.get(opts, :uses, 1)
      if uses < 1, do: Mix.raise("--uses musi być dodatnie")

      {:ok, token} = Invites.create(note: opts[:note], max_uses: uses, days: opts[:days])

      Mix.shell().info(
        "Zaproszenie (zapisz je teraz, nie da się go odczytać później):\n\n  #{token}\n"
      )
    end
  end
end
