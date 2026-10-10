import Config

config :oktavarium, Oktavarium.Repo,
  database: Path.expand("../priv/oktavarium.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :oktavarium, OktavariumWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-test-only-secret-key-base-test-only-secret-key-base-000",
  server: false

config :logger, level: :warning
