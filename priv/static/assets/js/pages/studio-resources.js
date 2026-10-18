import { h, field } from "../lib/ui.js";
import { fileResource } from "../lib/permissions.js";
import { projectSelect } from "./studio-projects.js";

export const KIND_LABEL = {
  image: "Obraz",
  audio: "Nagranie",
  site: "Plik strony",
};
const TYPES = {
  html: "text/html",
  htm: "text/html",
  css: "text/css",
  js: "text/javascript",
  mjs: "text/javascript",
  json: "application/json",
  txt: "text/plain",
  svg: "image/svg+xml",
  png: "image/png",
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  gif: "image/gif",
  webp: "image/webp",
  ico: "image/x-icon",
  woff: "font/woff",
  woff2: "font/woff2",
  mp3: "audio/mpeg",
  ogg: "audio/ogg",
  oga: "audio/ogg",
  opus: "audio/ogg",
  wav: "audio/wav",
  flac: "audio/flac",
  m4a: "audio/mp4",
};
export const fmtSize = (n) =>
  n >= 1048576
    ? (n / 1048576).toFixed(1) + " MiB"
    : n >= 1024
      ? (n / 1024).toFixed(1) + " KiB"
      : n + " B";

export function buildPath(kind, raw) {
  if (kind === "site") {
    const p = raw.replace(/^\/+/, "");
    // Backend permits at most seven segments below site/ and 200 bytes total.
    const path = "site/" + p;
    return /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}(\/[A-Za-z0-9][A-Za-z0-9._-]{0,79}){0,6}$/.test(
      p,
    ) && path.length <= 200
      ? path
      : null;
  }
  const slug = raw
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/^[^a-z0-9]+/, "")
    .slice(0, 80);
  return slug ? (kind === "image" ? "images/" : "audio/") + slug : null;
}

const ACCEPTED = {
  image: ["image/png", "image/jpeg", "image/gif", "image/webp"],
  audio: ["audio/mpeg", "audio/ogg", "audio/wav", "audio/flac", "audio/mp4"],
  site: [
    "text/html",
    "text/css",
    "text/javascript",
    "text/plain",
    "application/json",
    "image/svg+xml",
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
    "image/x-icon",
    "font/woff",
    "font/woff2",
    "audio/mpeg",
    "audio/ogg",
  ],
};
export function validateFile(file, path, type) {
  const kind = path.startsWith("images/")
    ? "image"
    : path.startsWith("audio/")
      ? "audio"
      : "site";
  if (!ACCEPTED[kind].includes(type))
    throw new Error(
      "Ten format nie jest obsługiwany w wybranym rodzaju zasobu.",
    );
  const max = { image: 10, audio: 50, site: 5 }[kind] * 1024 * 1024;
  if (!file.size || file.size > max)
    throw new Error(
      "Plik jest pusty lub przekracza limit " + fmtSize(max) + ".",
    );
}
export function resourcesSection(
  d,
  { editable, selected, act, publishFile, say, can },
) {
  const files = d.resources.filter(
    (r) => selected === "all" || (r.project_id || null) === selected,
  );
  const list = h("ul", { class: "res-list", id: "resource-list" });
  const count = h("p", { class: "hint", role: "status" });
  const search = h("input", {
    id: "resource-search",
    type: "search",
    placeholder: "Nazwa lub ścieżka",
    "aria-label": "Szukaj zasobu",
  });
  const kind = h(
    "select",
    { id: "resource-filter", "aria-label": "Rodzaj pliku" },
    h("option", { value: "all" }, "Wszystkie pliki"),
    Object.entries(KIND_LABEL).map(([value, label]) =>
      h("option", { value }, label),
    ),
  );
  const renderList = () => {
    const q = search.value.trim().toLocaleLowerCase("pl");
    const filtered = files.filter(
      (r) =>
        (kind.value === "all" || r.kind === kind.value) &&
        [r.path, r.meta.title || ""]
          .join(" ")
          .toLocaleLowerCase("pl")
          .includes(q),
    );
    list.replaceChildren(
      ...filtered.map((r) => {
        const ownerProject = d.projects.find((p) => p.id === r.project_id);
        const url = `/api/identities/${encodeURIComponent(d.id)}/resources/${encodeURIComponent(r.id)}/download`;
        return h(
          "li",
          { "data-resource-id": r.id },
          r.kind === "image" &&
            r.available !== false &&
            h("img", {
              src: "/blobs/" + r.hash,
              alt: r.meta.alt || "",
              width: 64,
              loading: "lazy",
              onerror: (e) => {
                e.target.hidden = true;
              },
            }),
          h(
            "div",
            { class: "res-main" },
            h("h3", {}, r.meta.title || r.path),
            h(
              "p",
              { class: "hint" },
              h("code", {}, r.path),
              " · ",
              fmtSize(r.size),
            ),
            h(
              "p",
              { class: "hint" },
              ownerProject
                ? "Projekt: " + (ownerProject.meta.title || ownerProject.slug)
                : "Przestrzeń główna",
            ),
            r.meta.description && h("p", {}, r.meta.description),
            r.available === false
              ? h(
                  "p",
                  { class: "notice warn" },
                  "Treść niedostępna. Referencja i historia pozostają.",
                )
              : h(
                  "div",
                  { class: "actions" },
                  r.kind !== "site" &&
                    h(
                      "a",
                      {
                        class: "btn small",
                        href: "/blobs/" + r.hash,
                        target: "_blank",
                        rel: "noopener noreferrer",
                      },
                      "Otwórz",
                    ),
                  h(
                    "a",
                    { class: "btn small", href: url, download: "" },
                    "Pobierz plik",
                  ),
                ),
            editable && fileEditor(d, r, { act, say, can }),
          ),
        );
      }),
    );
    count.textContent = filtered.length
      ? "Pliki: " + filtered.length
      : "Brak plików pasujących do tego zakresu i filtra.";
  };
  search.addEventListener("input", renderList);
  kind.addEventListener("change", renderList);
  renderList();
  return h(
    "section",
    { class: "panel", "aria-labelledby": "res-h" },
    h("h2", { id: "res-h" }, "Pliki w wybranym zakresie"),
    h(
      "p",
      { class: "section-note" },
      selected === "all"
        ? "Wszystkie pliki tożsamości, także w projektach."
        : "Pliki wybranej przestrzeni.",
    ),
    h("div", { class: "toolbar" }, search, kind),
    count,
    list,
    editable
      ? h(
          "details",
          { class: "upload-section" },
          h("summary", {}, "Dodaj materiał"),
          uploadForm(d, selected, { publishFile, say }),
        )
      : h(
          "p",
          { class: "hint" },
          "Odblokuj klucze, aby przygotować publikację. Odczyt nie wymaga logowania.",
        ),
  );
}

function uploadForm(d, projectId, { publishFile, say }) {
  const kind = h(
    "select",
    { id: "r-kind" },
    Object.entries(KIND_LABEL).map(([value, label]) =>
      h("option", { value }, label),
    ),
  );
  const file = h("input", { id: "r-file", type: "file", required: true });
  const name = h("input", {
    id: "r-name",
    autocomplete: "off",
    placeholder: "Nazwa pliku, bez images/, audio/ ani site/",
  });
  const target = projectSelect(
    "r-project",
    d.projects,
    projectId === "all" ? null : projectId,
  );
  if (projectId === "all") {
    target.prepend(
      h(
        "option",
        { value: "__choose", selected: true, disabled: true },
        "Wybierz miejsce publikacji",
      ),
    );
    target.value = "__choose";
  }
  const meta = metaInputs("r", {});
  const preview = h(
    "p",
    { class: "hint", role: "status" },
    "Nie wysyłamy pliku przy wyborze.",
  );
  file.addEventListener("change", () => {
    const f = file.files[0];
    preview.textContent = f
      ? f.name + " · " + fmtSize(f.size)
      : "Nie wybrano pliku.";
  });
  return h(
    "form",
    {
      id: "resource-upload",
      class: "stack",
      onsubmit: async (e) => {
        e.preventDefault();
        const f = file.files[0];
        if (!f) return;
        try {
          if (target.value === "__choose")
            throw new Error("Wybierz projekt albo przestrzeń główną.");
          const path = buildPath(kind.value, name.value.trim() || f.name);
          if (!path) throw new Error("Nieprawidłowa ścieżka pliku.");
          const type =
            TYPES[(f.name.split(".").pop() || "").toLowerCase()] || f.type;
          validateFile(f, path, type);
          await publishFile(f, {
            path,
            project_id: target.value || null,
            media_type: type,
            meta: readMeta(meta),
          });
        } catch (err) {
          say(err.message, "bad");
        }
      },
    },
    field("Cel publikacji", target),
    h("div", { class: "grid2" }, field("Rodzaj", kind), field("Plik", file)),
    preview,
    field("Nazwa / ścieżka względna", name),
    metaFields(meta),
    h(
      "p",
      { class: "notice warn" },
      "Po potwierdzeniu bajty trafią do serwera. Mogą być odczytywalne po skrócie, nawet jeśli publikacja zostanie odrzucona. Pliki stron uruchamiaj wyłącznie pod ich odrębnym adresem.",
    ),
    h(
      "button",
      { id: "upload", class: "btn primary", type: "submit" },
      "Sprawdź publikację",
    ),
  );
}

function fileEditor(d, r, { act, say, can }) {
  const path = h("input", {
    id: "path-" + r.id,
    required: true,
    value: r.path,
    maxlength: 200,
  });
  const project = projectSelect("move-" + r.id, d.projects, r.project_id);
  const meta = metaInputs("edit-" + r.id, r.meta);
  const source = fileResource(d.id, r.path, r.project_id);
  return h(
    "details",
    { class: "resource-edit" },
    h("summary", {}, "Edytuj lub przenieś"),
    h(
      "form",
      {
        class: "stack",
        onsubmit: async (e) => {
          e.preventDefault();
          const targetProject = project.value || null;
          const moved =
            path.value !== r.path || targetProject !== (r.project_id || null);
          if (moved && !can("resource.delete", source))
            return say("Przeniesienie wymaga resource.delete w źródle.", "bad");
          const dest = fileResource(d.id, path.value, targetProject);
          if (!can("resource.put", dest))
            return say("Brak prawa resource.put w miejscu docelowym.", "bad");
          await act("resource.put", {
            id: r.id,
            path: path.value,
            project_id: targetProject,
            hash: r.hash,
            size: r.size,
            media_type: r.media_type,
            meta: readMeta(meta),
          });
        },
      },
      field("Ścieżka", path),
      field("Projekt docelowy", project),
      metaFields(meta),
      h(
        "div",
        { class: "actions" },
        h(
          "button",
          { class: "btn primary", type: "submit" },
          "Podpisz zmiany pliku",
        ),
        h(
          "button",
          {
            class: "btn",
            type: "button",
            disabled: !can("resource.delete", source),
            onclick: () => act("resource.delete", { id: r.id }),
          },
          "Usuń plik",
        ),
      ),
    ),
  );
}

function metaInputs(prefix, meta) {
  return Object.fromEntries(
    [
      ["title", 120],
      ["alt", 300],
      ["description", 1000],
      ["collection", 40],
    ].map(([key, limit]) => [
      key,
      key === "description"
        ? h(
            "textarea",
            { id: prefix + "-" + key, rows: 2, maxlength: limit },
            meta[key] || "",
          )
        : h("input", {
            id: prefix + "-" + key,
            value: meta[key] || "",
            maxlength: limit,
          }),
    ]),
  );
}
const readMeta = (inputs) =>
  Object.fromEntries(
    Object.entries(inputs)
      .map(([key, input]) => [key, input.value.trim()])
      .filter(([, v]) => v),
  );
const metaFields = (inputs) => [
  field("Tytuł", inputs.title),
  field("Tekst alternatywny", inputs.alt),
  field("Opis", inputs.description),
  field("Kolekcja", inputs.collection),
];
