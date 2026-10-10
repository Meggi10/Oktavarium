defmodule Oktavarium.DataCase do
  @moduledoc """
  Szablon testów korzystających z bazy. SQLite z piaskownicą Ecto działa
  poprawnie tylko w trybie synchronicznym, więc testy z tego szablonu
  nie powinny używać `async: true`.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Oktavarium.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
    end
  end

  setup tags do
		pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Oktavarium.repo, shared: not tags[:async])
		on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
