defmodule OktavariumWeb.ErrorHTML do
  @moduledoc false
  use OktavariumWeb, :html

  alias OktavariumWeb.Layouts

  def render("404.html", assigns),
    do:
      page(assigns, "Nie ma takiej strony", "Adres jest niepoprawny albo tożsamość nie istnieje.")

  def render("500.html", assigns),
    do:
      page(
        assigns,
        "Coś poszło nie tak po stronie serwera",
        "Spróbuj za chwilę. Jeśli błąd wraca, zgłoś go operatorowi instancji."
      )

  def render(template, assigns),
    do:
      page(
        assigns,
        Phoenix.Controller.status_message_from_template(template),
        "Tego żądania nie da się obsłużyć."
      )

  defp page(assigns, title, text) do
    assigns = Map.merge(assigns, %{title: title, text: text})

    ~H"""
    <Layouts.document page_title={@title}>
      <Layouts.shell>
        <section class="notice">
          <h1>{@title}</h1>
          <p>{@text}</p>
          <p><a href={~p"/"}>Wróć do listy tożsamości</a></p>
        </section>
      </Layouts.shell>
    </Layouts.document>
    """
  end
end
