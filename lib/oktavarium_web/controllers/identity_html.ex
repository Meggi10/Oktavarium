defmodule OktavariumWeb.IdentityHTML do
  @moduledoc false
  use OktavariumWeb, :html

  import OktavariumWeb.PublicComponents

  @field_labels %{
    "display_name" => "Nazwa",
    "bio" => "Opis",
    "location" => "Miejsce",
    "website" => "Strona"
  }

  def show(assigns) do
    assigns =
      assigns
      |> Map.put_new(:projects, [])
      |> Map.put(:profile, assigns.identity.profile || %{})
      |> Map.put(:ref, assigns.identity.handle || assigns.identity.id)
      |> Map.put(:images, images(assigns.resources))
      |> Map.put(:tracks, tracks(assigns.resources))
      |> Map.put(:site_files, site_files(assigns.resources))

    ~H"""
    <article class="profile-page">
      <a class="back-link" href={~p"/"}><span aria-hidden="true">←</span> Odkrywaj</a>
      <header class="profile-header">
        <img
          :if={@avatar_hash}
          class="avatar avatar-large avatar-photo"
          src={~p"/blobs/#{@avatar_hash}"}
          alt={"Zdjęcie profilowe: " <> name(@identity)}
          decoding="async"
        />
        <span
          :if={!@avatar_hash}
          class="avatar avatar-large"
          data-kind={@identity.kind}
          aria-hidden="true"
        >{initial(@identity)}</span>
        <div class="profile-copy">
          <p class="eyebrow">{public_kind(@identity.kind)}</p>
          <h1>{name(@identity)}</h1>
          <p :if={@identity.handle} class="profile-handle">@{@identity.handle}</p>
          <p :if={@profile["bio"]} class="bio">{@profile["bio"]}</p>
          <p :if={profile_empty?(@profile)} class="muted">Ta tożsamość nie ma jeszcze opisu.</p>
          <dl :if={@profile["location"] || @profile["website"]} class="facts">
            <div :if={@profile["location"]}>
              <dt>Miejsce</dt>
              <dd>{@profile["location"]}</dd>
            </div>
            <div :if={@profile["website"]}>
              <dt>Strona</dt>
              <dd>
                <a
                  :if={web_url?(@profile["website"])}
                  href={@profile["website"]}
                  rel="nofollow noopener noreferrer ugc"
                >{@profile["website"]}</a>
                <span :if={!web_url?(@profile["website"])}>{@profile["website"]}</span>
              </dd>
            </div>
          </dl>
        </div>
        <div class="profile-actions">
          <a class="btn" href={~p"/studio?#{[ref: @ref]}"}>Otwórz w Pracowni</a>
          <span :if={@identity.visibility == :unlisted} class="tag">Nieindeksowana · dostępna przez adres</span>
          <a :if={@site_url} class="btn" href={@site_url} target="_blank" rel="noopener noreferrer">
            Własna strona <span aria-hidden="true">↗</span>
            <span class="sr">(otwiera się w nowej karcie)</span>
          </a>
        </div>
      </header>

      <p :if={@integrity != :ok} class="notice bad" role="alert">{integrity_text(@integrity)}</p>

      <section
        :if={@projects != []}
        id="profile-projects"
        class="gallery-section"
        aria-labelledby="profile-projects-h"
      >
        <div class="section-heading">
          <h2 id="profile-projects-h">Projekty</h2>
        </div>
        <div class="project-grid">
          <.project_card :for={p <- @projects} project={p} identity={@identity} />
        </div>
      </section>

      <section id="resources" aria-labelledby="res-h" class="resources-section profile-resources">
        <div class="section-heading">
          <h2 id="res-h">Publikacje</h2>
          <span class="section-note">Zasoby tej przestrzeni</span>
        </div>
        <div :if={@images == [] && @tracks == [] && @site_files == []} class="feed-empty">
          <h3>Jeszcze nic tu nie opublikowano</h3>
          <p>Obrazy, nagrania i własna strona pojawią się w tym miejscu.</p>
        </div>
        <ul :if={@images != []} class="gallery" aria-label="Obrazy">
          <li :for={r <- @images}>
            <figure>
              <a
                :if={Oktavarium.Blobs.exists?(r.hash)}
                class="media-link"
                href={~p"/blobs/#{r.hash}"}
                target="_blank"
                rel="noopener noreferrer"
                aria-label={"Otwórz obraz: " <> (r.meta["title"] || r.path) <> " (nowa karta)"}
              >
                <img
                  src={~p"/blobs/#{r.hash}"}
                  alt={r.meta["alt"] || r.meta["title"] || r.path}
                  loading="lazy"
                  decoding="async"
                />
              </a>
              <p :if={!Oktavarium.Blobs.exists?(r.hash)} class="notice warn">
                Treść niedostępna. Historia i referencja pozostają.
              </p>
              <figcaption>
                <span class="cap-title">{r.meta["title"] || r.path}</span>
                <p :if={r.meta["description"]} class="media-description">{r.meta["description"]}</p>
              </figcaption>
            </figure>
          </li>
        </ul>
        <ul :if={@tracks != []} class="tracks" aria-label="Nagrania">
          <li :for={r <- @tracks}>
            <div class="track-head"><span class="cap-title">{r.meta["title"] || r.path}</span></div>
            <p :if={!Oktavarium.Blobs.exists?(r.hash)} class="notice warn">
              Treść niedostępna. Historia i referencja pozostają.
            </p>
            <audio
              :if={Oktavarium.Blobs.exists?(r.hash)}
              controls
              preload="none"
              src={~p"/blobs/#{r.hash}"}
              aria-label={"Odtwórz: " <> (r.meta["title"] || r.path)}
            >
              <a href={~p"/blobs/#{r.hash}"}>Pobierz nagranie</a>
            </audio>
          </li>
        </ul>
        <section :if={@site_files != []} class="site-card" aria-labelledby="site-h">
          <div>
            <p class="eyebrow">Własna przestrzeń</p>
            <h3 id="site-h">Strona internetowa</h3>
            <p>{plural(length(@site_files), "plik strony", "pliki strony", "plików strony")}</p>
            <p :if={!@site_url} class="muted">Podgląd strony nie jest jeszcze dostępny.</p>
          </div>
          <a :if={@site_url} class="btn" href={@site_url} target="_blank" rel="noopener noreferrer">
            Otwórz stronę <span aria-hidden="true">↗</span>
            <span class="sr">(otwiera się w nowej karcie)</span>
          </a>
        </section>
      </section>

      <details id="profile-details" class="technical" open={@before != nil || @integrity != :ok}>
        <summary>
          <span>Historia i szczegóły techniczne</span>
          <span class="technical-caption">Dziennik, klucze i uprawnienia</span>
        </summary>
        <div class="technical-grid">
          <aside class="title-block" aria-label="Dane tożsamości">
            <dl>
              <div>
                <dt>Rodzaj</dt>
                <dd>{kind_name(@identity.kind)}</dd>
              </div>
              <div>
                <dt>Założono</dt>
                <dd><.time_tag at={@identity.inserted_at} /></dd>
              </div>
              <div>
                <dt>Identyfikator</dt>
                <dd class="full-id"><.key_id id={@identity.id} /></dd>
              </div>
              <div :if={@founding_key}>
                <dt>Klucz założycielski</dt>
                <dd><.key_id id={@founding_key} /></dd>
              </div>
              <div>
                <dt>Klucze autoryzacji</dt>
                <dd>
                  <span :for={k <- @auth_keys} class="auth-key">
                    <.key_id id={k.key_id} />
                    <span :if={k.status == :revoked} class="tag bad">unieważniony</span>
                  </span>
                </dd>
              </div>
              <div>
                <dt>Zdarzenia</dt>
                <dd>{@event_count}</dd>
              </div>
              <div :if={@integrity == :ok} class="integrity ok">
                <dt>Dziennik</dt>
                <dd>
                  Zweryfikowany: podpisy i łańcuch zdarzeń się zgadzają.
                  <a href={~p"/api/identities/#{@identity.id}/events"}>Pobierz JSON</a>
                </dd>
              </div>
              <div :if={@integrity != :ok} class="integrity bad">
                <dt>Dziennik</dt>
                <dd>{integrity_text(@integrity)}</dd>
              </div>
            </dl>
          </aside>

          <div class="id-rest">
            <section :if={@members != []} aria-labelledby="members-h" class="members-section">
              <h2 id="members-h">Klucze urządzeń</h2>
              <p class="section-note">
                Klucze dopisane do tej tożsamości. Same niczego nie mogą: uprawnienia dają granty.
              </p>
              <ul class="members">
                <li :for={m <- @members}>
                  <.key_id id={m.key_id} />
                  <span :if={m.label} class="muted">{m.label}</span>
                  <span :if={m.status == :revoked} class="tag bad">cofnięty</span>
                </li>
              </ul>
            </section>

            <section aria-labelledby="grants-h" class="grants-section">
              <h2 id="grants-h">Uprawnienia</h2>
              <p class="section-note">
                Klucz założycielski może wszystko w tej przestrzeni. Poniżej to, co nadał innym kluczom.
              </p>
              <p :if={@grants == []} class="muted">Nikomu nie nadano uprawnień.</p>
              <table :if={@grants != []} class="grants">
                <caption class="sr">Uprawnienia nadane innym kluczom</caption>
                <thead>
                  <tr>
                    <th scope="col">Komu</th>
                    <th scope="col">Co może</th>
                    <th scope="col">Gdzie</th>
                    <th scope="col">Kiedy</th>
                    <th scope="col">Stan</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={g <- @grants} class={["grant", "is-#{g.status}"]}>
                    <td data-label="Komu">
                      <.holder key_id={g.subject_key_id} homes={@homes} />
                      <span :if={g.delegable} class="tag">może przekazywać dalej</span>
                    </td>
                    <td data-label="Co może"><code class="cap">{g.action}</code></td>
                    <td data-label="Gdzie">
                      <code class="cap" title={g.resource}>{relative(g.resource, @identity.id)}</code>
                    </td>
                    <td data-label="Kiedy">{window_text(g.not_before, g.expires_at)}</td>
                    <td data-label="Stan">
                      <span class={["status", "is-#{g.status}"]}>{status_label(g.status)}</span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </section>

            <section aria-labelledby="log-h" class="log-section">
              <h2 id="log-h">Dziennik</h2>
              <p class="section-note">
                Najnowsze zdarzenia są na górze. Każde jest podpisane i wskazuje poprzednie.
              </p>
              <p :if={@before} class="section-note">
                <a href={~p"/i/#{@ref}"}>Wróć do najnowszych zdarzeń</a>
              </p>
              <ol class={["log", @next_before && "continues"]}>
                <li
                  :for={e <- @entries}
                  class={["event", e.seq == 0 && "is-genesis", e[:corrupt] && "is-corrupt"]}
                >
                  <div class="ev-head">
                    <span class="ev-seq">#{e.seq}</span>
                    <h3 class="ev-title">{event_title(e)}</h3>
                    <.time_tag at={e.received_at} />
                  </div>
                  <.event_body e={e} identity_id={@identity.id} homes={@homes} />
                  <p class="ev-meta">
                    Podpisał <.holder key_id={e.signer} homes={@homes} />
                    <.key_id id={e.id} />
                  </p>
                </li>
              </ol>
              <p :if={@next_before} class="older">
                <a href={~p"/i/#{@ref}?#{[before: @next_before]}"}>Starsze zdarzenia</a>
              </p>
            </section>
          </div>
        </div>
      </details>
    </article>
    """
  end

  # treść zdarzeń

  attr :e, :map, required: true
  attr :identity_id, :string, required: true
  attr :homes, :map, required: true

  defp event_body(%{e: %{corrupt: reason}} = assigns) do
    assigns = assign(assigns, :reason, inspect(reason))

    ~H"""
    <p class="ev-line bad">Podpis albo struktura zdarzenia są niepoprawne ({@reason}).</p>
    """
  end

  defp event_body(%{e: %{type: "identity.genesis", body: body}} = assigns) do
    assigns =
      assign(assigns,
        body: body,
        auth_count: body |> Map.get("auth_keys", []) |> List.wrap() |> length()
      )

    ~H"""
    <p class="ev-line">Rodzaj: {kind_name(@body["kind"])}</p>
    <p :if={@body["handle"]} class="ev-line">Uchwyt: @{@body["handle"]}</p>
    <p class="ev-line">
      {plural(@auth_count, "klucz autoryzacji", "klucze autoryzacji", "kluczy autoryzacji")}
    </p>
    """
  end

  defp event_body(%{e: %{type: "grant.create", body: body}} = assigns) do
    assigns =
      assign(assigns,
        body: body,
        window: window_text(from_unix(body["not_before"]), from_unix(body["expires_at"]))
      )

    ~H"""
    <p class="ev-line">
      <code class="cap">{@body["action"]}</code>
      na
      <code class="cap" title={@body["resource"]}>{relative(@body["resource"], @identity_id)}</code>
    </p>
    <p :if={is_binary(@body["subject"])} class="ev-line">
      Dla <.holder key_id={@body["subject"]} homes={@homes} />
    </p>
    <p :if={@body["delegable"] == true} class="ev-line">Może przekazywać to uprawnienie dalej.</p>
    <p :if={@window != ""} class="ev-line">Obowiązuje {@window}.</p>
    """
  end

  defp event_body(%{e: %{type: "profile.update", body: body}} = assigns) do
    fields = body |> Map.get("fields", %{}) |> Enum.sort()
    assigns = assign(assigns, :fields, fields)

    ~H"""
    <dl class="changes">
      <div :for={{field, value} <- @fields}>
        <dt>{Map.get(field_labels(), field, field)}</dt>
        <dd :if={is_binary(value)} class="set">{clip(value)}</dd>
        <dd :if={is_map(value) and is_binary(value["sha256"])} class="set">
          wersja SHA-256: <.key_id id={value["sha256"]} />
        </dd>
        <dd :if={is_nil(value)} class="unset">usunięto</dd>
      </div>
    </dl>
    """
  end

  defp event_body(%{e: %{type: "grant.revoke", body: body}} = assigns) do
    assigns = assign(assigns, :body, body)

    ~H"""
    <p class="ev-line">
      Cofnięto uprawnienie <.key_id id={@body["grant"] || ""} />
    </p>
    """
  end

  defp event_body(%{e: %{type: type, body: body}} = assigns)
       when type in ["key.add", "key.revoke"] do
    assigns = assign(assigns, :body, body)

    ~H"""
    <p :if={is_binary(@body["key"])} class="ev-line">
      <.holder key_id={@body["key"]} homes={@homes} />
    </p>
    <p :if={is_binary(@body["label"])} class="ev-line">Etykieta: {clip(@body["label"])}</p>
    """
  end

  defp event_body(%{e: %{type: "resource.put", body: body}} = assigns) do
    assigns = assign(assigns, :body, body)

    ~H"""
    <p class="ev-line">
      <code class="cap">{@body["path"]}</code>
      <span class="muted">{@body["media_type"]}, {format_size(@body["size"])}</span>
    </p>
    <p :if={is_binary(@body["meta"]["title"])} class="ev-line">{clip(@body["meta"]["title"])}</p>
    """
  end

  defp event_body(%{e: %{type: "resource.delete", body: body}} = assigns) do
    assigns = assign(assigns, :body, body)

    ~H"""
    <p class="ev-line"><code class="cap">{@body["path"]}</code></p>
    """
  end

  defp event_body(assigns) do
    ~H"""
    <p class="ev-line muted">Ten typ zdarzenia nie ma jeszcze opisu na stronie.</p>
    """
  end

  defp field_labels, do: @field_labels

  defp event_title(%{corrupt: _}), do: "Zdarzenie nie przechodzi weryfikacji"
  defp event_title(%{type: "identity.genesis"}), do: "Założono tożsamość"
  defp event_title(%{type: "grant.create"}), do: "Nadano uprawnienie"
  defp event_title(%{type: "profile.update"}), do: "Zmieniono profil"
  defp event_title(%{type: "grant.revoke"}), do: "Cofnięto uprawnienie"
  defp event_title(%{type: "key.add"}), do: "Dopisano klucz urządzenia"
  defp event_title(%{type: "key.revoke"}), do: "Cofnięto klucz urządzenia"
  defp event_title(%{type: "resource.put"}), do: "Zapisano zasób"
  defp event_title(%{type: "resource.delete"}), do: "Usunięto zasób"
  defp event_title(%{type: type}), do: "Zdarzenie " <> type

  # pomocnicze

  defp public_kind(:user), do: "osoba"
  defp public_kind(:org), do: "kolektyw"
  defp public_kind(kind), do: kind_name(kind)

  defp initial(identity) do
    identity
    |> name()
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "O"
      char -> String.upcase(char)
    end
  end

  defp images(resources),
    do:
      Enum.filter(
        resources,
        &(&1.kind == :image and
            not (is_nil(&1.project_id) and &1.path == Oktavarium.Directory.avatar_path()))
      )

  defp tracks(resources), do: Enum.filter(resources, &(&1.kind == :audio))

  defp site_files(resources),
    do: Enum.filter(resources, &(&1.kind == :site and is_nil(&1.project_id)))

  defp format_size(n) when is_integer(n) and n >= 1_048_576,
    do: "#{Float.round(n / 1_048_576, 1)} MiB"

  defp format_size(n) when is_integer(n) and n >= 1024, do: "#{Float.round(n / 1024, 1)} KiB"
  defp format_size(n) when is_integer(n), do: "#{n} B"
  defp format_size(_other), do: "?"

  defp name(%{profile: %{"display_name" => n}}) when is_binary(n), do: n
  defp name(%{handle: handle}) when is_binary(handle), do: handle
  defp name(%{id: id}), do: short(id)

  defp profile_empty?(profile),
    do: Enum.all?(["bio", "location", "website"], &is_nil(profile[&1]))

  defp web_url?(url) when is_binary(url), do: String.starts_with?(url, ["http://", "https://"])
  defp web_url?(_url), do: false

  defp relative(resource, identity_id) when is_binary(resource),
    do: String.replace_prefix(resource, identity_id, "")

  defp relative(_resource, _identity_id), do: ""

  defp clip(text) do
    if String.length(text) > 200, do: String.slice(text, 0, 199) <> "...", else: text
  end

  defp window_text(nil, nil), do: ""
  defp window_text(from, nil), do: "od " <> format_time(from)
  defp window_text(nil, until), do: "do " <> format_time(until)
  defp window_text(from, until), do: "od " <> format_time(from) <> " do " <> format_time(until)

  defp status_label(:active), do: "aktywne"
  defp status_label(:revoked), do: "unieważnione"
  defp status_label(:expired), do: "wygasło"
  defp status_label(:pending), do: "jeszcze nie obowiązuje"
  defp status_label(:broken), do: "łańcuch uprawnień jest przerwany"

  defp integrity_text({:error, {:corrupt, seq, _reason}}),
    do: "Uszkodzony od zdarzenia ##{seq}: podpis albo łańcuch się nie zgadzają."

  defp integrity_text({:error, :unknown_identity}), do: "Brak zdarzeń do sprawdzenia."
  defp integrity_text(_other), do: "Nie udało się zweryfikować dziennika."
end
