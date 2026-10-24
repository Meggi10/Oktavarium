defmodule Oktavarium.MixProject do
  use Mix.Project

  def project do
    [
      app: :oktavarium,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Oktavarium.Application, []},
      extra_applications: [:logger, :crypto, :inets, :ssl, :public_key]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.13.1"},
      {:phoenix, "~> 1.8.15"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:phoenix_html, "~> 4.1"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "cmd npm run typecheck",
        "cmd npm run lint",
        "cmd npm run build",
        "cmd node --test test/js/*_test.mjs",
        "test"
      ]
    ]
  end
end
