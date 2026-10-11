import Config

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise "zmienna środowiskowa DATABASE_PATH nie jest ustawiona (np. '/var/lib/oktavarium/oktavarium.db')"

  config :oktavarium, Oktavarium.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "zmienna środowiskowa SECRET_KEY_BASE nie jest ustawiona (wygeneruj: mix phx.gen.secret)"

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :oktavarium, OktavariumWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  config :oktavarium,
    blob_dir:
      System.get_env("OKTAVARIUM_BLOB_DIR") || Path.join(Path.dirname(database_path), "blobs"),
    sites_domain: System.get_env("OKTAVARIUM_SITES_DOMAIN"),
    secure_cookies: true

  if registration = System.get_env("OKTAVARIUM_REGISTRATION") do
    config :oktavarium, registration: String.to_existing_atom(registration)
  end
end
