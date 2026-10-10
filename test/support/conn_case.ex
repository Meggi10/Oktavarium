defmodule OktavariumWeb.ConnCase do
  @moduledoc """
  Szablon testów warstwy webowej. Jak `Oktavarium.DataCase`, 
  działa synchronicznie (SQLite z piaskownicą Ecto).
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint OktavariumWeb.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import OktavariumWeb.ConnCase

      alias Oktavarium.Repo
      use OktavariumWeb, :verified_routes
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Oktavarium.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
