defmodule OktavariumWeb do
  @moduledoc """
  Warstwa webowa: strony (projekcja dzienników, tylko do odczytu) i API przyjmujące
  podpisane koperty. Strony pokazują stan i historię, a zapis idzie przez `POST /api/events`.

  `use OktavariumWeb, :controller`, `:html` i `:router` wciągają wspólne importy.
  """
  def static_paths, do: ~w(assets favicon.svg robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json], layouts: [html: OktavariumWeb.Layouts]
      import Plug.Conn
      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.Controller, only: [get_csrf_token: 0, view_module: 1, view_template: 1]
      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import OktavariumWeb.Components
      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: OktavariumWeb.Endpoint,
        router: OktavariumWeb.Router,
        statics: OktavariumWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which), do: apply(__MODULE__, which, [])
end
