defmodule Oktavarium.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Oktavarium.Repo,
      OktavariumWeb.Endpoint
    ]
    Supervisor.start_link(children, strategy: :one_for_one, name: Oktavarium.Supervisor)
  end
end
