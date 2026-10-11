defmodule OktavariumWeb.Router do
  use OktavariumWeb, :router

  import OktavariumWeb.Auth, only: [load_session: 2, require_session: 2, verify_csrf: 2]

  # Strony nie mają sesji ani formularzy (nic nie jest tu zapisywane z przeglądarki),
  # więc CSP może zabronić wszystkiego poza własnymi plikami.
  @csp "default-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; " <>
         "frame-ancestors 'none'; base-uri 'none'; form-action 'none'"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_root_layout, html: {OktavariumWeb.Layouts, :root}
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_session
  end

  pipeline :csrf do
    plug :require_session
    plug :verify_csrf
  end

  scope "/", OktavariumWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/i/:ref", IdentityController, :show
    # powłoki aplikacji `priv/static/assets/js`
    get "/join", AppController, :join
    get "/login", AppController, :login
    get "/studio", AppController, :studio
  end

  scope "/", OktavariumWeb do
    get "/blobs/:hash", BlobController, :show
  end

  scope "/api", OktavariumWeb do
    pipe_through :api

    post "/events", EventController, :create
    post "/session/challenge", SessionController, :challenge
    post "/session", SessionController, :create
    get "/me", SessionController, :me
    get "/identities/:ref", IdentityApiController, :show
    get "/identities/:id/head", EventController, :head
    get "/identities/:id/events", EventController, :index
  end

  scope "/api", OktavariumWeb do
    pipe_through [:api, :csrf]

    delete "/session", SessionController, :delete
    post "/blobs", BlobController, :create
  end
end
