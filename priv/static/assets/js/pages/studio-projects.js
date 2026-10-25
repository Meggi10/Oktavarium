import { h, field } from "../lib/ui.js";
import { projectResource } from "../lib/permissions.js";
function projectSelect(id, projects, value = null) {
  return h(
    "select",
    { id },
    h(
      "option",
      { value: "", selected: value == null },
      "Przestrze\u0144 g\u0142\xF3wna",
    ),
    projects.map((p) =>
      h(
        "option",
        { value: p.id, selected: p.id === value },
        p.meta.title || p.slug,
      ),
    ),
  );
}
function projectsSection(d, { editable, selected, onSelect, act, can }) {
  const projects = d.projects || [];
  const p = projects.find((p2) => p2.id === selected);
  const slug = h("input", {
    id: "project-slug",
    required: true,
    pattern: "[a-z0-9][a-z0-9\\-]{0,59}",
    maxlength: 60,
  });
  const title = h("input", {
    id: "project-title",
    required: true,
    maxlength: 120,
  });
  const description = h("textarea", {
    id: "project-description",
    rows: 3,
    maxlength: 1e3,
  });
  const create =
    editable &&
    h(
      "details",
      {},
      h("summary", {}, "Nowy projekt"),
      h(
        "form",
        {
          id: "project-create",
          class: "stack",
          onsubmit: async (e) => {
            e.preventDefault();
            const meta = { title: title.value.trim() };
            if (description.value.trim())
              meta.description = description.value.trim();
            await act("project.create", { slug: slug.value, meta });
          },
        },
        field("Nazwa", title),
        field(
          "Slug",
          slug,
          "Ma\u0142e litery, cyfry i my\u015Blniki. Nie jest identyfikatorem uprawnie\u0144.",
        ),
        field("Opis", description),
        h(
          "button",
          {
            id: "create-project",
            type: "submit",
            class: "btn primary",
            disabled: !can("project.create", d.id + "/projects"),
          },
          "Podpisz utworzenie projektu",
        ),
      ),
    );
  return h(
    "section",
    { class: "panel", "aria-labelledby": "projects-h" },
    h("h2", { id: "projects-h" }, "Projekty"),
    h(
      "div",
      { class: "project-grid" },
      projects.map((project) =>
        h(
          "button",
          {
            type: "button",
            class: "project-card",
            onclick: () => onSelect(project.id),
          },
          h("p", { class: "eyebrow" }, "Projekt"),
          h("h3", {}, project.meta.title || project.slug),
          h("p", {}, project.meta.description || "Brak opisu."),
        ),
      ),
    ),
    h(
      "p",
      { class: "section-note" },
      "Projekt jest zbiorem zasob\xF3w tej to\u017Csamo\u015Bci. Zmiana nazwy nie zmienia ID ani uprawnie\u0144.",
    ),
    !projects.length &&
      h("p", { class: "muted" }, "Nie ma jeszcze projekt\xF3w."),
    p &&
      h(
        "div",
        { class: "stack", id: "project-details" },
        h("h3", {}, p.meta.title || p.slug),
        h("p", {}, p.meta.description || "Brak opisu."),
        h("p", {}, "ID: ", h("code", {}, p.id)),
        h(
          "p",
          {},
          "Zakres uprawnie\u0144: ",
          h("code", {}, projectResource(d.id, p.id) + "/*"),
        ),
        p.site_url &&
          h(
            "a",
            {
              id: "project-site",
              href: p.site_url,
              target: "_blank",
              rel: "noopener noreferrer",
            },
            "Otw\xF3rz stron\u0119 projektu",
          ),
        h(
          "a",
          {
            class: "btn",
            href: `/i/${encodeURIComponent(d.handle || d.id)}/projects/${encodeURIComponent(p.id)}`,
          },
          "Publiczny projekt",
        ),
        h(
          "a",
          {
            href: `/api/identities/${encodeURIComponent(d.id)}/projects/${encodeURIComponent(p.id)}`,
          },
          "Projekt i pliki (JSON)",
        ),
        editable && projectEditor(d, p, { act, can }),
      ),
    create,
  );
}
function projectEditor(d, p, { act, can }) {
  const title = h("input", {
    id: "project-edit-title",
    value: p.meta.title || "",
    required: true,
    maxlength: 120,
  });
  const slug = h("input", {
    id: "project-edit-slug",
    value: p.slug,
    required: true,
    pattern: "[a-z0-9][a-z0-9\\-]{0,59}",
    maxlength: 60,
  });
  const description = h(
    "textarea",
    { id: "project-edit-description", rows: 3, maxlength: 1e3 },
    p.meta.description || "",
  );
  const scope = projectResource(d.id, p.id);
  const nonempty = d.resources.some((r) => r.project_id === p.id);
  return h(
    "details",
    {},
    h("summary", {}, "Edytuj projekt"),
    h(
      "form",
      {
        id: "project-edit",
        class: "stack",
        onsubmit: async (e) => {
          e.preventDefault();
          const meta = { ...p.meta, title: title.value.trim() };
          if (description.value.trim())
            meta.description = description.value.trim();
          else delete meta.description;
          await act("project.update", { id: p.id, slug: slug.value, meta });
        },
      },
      field("Nazwa", title),
      field("Slug", slug),
      field("Opis", description),
      h(
        "div",
        { class: "actions" },
        h(
          "button",
          {
            id: "save-project",
            class: "btn primary",
            type: "submit",
            disabled: !can("project.update", scope),
          },
          "Podpisz zmiany",
        ),
        h(
          "button",
          {
            id: "delete-project",
            class: "btn",
            type: "button",
            disabled: nonempty || !can("project.delete", scope),
            onclick: () => act("project.delete", { id: p.id }),
          },
          "Usu\u0144 pusty projekt",
        ),
      ),
      nonempty &&
        h(
          "p",
          { class: "muted" },
          "Przed usuni\u0119ciem projektu usu\u0144 lub przenie\u015B jego pliki.",
        ),
    ),
  );
}
export { projectSelect, projectsSection };
