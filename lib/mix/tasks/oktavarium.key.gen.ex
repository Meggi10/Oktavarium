defmodule Mix.Tasks.Oktavarium.Key.Gen do
  @moduledoc false
  use Mix.Task

  alias Oktavarium.Cli

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    with {:ok, opts, _} <- Cli.parse_args(args, kind: :string, out: :string),
         {:ok, key} <- Cli.gen_key(opts[:kind] || "signing", opts[:out]) do
      Mix.shell().info("Wygenerowano klucz #{key.kind}: #{key.id}")

      Mix.shell().info(
        "Zapisano w #{key.path} (uprawnienia 0600). Plik zawiera klucz prywatny — " <>
          "nie dodawaj go do repozytorium."
      )
    else
      {:error, error} -> Mix.raise(Cli.format_error(error))
    end
  end
end
