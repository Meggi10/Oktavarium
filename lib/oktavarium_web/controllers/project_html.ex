defmodule OktavariumWeb.ProjectHTML do
  @moduledoc false
  use OktavariumWeb, :html
  import OktavariumWeb.PublicComponents

  def show(assigns) do
    assigns = Map.put(assigns, :ref, assigns.identity.handle || assigns.identity.id)

    ~H"""
    <article class="public-project" id="public-project">
      <nav class="crumbs" aria-label="Ścieżka nawigacji">
        <a href={~p"/"}>Odkrywaj</a><span aria-hidden="true">/</span>
        <a href={~p"/i/#{@ref}"}>{@identity.profile["display_name"] || @ref}</a>
        <span aria-hidden="true">/</span><span aria-current="page">Projekt</span>
      </nav>
      <header class="project-heading">
        <div>
          <p class="eyebrow">Projekt · {kind_name(@identity.kind)}</p>
          <h1>{@project.meta["title"] || String.replace_prefix(@project.path, "projects/", "")}</h1>
          <p class="lead">{@project.meta["description"] || "Ten projekt nie ma jeszcze opisu."}</p>
          <p :if={@identity.visibility == :unlisted} class="tag">
            Nieindeksowana tożsamość · odczyt dostępny przez adres
          </p>
        </div>
        <aside class="panel">
          <h2>Wspólna przestrzeń</h2>
          <p>Materiały można przeglądać bez logowania. Projekt porządkuje zasoby właściciela.</p>
          <a
            class="btn"
            href={~p"/studio?#{[ref: @identity.id, project: @project.id, view: "resources"]}"}
          >Otwórz w Pracowni</a>
          <a
            :if={@site_url}
            class="btn primary"
            href={@site_url}
            target="_blank"
            rel="noopener noreferrer"
          >Własna strona ↗</a>
          <p :if={@site_url} class="hint">Osobny adres, własny HTML/CSS/JS. Nowa karta.</p>
        </aside>
      </header>
      <p :if={@integrity != :ok} class="notice bad" role="alert">
        Nie udało się zweryfikować dziennika właściciela. Dane mogą być niespójne.
      </p>
      <section aria-labelledby="project-files-h">
        <div class="section-heading">
          <h2 id="project-files-h">Zasoby projektu</h2><span>{plural(
            length(@resources),
            "plik",
            "pliki",
            "plików"
          )}</span>
        </div>
        <div :if={@resources == []} class="feed-empty">
          <h3>Projekt jest jeszcze pusty</h3><p>Autor może dodać materiały w Pracowni.</p>
        </div>
        <div class="project-files">
          <.file_card :for={r <- @resources} resource={r} identity={@identity} />
        </div>
      </section>
      <details class="technical">
        <summary>Identyfikator i dane projektu</summary>
        <div class="panel">
          <p>Stałe ID: <.key_id id={@project.id} /></p><a href={
            ~p"/api/identities/#{@identity.id}/projects/#{@project.id}"
          }>Projekt i zasoby (JSON)</a>
        </div>
      </details>
    </article>
    """
  end
end
