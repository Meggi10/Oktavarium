import Config

# Na produkcji nowe tożsamości zakłada głównie operator (`mix oktavarium.ingest`).
config :oktavarium, registration: :closed

config :logger, level: :info
