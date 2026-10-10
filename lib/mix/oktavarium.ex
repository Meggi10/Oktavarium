defmodule Mix.Oktavarium do
  @moduledoc false
  # Wspólny start zadań operatora, które pracują na bazie bez serwera HTTP.

  @doc "Uruchamia samo repozytorium (bez Endpointu), więc działa też przy działającym serwerze."
  def start_repo! do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

    case Oktavarium.Repo.start_link(pool_size: 2) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
