defmodule OktavariumWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :oktavarium

  # strony tożsamości na subdomenach
  plug OktavariumWeb.SitePlug

  plug Plug.Static,
    at: "/",
    from: {:oktavarium, "priv/static"},
    gzip: false,
    only: OktavariumWeb.static_paths()

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Koperta zdarzenia to kilkaset bajtów; 64 KiB z zapasem, żeby nikt nie wysyłał
  # megabajtów do parsowania. Inne typy treści przechodzą bez parsowania.
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["*/*"],
    length: 65_536,
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug OktavariumWeb.Router
end
