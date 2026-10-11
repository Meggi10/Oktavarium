import Config

config :oktavarium, Oktavarium.Repo,
  database: Path.expand("../priv/oktavarium_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :oktavarium, OktavariumWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base:
    "dev-only-secret-key-base-dev-only-secret-key-base-dev-only-secret-key-base-0000",
  debug_errors: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :oktavarium, blob_dir: Path.expand("../priv/blobs_dev", __DIR__), sites_domain: "localhost"
