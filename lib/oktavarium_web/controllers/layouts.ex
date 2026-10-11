defmodule OktavariumWeb.Layouts do
  @moduledoc false
  use OktavariumWeb, :html

  attr :page_title, :string, default: nil
  slot :inner_block, required: true

  @doc "Dokument wspólny dla stron publicznych, Pracowni i błędów."
  def document(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="pl">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="dark" />
        <title>{if @page_title, do: @page_title <> " | Oktavarium", else: "Oktavarium"}</title>
        <link rel="icon" href={~p"/favicon.svg"} type="image/svg+xml" />
        <link rel="stylesheet" href={~p"/assets/app.css"} />
      </head>
      <body>
        <a class="skip" href="#main">Przejdź do treści</a>
        {render_slot(@inner_block)}
      </body>
    </html>
    """
  end

  attr :active, :string, default: nil
  slot :inner_block, required: true

  @doc "Nawigacja nie wymaga sesji. Pracownia sama obsługuje logowanie."
  def shell(assigns) do
    ~H"""
    <header class="top">
      <a class="wordmark" href={~p"/"} aria-label="Oktavarium — strona główna">
        <svg
          class="mark"
          viewBox="0 0 24 24"
          width="24"
          height="24"
          aria-hidden="true"
          focusable="false"
        >
          <line x1="12" y1="2" x2="12" y2="22" stroke="currentColor" stroke-width="2.5" />
          <circle cx="12" cy="9" r="4.5" fill="currentColor" />
          <circle cx="12" cy="9" r="1.6" fill="var(--paper)" />
        </svg>
        Oktavarium
      </a>
      <nav class="main-nav" aria-label="Główna">
        <a href={~p"/"} aria-current={if @active == "/", do: "page"}>Odkrywaj</a>
        <a href={~p"/studio"} aria-current={if @active == "/studio", do: "page"}>Pracownia</a>
      </nav>
      <div class="nav-actions">
        <a class="nav-login" href={~p"/login"} aria-current={if @active == "/login", do: "page"}>
          Zaloguj się
        </a>
        <a class="btn primary" href={~p"/join"} aria-current={if @active == "/join", do: "page"}>
          Dołącz
        </a>
      </div>
    </header>
    <main id="main" tabindex="-1">{render_slot(@inner_block)}</main>
    <footer class="foot">
      <p><strong>Oktavarium</strong> · Małe społeczności, wspólne rzeczy.</p>
      <span>Prototyp akademicki</span>
    </footer>
    """
  end

  def app(assigns) do
    assigns = Map.put(assigns, :active, if(assigns[:conn], do: assigns.conn.request_path))

    ~H"""
    <.shell active={@active}>{@inner_content}</.shell>
    """
  end

  def root(assigns) do
    ~H"""
    <.document page_title={assigns[:page_title]}>{@inner_content}</.document>
    """
  end
end
