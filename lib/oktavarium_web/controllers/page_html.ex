defmodule OktavariumWeb.PageHTML do
  @moduledoc false
  use OktavariumWeb, :html

  import OktavariumWeb.PublicComponents

  attr :projects, :list, default: []
  attr :entries, :list, required: true
  attr :images, :list, default: []
  attr :tracks, :list, default: []
  attr :view, :string, default: "all"

  def home(assigns) do
    ~H"""
    <section class="discover-head" aria-labelledby="discover-h">
      <div>
        <p class="eyebrow">Twoja społeczność</p>
        <h1 id="discover-h">Odkrywaj</h1>
        <p class="lead">Obrazy, dźwięki i ludzie. Zobacz, co powstaje obok.</p>
      </div>
      <a class="btn" href={~p"/studio"}>Przejdź do Pracowni <span aria-hidden="true">↗</span></a>
    </section>

    <nav class="filter-nav" aria-label="Rodzaj treści">
      <a href={~p"/"} aria-current={if @view == "all", do: "page"}>Wszystko</a>
      <a href={~p"/?view=images"} aria-current={if @view == "images", do: "page"}>Obrazy</a>
      <a href={~p"/?view=audio"} aria-current={if @view == "audio", do: "page"}>Nagrania</a>
      <a href={~p"/?view=projects"} aria-current={if @view == "projects", do: "page"}>Projekty</a>
      <a href={~p"/?view=people"} aria-current={if @view == "people", do: "page"}>Osoby i kolektywy</a>
    </nav>

    <section :if={@entries == []} class="onboarding" aria-labelledby="empty-h">
      <span class="empty-mark" aria-hidden="true">O</span>
      <p class="eyebrow">Miejsce na początek</p>
      <h2 id="empty-h">Nie ma jeszcze żadnych tożsamości</h2>
      <p>Załóż profil w przeglądarce. Potem opublikuj pierwszą pracę w Pracowni.</p>
      <div class="actions">
        <a class="btn primary" href={~p"/join"}>Załóż profil</a>
        <a class="btn" href={~p"/login"}>Mam już klucze</a>
      </div>
      <details class="cli-help">
        <summary>Wolisz terminal?</summary>
        <p>Możesz też utworzyć tożsamość przez CLI. Klucze prywatne zostają u Ciebie.</p>
        <pre class="code"><code>mix oktavarium.key.gen --out keys/ja.key
    mix oktavarium.key.gen --kind auth --out keys/laptop.key
    mix oktavarium.identity.create --key keys/ja.key --kind person --handle ja \
      --auth-key ID_KLUCZA_AUTH --out events/ja-0.json
    mix oktavarium.submit events/ja-0.json</code></pre>
      </details>
    </section>

    <div class={["discover-layout", (@view == "people" || @entries == []) && "people-only"]}>
      <div :if={@entries != [] && @view != "people"} class="discover-feed">
        <section :if={@images != []} class="gallery-section" aria-labelledby="gallery-h">
          <div class="section-heading">
            <h2 id="gallery-h">Ostatnio opublikowane</h2>
            <span class="section-note">Obrazy · ostatnio aktualizowane najpierw</span>
          </div>
          <ul class="gallery">
            <li :for={img <- @images}>
              <figure>
                <a
                  :if={Oktavarium.Blobs.exists?(img.hash)}
                  class="media-link"
                  href={~p"/i/#{img.handle || img.identity_id}"}
                >
                  <img
                    src={~p"/blobs/#{img.hash}"}
                    alt={img.meta["alt"] || img.meta["title"] || img.path}
                    loading="lazy"
                    decoding="async"
                  />
                </a>
                <p :if={!Oktavarium.Blobs.exists?(img.hash)} class="notice warn">Treść niedostępna</p>
                <figcaption>
                  <a class="cap-title" href={~p"/i/#{img.handle || img.identity_id}"}>
                    {img.meta["title"] || img.path}
                  </a>
                  <a class="cap-by" href={~p"/i/#{img.handle || img.identity_id}"}>{owner_name(img)}</a>
                </figcaption>
              </figure>
            </li>
          </ul>
        </section>

        <section :if={@tracks != []} class="tracks-section" aria-labelledby="tracks-h">
          <div class="section-heading">
            <h2 id="tracks-h">Do posłuchania</h2>
            <span class="section-note">Nagrania społeczności</span>
          </div>
          <ul class="tracks">
            <li :for={t <- @tracks}>
              <div class="track-head">
                <span class="cap-title">{t.meta["title"] || t.path}</span>
                <a class="cap-by" href={~p"/i/#{t.handle || t.identity_id}"}>{owner_name(t)}</a>
              </div>
              <p :if={!Oktavarium.Blobs.exists?(t.hash)} class="notice warn">Treść niedostępna</p>
              <audio
                :if={Oktavarium.Blobs.exists?(t.hash)}
                controls
                preload="none"
                src={~p"/blobs/#{t.hash}"}
                aria-label={"Odtwórz: " <> (t.meta["title"] || t.path)}
              >
                <a href={~p"/blobs/#{t.hash}"}>Pobierz nagranie</a>
              </audio>
            </li>
          </ul>
        </section>

        <section :if={@projects != []} aria-labelledby="discover-projects-h" class="gallery-section">
          <div class="section-heading">
            <h2 id="discover-projects-h">Projekty</h2><a href={~p"/?view=projects"}>Wszystkie projekty</a>
          </div>
          <div class="project-grid">
            <.project_card
              :for={entry <- @projects}
              project={entry.project}
              identity={entry.identity}
            />
          </div>
        </section>
        <section
          :if={@images == [] && @tracks == [] && @projects == []}
          class="feed-empty"
          aria-labelledby="feed-empty-h"
        >
          <p class="eyebrow">Jeszcze przed premierą</p>
          <h2 id="feed-empty-h">{empty_title(@view)}</h2>
          <p>Opublikowane materiały pojawią się tutaj. Tymczasem poznaj osoby i kolektywy.</p>
          <div class="actions">
            <a class="btn primary" href={~p"/studio"}>Opublikuj w Pracowni</a>
            <a class="btn" href={~p"/?view=people"}>Poznaj społeczność</a>
          </div>
        </section>
      </div>

      <section class="community" aria-labelledby="community-h">
        <div class="section-heading">
          <h2 id="community-h">Kto tu pracuje</h2>
          <span class="count">{length(@entries)}</span>
        </div>
        <p class="section-note">Osoby i wspólne przestrzenie.</p>
        <p :if={@entries == []} class="muted community-empty">Twój profil może być pierwszy.</p>
        <ul :if={@entries != []} class="directory" aria-label="Lista tożsamości">
          <li :for={entry <- @entries}>
            <a class="identity-card" href={~p"/i/#{entry.identity.handle || entry.identity.id}"}>
              <img
                :if={entry.avatar_hash && Oktavarium.Blobs.exists?(entry.avatar_hash)}
                class="avatar avatar-photo"
                src={~p"/blobs/#{entry.avatar_hash}"}
                alt=""
                loading="lazy"
                decoding="async"
              />
              <span
                :if={!entry.avatar_hash || !Oktavarium.Blobs.exists?(entry.avatar_hash)}
                class="avatar"
                data-kind={entry.identity.kind}
                aria-hidden="true"
              >{initial(entry.identity)}</span>
              <span class="identity-card-copy">
                <span class="row-name">{display_name(entry.identity)}</span>
                <span :if={entry.identity.handle} class="row-handle">@{entry.identity.handle}</span>
                <span class="kind-label">{public_kind(entry.identity.kind)}</span>
                <span :if={bio(entry.identity)} class="row-bio">{bio(entry.identity)}</span>
              </span>
            </a>
          </li>
        </ul>
        <a :if={@view != "people" && @entries != []} class="community-more" href={~p"/?view=people"}>
          Przeglądaj profile <span aria-hidden="true">→</span>
        </a>
      </section>
    </div>
    """
  end

  # Etykiety UX, nie zmiana formatu zdarzeń. Pozostałe rodzaje zachowują stare nazwy.
  defp public_kind(:user), do: "osoba"
  defp public_kind(:org), do: "kolektyw"
  defp public_kind(kind), do: kind_name(kind)

  defp empty_title("projects"), do: "Nie ma jeszcze projektów"
  defp empty_title("images"), do: "Nie ma jeszcze obrazów"
  defp empty_title("audio"), do: "Nie ma jeszcze nagrań"
  defp empty_title(_view), do: "Tu pojawią się publikacje"

  defp owner_name(%{profile: %{"display_name" => name}}) when is_binary(name), do: name
  defp owner_name(%{handle: handle}) when is_binary(handle), do: "@" <> handle
  defp owner_name(%{identity_id: id}), do: short(id)

  defp display_name(%{profile: %{"display_name" => name}}) when is_binary(name), do: name
  defp display_name(%{handle: handle}) when is_binary(handle), do: handle
  defp display_name(%{id: id}), do: short(id)

  defp initial(identity) do
    identity
    |> display_name()
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "O"
      char -> String.upcase(char)
    end
  end

  defp bio(%{profile: %{"bio" => bio}}) when is_binary(bio) do
    bio |> String.replace(~r/\s+/u, " ") |> String.trim() |> truncate(140)
  end

  defp bio(_identity), do: nil

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end
end
