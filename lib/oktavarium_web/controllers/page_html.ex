defmodule OktavariumWeb.PageHTML do
  @moduledoc false
  use OktavariumWeb, :html

  attr :entries, :list, required: true
  attr :images, :list, default: []
  attr :tracks, :list, default: []

  def home(assigns) do
    ~H"""
    <section class="intro">
      <h1>Kto tu pracuje</h1>
      <p class="lead">
        Każda tożsamość prowadzi własny dziennik podpisanych zdarzeń.
        Te strony pokazują jego bieżący stan i całą historię.
      </p>
    </section>

    <section :if={@entries == []} class="empty" aria-labelledby="empty-h">
      <h2 id="empty-h">Nie ma jeszcze żadnych tożsamości</h2>
      <p>
        Wygeneruj klucz, podpisz zdarzenie założycielskie w CLI i wyślij je na serwer.
        Klucze prywatne zostają na Twoim komputerze.
      </p>
      <pre class="code"><code>mix oktavarium.key.gen --out keys/ja.key
    mix oktavarium.key.gen --kind auth --out keys/laptop.key
    mix oktavarium.identity.create --key keys/ja.key --kind user --handle ja \
      --auth-key ID_KLUCZA_AUTH --out events/ja-0.json
    mix oktavarium.submit events/ja-0.json</code></pre>
    </section>

    <ul :if={@entries != []} class="directory" aria-label="Lista tożsamości">
      <li :for={entry <- @entries}>
        <a class="row" href={~p"/i/#{entry.identity.handle || entry.identity.id}"}>
          <span class="row-main">
            <span class="row-name">{display_name(entry.identity)}</span>
            <span :if={entry.identity.handle} class="row-handle">@{entry.identity.handle}</span>
            <span :if={bio(entry.identity)} class="row-bio">{bio(entry.identity)}</span>
          </span>
          <span class="row-meta">
            <span>{kind_name(entry.identity.kind)}</span>
            <span>{plural(entry.events, "zdarzenie", "zdarzenia", "zdarzeń")}</span>
            <code :if={entry.head} class="hash" title={entry.head}>{short(entry.head)}</code>
          </span>
        </a>
      </li>
    </ul>

    <section :if={@images != []} class="gallery-section" aria-labelledby="gallery-h">
      <h2 id="gallery-h">Galeria</h2>
      <p class="section-note">Najnowsze obrazy publicznych tożsamości.</p>
      <ul class="gallery">
        <li :for={img <- @images}>
          <figure>
            <a href={~p"/i/#{img.handle || img.identity_id}"}>
              <img
                src={~p"/blobs/#{img.hash}"}
                alt={img.meta["alt"] || img.meta["title"] || ""}
                loading="lazy"
                decoding="async"
              />
            </a>
            <figcaption>
              <span :if={img.meta["title"]} class="cap-title">{img.meta["title"]}</span>
              <a class="cap-by" href={~p"/i/#{img.handle || img.identity_id}"}>{owner_name(img)}</a>
            </figcaption>
          </figure>
        </li>
      </ul>
    </section>

    <section :if={@tracks != []} class="tracks-section" aria-labelledby="tracks-h">
      <h2 id="tracks-h">Nagrania</h2>
      <ul class="tracks">
        <li :for={t <- @tracks}>
          <div class="track-head">
            <span class="cap-title">{t.meta["title"] || t.path}</span>
            <a class="cap-by" href={~p"/i/#{t.handle || t.identity_id}"}>{owner_name(t)}</a>
          </div>
          <audio controls preload="none" src={~p"/blobs/#{t.hash}"}></audio>
        </li>
      </ul>
    </section>
    """
  end

  defp owner_name(%{profile: %{"display_name" => name}}) when is_binary(name), do: name
  defp owner_name(%{handle: handle}) when is_binary(handle), do: "@" <> handle
  defp owner_name(%{identity_id: id}), do: short(id)

  defp display_name(%{profile: %{"display_name" => name}}) when is_binary(name), do: name
  defp display_name(%{handle: handle}) when is_binary(handle), do: handle
  defp display_name(%{id: id}), do: short(id)

  defp bio(%{profile: %{"bio" => bio}}) when is_binary(bio) do
    bio |> String.replace(~r/\s+/u, " ") |> String.trim() |> truncate(140)
  end

  defp bio(_identity), do: nil

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "...", else: text
  end
end
