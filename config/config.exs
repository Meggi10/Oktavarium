import Config

config :oktavarium,
  ecto_repos: [Oktavarium.Repo]

config :oktavarium, Oktavarium.Repo,
  # Dopisywanie do logu czyta stan i potem zapisuje; `BEGIN IMMEDIATE` zajmuje
  # blokadę zapisu od początku, więc dwa równoległe zapisy się kolejkują zamiast
  # kończyć błędem "database is locked" przy awansie blokady.
  default_transaction_mode: :immediate

config :oktavarium, OktavariumWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  live_view: [signing_salt: "oktavarium-public-live-v1"],
  render_errors: [
    formats: [html: OktavariumWeb.ErrorHTML, json: OktavariumWeb.ErrorJSON],
    layout: false
  ]

config :phoenix, :json_library, Jason

# Czy przez HTTP (`POST /api/events`) można zakładać nowe tożsamości (zdarzenie genesis).
# `:closed` przyjmuje przez HTTP tylko kolejne zdarzenia istniejących tożsamości;
# nowe zakłada operator poleceniem `mix oktavarium.ingest`, dopóki nie ma zaproszeń.
config :oktavarium, registration: :open

# Katalog z bajtami blobów i domena, na której serwowane są strony tożsamości
# (`<uchwyt>.<sites_domain>`). `nil` wyłącza strony. Zob. `OktavariumWeb.SitePlug`.
config :oktavarium, sites_domain: nil, secure_cookies: false

import_config "#{config_env()}.exs"
