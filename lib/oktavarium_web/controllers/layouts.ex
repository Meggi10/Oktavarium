defmodule OktavariumWeb.Layouts do
  @moduledoc false
  use OktavariumWeb, :html

  attr :page_title, :string, default: nil
  slot :inner_block, required: true

  @doc "Cały dokument HTML; używają go układ główny i strony błędów."
  def document(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="pl">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
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

  slot :inner_block, required: true

  @doc "Nagłówek, treść i stopka wspólne dla wszystkich stron."
  def shell(assigns) do
    ~H"""
    <header class="top">
      <a class="wordmark" href={~p"/"}>
        <svg
          class="mark"
          viewBox="0 0 24 24"
          width="22"
          height="22"
          aria-hidden="true"
          focusable="false"
        >
          <line x1="12" y1="2" x2="12" y2="22" stroke="currentColor" stroke-width="2.5" />
          <circle cx="12" cy="9" r="4.5" fill="currentColor" />
          <circle cx="12" cy="9" r="1.6" fill="var(--paper)" />
        </svg>
        Oktavarium
      </a>
      <nav aria-label="Główna">
        <a href={~p"/"}>Tożsamości</a>
      </nav>
    </header>
    <main id="main">{render_slot(@inner_block)}</main>
    <footer class="foot">
      <p>
        Oktavarium jest prototypem. Każda zmiana, którą widać na tych stronach,
        pochodzi z podpisanego zdarzenia w dzienniku tożsamości.
      </p>
    </footer>
    """
  end

  @doc "Układ główny: Phoenix wstawia tu wyrenderowaną stronę."
  def app(assigns) do
    ~H"""
    <.shell>{@inner_content}</.shell>
    """
  end

  @doc "Układ główny (korzeń) dla stron renderowanych przez kontrolery."
  def root(assigns) do
    ~H"""
    <.document page_title={assigns[:page_title]}>{@inner_content}</.document>
    """
  end
end
