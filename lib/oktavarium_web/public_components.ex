defmodule OktavariumWeb.PublicComponents do
  @moduledoc false
  use OktavariumWeb, :html

  attr :project, :map, required: true
  attr :identity, :map, required: true

  def project_card(assigns) do
    ~H"""
    <a class="project-card" href={~p"/i/#{@identity.handle || @identity.id}/projects/#{@project.id}"}>
      <span class="eyebrow">Projekt</span>
      <h3>{@project.meta["title"] || String.replace_prefix(@project.path, "projects/", "")}</h3>
      <p>{@project.meta["description"] || "Zbiór materiałów tej tożsamości."}</p>
      <span class="project-owner">{@identity.profile["display_name"] || @identity.handle ||
        short(@identity.id)} <span aria-hidden="true">→</span></span>
    </a>
    """
  end

  attr :resource, :map, required: true
  attr :identity, :map, required: true

  def file_card(assigns) do
    assigns = assign(assigns, :available, Oktavarium.Blobs.exists?(assigns.resource.hash))

    ~H"""
    <article class="public-file" data-resource-id={@resource.id}>
      <div :if={!@available} class="notice warn">
        <strong>Treść niedostępna.</strong> Pozostała referencja; nie ma bajtów w magazynie.
      </div>
      <a
        :if={@available && @resource.kind == :image}
        class="media-link"
        href={~p"/blobs/#{@resource.hash}"}
        target="_blank"
        rel="noopener noreferrer"
      >
        <img
          src={~p"/blobs/#{@resource.hash}"}
          alt={@resource.meta["alt"] || @resource.meta["title"] || @resource.path}
          loading="lazy"
        />
      </a>
      <audio
        :if={@available && @resource.kind == :audio}
        controls
        preload="none"
        src={~p"/blobs/#{@resource.hash}"}
        aria-label={@resource.meta["title"] || @resource.path}
      ></audio>
      <h3>{@resource.meta["title"] || @resource.path}</h3>
      <p :if={@resource.meta["description"]}>{@resource.meta["description"]}</p>
      <code>{@resource.path}</code>
      <a
        :if={@available}
        class="btn small"
        href={~p"/api/identities/#{@identity.id}/resources/#{@resource.id}/download"}
        download
      >Pobierz plik</a>
    </article>
    """
  end
end
