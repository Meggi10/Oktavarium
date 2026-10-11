defmodule OktavariumWeb.AppHTML do
  @moduledoc false
  use OktavariumWeb, :html

  attr :page, :string, required: true
  attr :heading, :string, required: true
  attr :registration, :atom, required: true

  def app(assigns) do
    ~H"""
    <section class="app" id="app" data-page={@page} data-registration={@registration}>
      <h1>{@heading}</h1>
      <noscript>
        <p class="bad">
          Ta strona wymaga JavaScriptu: podpisywanie zdarzeń odbywa się w przeglądarce.
        </p>
      </noscript>
      <p class="muted" id="app-loading">Ładowanie…</p>
    </section>
    <script type="module" src={"/assets/js/pages/" <> @page <> ".js"}>
    </script>
    """
  end
end
