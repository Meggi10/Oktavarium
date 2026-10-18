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
      <p class="muted" id="app-loading" role="status">
        Przygotowanie interfejsu... Jeśli nie otworzy się poprawnie, możesz odświeżyć stronę.
      </p>
    </section>
    <script defer src={~p"/assets/js/app-boot-guard.js"}>
    </script>
    <script type="module" src={"/assets/js/pages/" <> @page <> ".js"}>
    </script>
    """
  end
end
