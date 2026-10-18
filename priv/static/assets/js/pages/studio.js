// C2: public workspace, local keys and signed mutations are separate concerns.
import { generateKey, sign, sha256 } from "../lib/crypto.js";
import { short, enc, unb64u, dec } from "../lib/bytes.js";
import { cliKeyfile } from "../lib/keystore.js";
import { localVault, rememberVault, lockVault } from "../lib/local-state.js";
import { unlockDialog } from "../lib/vault-ui.js";
import { Drafts } from "../lib/drafts.js";
import * as api from "../lib/api.js";
import {
  h,
  mount,
  field,
  notice,
  download,
  confirmSign,
  ask,
  actionLabel,
} from "../lib/ui.js";
import { permits, fileResource } from "../lib/permissions.js";
import { copyButton } from "../lib/copy-id.js";
import { projectsSection } from "./studio-projects.js";
import { resourcesSection, validateFile } from "./studio-resources.js";
import { AVATAR_PATH, avatarMediaType } from "../lib/avatar.js";
import { grantsSection } from "./studio-grants.js";

const root = document.getElementById("app");
const views = {
  overview: "Przegląd",
  profile: "Profil",
  projects: "Projekty",
  resources: "Zasoby",
  collaboration: "Współpraca",
  keys: "Klucze",
  history: "Historia",
};
const PROFILE_FIELDS = [
  ["display_name", "Nazwa wyświetlana", "input"],
  ["bio", "Opis", "textarea"],
  ["location", "Miejsce", "input"],
  ["website", "Strona (https://...)", "input"],
];
const state = {
  vault: null,
  signerId: null,
  authId: null,
  me: null,
  current: null,
  data: null,
  directory: [],
  access: null,
  projectId: "all",
  view: "overview",
  busy: false,
  message: null,
  events: null,
  loading: false,
  directoryError: null,
};
const drafts = new Drafts(),
  dirty = new Set(),
  bases = new Map();
const uploaded = new Set(); // Hashes acknowledged by this server in this tab.
let startPromise,
  ticket = 0;
const draftKey = () => [state.current, state.view, state.projectId].join(":");
const content = () => document.getElementById("studio-content");
function capture() {
  if (content() && dirty.has(draftKey())) drafts.capture(draftKey(), content());
}
const can = (action, resource) =>
  state.data?.integrity !== "error" &&
  Boolean(state.vault?.get(state.signerId)) &&
  (state.signerId === state.data?.founding_key ||
    permits(state.access, action, resource));
const label = (d) =>
  d?.profile?.display_name ||
  d?.display_name ||
  (d?.handle ? "@" + d.handle : d?.id ? short(d.id) : "Wybierz tożsamość");
const url = (
  view = state.view,
  project = state.projectId,
  ref = state.current,
) => {
  const p = new URLSearchParams({ view, scope: project || "root" });
  if (ref) p.set("ref", ref);
  if (project && project !== "all") p.set("project", project);
  return "/studio?" + p;
};
const publicUrl = () =>
  "/i/" + encodeURIComponent(state.data?.handle || state.current);
function parseUrl() {
  const p = new URLSearchParams(location.search);
  state.view = Object.hasOwn(views, p.get("view")) ? p.get("view") : "overview";
  state.projectId =
    p.get("project") || (p.get("scope") === "root" ? null : "all");
  return p.get("ref") || state.directory[0]?.id || null;
}

export function start() {
  if (startPromise) return startPromise;
  document.title = "Pracownia | Oktavarium";
  document.body.dataset.workspace = "true";
  root.classList.add("studio-app");
  state.vault = localVault();
  state.signerId = state.vault?.ofKind("signing")[0]?.id || null;
  state.authId = state.vault?.ofKind("auth")[0]?.id || null;
  const requestedRef = parseUrl();

  // Render immediately: the directory and IndexedDB must never gate the UI.
  render();
  window.addEventListener("popstate", onPop);
  window.addEventListener("beforeunload", (e) => {
    if (dirty.size || api.hasPending()) {
      e.preventDefault();
      e.returnValue = "";
    }
  });
  root.addEventListener("input", (e) => {
    if (
      !e.target.closest("#studio-content form") ||
      e.target.type === "password" ||
      e.target.closest("[data-local-only]")
    )
      return;
    const key = draftKey();
    dirty.add(key);
    if (!bases.has(key) && state.data?.head)
      bases.set(key, structuredClone(state.data.head));
  });

  // A direct /studio?ref=... must work even when /api/identities is unavailable.
  // Only public requests occur on entry. No /me, challenge or upload session.
  startPromise = (async () => {
    const catalogue = (async () => {
      try {
        const entries = await api.identities();
        if (!Array.isArray(entries))
          throw new Error("Nieprawidłowa odpowiedź katalogu.");
        state.directory = entries;
        state.directoryError = null;
        // Do not override a manually opened identity while the catalogue was pending.
        if (!requestedRef && ticket === 0 && !state.current && entries.length)
          await select(entries[0].id, false);
        else {
          capture();
          render();
        }
      } catch (e) {
        state.directoryError = e.message;
        capture();
        render();
      }
    })();
    if (requestedRef) await select(requestedRef, false);
    else await catalogue;
  })().catch((e) => {
    state.loading = false;
    state.message = {
      text: "Nie udało się uruchomić Pracowni: " + e.message,
      kind: "bad",
    };
    render();
  });
  return startPromise;
}
async function onPop() {
  if (state.busy) {
    history.replaceState(null, "", url());
    return;
  }
  capture();
  await select(parseUrl(), false);
}
async function select(id, push = true) {
  if (state.busy) return;
  capture();
  const generation = ++ticket;
  state.loading = Boolean(id);
  state.message = null;
  state.data = null;
  state.current = null;
  state.access = null;
  state.events = null;
  render();
  try {
    const d = id ? await api.identity(id) : null;
    if (generation !== ticket) return;
    state.data = d;
    state.current = d?.id || null;
    if (
      state.projectId &&
      state.projectId !== "all" &&
      !d?.projects.some((p) => p.id === state.projectId)
    )
      state.projectId = "all";
    if (push) history.pushState(null, "", url());
    // Show the selected identity even if the access lookup is slow.
    state.loading = false;
    render();
    await refreshAccess().catch((e) => {
      state.message = {
        text: "Nie można odczytać uprawnień: " + e.message,
        kind: "bad",
      };
    });
    if (generation === ticket) {
      capture();
      render();
    }
  } catch (e) {
    if (generation !== ticket) return;
    state.loading = false;
    state.message = {
      text: "Nie udało się otworzyć tożsamości: " + e.message,
      kind: "bad",
    };
    render();
  }
}
async function refreshAccess() {
  const id = state.current,
    key = state.signerId;
  state.access = null;
  if (!id || !key || !state.vault) return;
  const snapshot = await api.access(id, key);
  if (id === state.current && key === state.signerId && state.vault)
    state.access = snapshot;
}
async function reload({ discard = false } = {}) {
  const key = draftKey();
  if (discard) {
    drafts.clear(key);
    dirty.delete(key);
    bases.delete(key);
  } else capture();
  const identity = state.current,
    generation = ++ticket;
  const fresh = await api.identity(identity);
  if (generation !== ticket || identity !== state.current) return;
  state.data = fresh;
  state.events = null;
  if (
    state.projectId &&
    state.projectId !== "all" &&
    !state.data.projects.some((p) => p.id === state.projectId)
  )
    state.projectId = "all";
  await refreshAccess().catch((e) => {
    state.message = { text: e.message, kind: "bad" };
  });
  render();
}
function go(view, scope = state.projectId) {
  if (state.busy) return;
  capture();
  state.view = view;
  state.projectId = scope;
  history.pushState(null, "", url());
  render();
  content()?.focus();
}
function say(text, kind = "info") {
  state.message = text ? { text, kind } : null;
  const box = document.getElementById("msg");
  if (box) box.replaceChildren(...(text ? [notice(text, kind)] : []));
}
async function unlock() {
  if (state.busy) return;
  capture();
  try {
    const vault = await unlockDialog();
    if (!vault) return;
    state.vault = vault;
    rememberVault(vault);
    if (!vault.get(state.signerId))
      state.signerId = vault.ofKind("signing")[0]?.id || null;
    state.authId = vault.ofKind("auth")[0]?.id || null;
    if (!state.data) {
      const ref = vault.keys.find((k) => k.identity)?.identity;
      if (ref) return select(ref);
    }
    await refreshAccess();
    render();
  } catch (e) {
    say(e.message, "bad");
  }
}
function lock() {
  if (state.busy) return;
  capture();
  lockVault();
  state.vault = null;
  state.signerId = null;
  state.access = null;
  render();
}
async function endSession() {
  if (state.busy) return;
  try {
    // Explicit session management, never part of ordinary reading.
    if (!state.me) {
      const session = await api.me();
      api.setCsrf(session.csrf);
    }
    await api.logout();
    state.me = null;
    say("Sesja przesyłania zakończona. Klucze pozostają niezależne.");
  } catch (e) {
    if (e.status === 401) {
      state.me = null;
      api.setCsrf(null);
      say("Nie ma aktywnej sesji przesyłania.");
    } else say(e.message, "bad");
  }
}
function button(text, fn, cls = "") {
  return h(
    "button",
    {
      type: "button",
      class: "btn " + cls,
      disabled: state.busy,
      onclick: () => Promise.resolve(fn()).catch((e) => say(e.message, "bad")),
    },
    text,
  );
}
function nav() {
  return h(
    "nav",
    { class: "studio-nav", "aria-label": "Sekcje Pracowni" },
    Object.entries(views).map(([v, name]) =>
      h(
        "a",
        {
          href: url(v),
          "aria-current": state.view === v ? "page" : null,
          onclick: (e) => {
            e.preventDefault();
            go(v);
          },
        },
        name,
      ),
    ),
  );
}
function render() {
  const d = state.data;
  const available = new Map(state.directory.map((i) => [i.id, i]));
  if (d) available.set(d.id, d);
  for (const k of state.vault?.keys || [])
    if (k.identity && !available.has(k.identity))
      available.set(k.identity, { id: k.identity });
  const identitySelect = h(
    "select",
    {
      id: "identity",
      disabled: state.busy,
      onchange: (e) =>
        select(e.target.value).catch((err) => say(err.message, "bad")),
    },
    available.size
      ? [...available.values()].map((i) =>
          h(
            "option",
            { value: i.id, selected: i.id === state.current },
            label(i),
          ),
        )
      : h("option", { value: "" }, "Brak tożsamości"),
  );
  const ref = h("input", {
    id: "studio-ref",
    placeholder: "@uchwyt lub pełne ID",
    autocomplete: "off",
  });
  const browse = h(
    "form",
    {
      class: "stack",
      onsubmit: (e) => {
        e.preventDefault();
        select(ref.value.trim().replace(/^@/, "")).catch((err) =>
          say(err.message, "bad"),
        );
      },
    },
    field("Otwórz przez adres", ref),
    h(
      "button",
      { type: "submit", class: "btn", disabled: state.busy },
      "Otwórz",
    ),
  );
  const sidebar = h(
    "aside",
    { class: "studio-sidebar" },
    field("Przeglądana tożsamość", identitySelect),
    h("details", {}, h("summary", {}, "Tożsamość spoza katalogu"), browse),
    h("div", { class: "desktop-studio-nav" }, nav()),
    h(
      "details",
      { class: "mobile-studio-nav" },
      h("summary", {}, "Sekcje: " + views[state.view]),
      nav(),
    ),
    h(
      "p",
      { class: "hint" },
      "Wybór tożsamości nie zmienia klucza. Odczyt jest otwarty.",
    ),
  );
  const scope = h(
    "select",
    {
      id: "project-filter",
      disabled: state.busy,
      onchange: (e) => go(state.view, e.target.value || null),
    },
    h(
      "option",
      { value: "all", selected: state.projectId === "all" },
      "Cała tożsamość",
    ),
    h(
      "option",
      { value: "", selected: state.projectId === null },
      "Przestrzeń główna (bez projektu)",
    ),
    (d?.projects || []).map((p) =>
      h(
        "option",
        { value: p.id, selected: p.id === state.projectId },
        p.meta.title || p.slug,
      ),
    ),
  );
  const signer =
    state.vault &&
    h(
      "select",
      {
        id: "signer",
        disabled: state.busy,
        onchange: async (e) => {
          capture();
          state.signerId = e.target.value;
          try {
            await refreshAccess();
            render();
          } catch (err) {
            say(err.message, "bad");
          }
        },
      },
      h(
        "option",
        { value: "", selected: !state.signerId },
        "Wybierz klucz sygnowania",
      ),
      state.vault
        .ofKind("signing")
        .map((k) =>
          h(
            "option",
            { value: k.id, selected: k.id === state.signerId },
            (k.label || "Klucz") + " · " + short(k.id),
          ),
        ),
    );
  const active =
    Boolean(state.vault?.get(state.signerId)) &&
    (state.signerId === d?.founding_key ||
      (state.access?.signing_key &&
        (state.access.founder || state.access.grants.length > 0)));
  const accessText = !state.vault
    ? "Tryb odczytu. Do przeglądania nie potrzebujesz kluczy ani sesji."
    : active
      ? "Klucz odblokowany. Dostępne działania zależą od jego uprawnień."
      : "Klucz odblokowany, brak uprawnień w tej tożsamości. Odczyt pozostaje dostępny.";
  mount(
    root,
    h(
      "div",
      { class: "workspace" },
      sidebar,
      h(
        "div",
        { class: "studio-main" },
        h(
          "div",
          { class: "studio-context" },
          h(
            "div",
            {},
            h(
              "p",
              { class: "eyebrow" },
              d?.kind === "collective" ? "Kolektyw" : "Tożsamość",
            ),
            h(
              "div",
              { class: "studio-owner" },
              d?.avatar_url
                ? h("img", {
                    class: "avatar studio-avatar avatar-photo",
                    src: d.avatar_url,
                    alt: "",
                    onerror: (e) => {
                      e.target.hidden = true;
                    },
                  })
                : h(
                    "span",
                    { class: "avatar studio-avatar", "aria-hidden": "true" },
                    (
                      label(d).replace(/^@/, "").trim().slice(0, 1) || "O"
                    ).toUpperCase(),
                  ),
              h("strong", {}, label(d)),
            ),
          ),
          d && h("a", { class: "btn", href: publicUrl() }, "Profil publiczny"),
          state.vault
            ? button("Zablokuj klucze", lock)
            : button("Odblokuj klucze", unlock, "primary"),
        ),
        h(
          "div",
          { class: "studio-controls" },
          d && field("Zakres zasobów", scope),
          signer && field("Aktywny klucz", signer),
        ),
        ["profile", "keys"].includes(state.view) &&
          state.projectId !== "all" &&
          h(
            "p",
            { class: "hint" },
            "Ta sekcja dotyczy tożsamości, nie projektu. Zakres zasobów zostaje zapamiętany.",
          ),
        notice(accessText),
        state.directoryError &&
          notice(
            "Katalog jest chwilowo niedostępny: " +
              state.directoryError +
              ". Możesz otworzyć tożsamość po uchwycie lub ID.",
            "warn",
          ),
        d?.visibility === "unlisted" &&
          notice(
            "Nieindeksowana: poza katalogiem, ale wszystkie dane są odczytywalne przez adres.",
          ),
        d?.integrity === "error" &&
          notice(
            "Nie udało się zweryfikować dziennika. Zapis jest wstrzymany; możesz przeglądać dane i historię.",
            "bad",
          ),
        h(
          "div",
          { id: "msg", "aria-live": "polite" },
          state.message && notice(state.message.text, state.message.kind),
        ),
        pendingPanel(),
        h(
          "section",
          { id: "studio-content", tabindex: "-1" },
          h("div", { class: "page-head" }, h("h1", {}, views[state.view])),
          d
            ? viewContent(d)
            : h(
                "div",
                { class: "feed-empty" },
                h(
                  "h2",
                  {},
                  state.loading ? "Odczyt tożsamości…" : "Wybierz przestrzeń",
                ),
                h(
                  "p",
                  { role: "status" },
                  state.loading
                    ? "Pobieramy dane publiczne. Jeśli serwer nie odpowie, zobaczysz błąd i możesz spróbować ponownie."
                    : "Otwórz tożsamość przez adres albo utwórz pierwszą.",
                ),
                state.message?.kind === "bad" &&
                  button("Spróbuj ponownie", () => select(parseUrl(), false)),
                h("a", { class: "btn", href: "/join" }, "Nowa tożsamość"),
              ),
        ),
      ),
    ),
  );
  drafts.restore(draftKey(), content());
  if (state.view === "history" && d && !state.events) loadHistory();
}
function viewContent(d) {
  const editable = Boolean(state.vault);
  switch (state.view) {
    case "profile":
      return h(
        "div",
        { class: "stack" },
        editable && avatarSection(d),
        editable
          ? profileSection(d)
          : h(
              "section",
              { class: "panel" },
              h("h2", {}, label(d)),
              d.avatar_url &&
                h("img", {
                  class: "avatar avatar-large avatar-photo",
                  src: d.avatar_url,
                  alt: "Zdjęcie profilowe",
                }),
              h("p", {}, d.profile.bio || "Brak opisu."),
              h("p", {}, d.profile.location || ""),
              h("p", {}, d.profile.website || ""),
            ),
        editable
          ? visibilitySection(d)
          : notice(
              "Obecność w katalogu: " +
                (d.visibility === "public" ? "widoczna" : "nieindeksowana"),
            ),
      );
    case "projects":
      return projectsSection(d, {
        editable,
        selected: state.projectId,
        onSelect: (id) => go("projects", id),
        act,
        can,
      });
    case "resources":
      return resourcesSection(d, {
        editable,
        selected: state.projectId,
        act,
        publishFile,
        say,
        can,
      });
    case "collaboration":
      return grantsSection(d, {
        editable,
        access: state.access,
        selected: state.projectId === "all" ? null : state.projectId,
        keys: state.vault?.keys || [],
        signerId: state.signerId,
        act,
        say,
        can,
      });
    case "keys":
      return h(
        "div",
        { class: "stack" },
        editable ? keysSection(d) : readKeys(d),
        localKeys(),
        editable && backupSection(),
      );
    case "history":
      return historyView(d);
    default:
      return overview(d);
  }
}
function overview(d) {
  const project = d.projects.find((p) => p.id === state.projectId);
  const files = d.resources.filter(
    (r) =>
      state.projectId === "all" || (r.project_id || null) === state.projectId,
  );
  return h(
    "div",
    { class: "stack" },
    h(
      "section",
      { class: "panel" },
      h("p", { class: "eyebrow" }, project ? "Projekt" : "Przestrzeń"),
      h("h2", {}, project?.meta.title || label(d)),
      h(
        "p",
        {},
        project?.meta.description || d.profile.bio || "Nie ma jeszcze opisu.",
      ),
      h(
        "div",
        { class: "quick-summary" },
        h("span", {}, d.projects.length, " projektów"),
        h("span", {}, files.length, " plików"),
        h("span", {}, "Dziennik #", d.head.seq),
      ),
      h(
        "div",
        { class: "actions" },
        button("Przeglądaj zasoby", () => go("resources")),
        button("Sprawdź dostęp", () => go("collaboration")),
        h(
          "a",
          { class: "btn", href: "/join?kind=collective" },
          "Nowy kolektyw",
        ),
      ),
    ),
    h(
      "div",
      { class: "project-grid" },
      d.projects.map((p) =>
        h(
          "a",
          {
            class: "project-card",
            href: url("resources", p.id),
            onclick: (e) => {
              e.preventDefault();
              go("resources", p.id);
            },
          },
          h("p", { class: "eyebrow" }, "Projekt"),
          h("h2", {}, p.meta.title || p.slug),
          h("p", {}, p.meta.description || "Brak opisu."),
          h(
            "span",
            { class: "hint" },
            d.resources.filter((r) => r.project_id === p.id).length,
            " plików",
          ),
        ),
      ),
    ),
    !d.projects.length &&
      h(
        "div",
        { class: "feed-empty" },
        h("h2", {}, "Nie ma jeszcze projektów"),
        button("Przejdź do projektów", () => go("projects")),
      ),
  );
}
function readKeys(d) {
  return h(
    "section",
    { class: "panel" },
    h("h2", {}, "Klucze publiczne"),
    h("p", {}, "Założycielski: ", copyButton(d.founding_key)),
    h("h3", {}, "Sygnowanie"),
    h(
      "ul",
      { class: "res-list" },
      d.members.map((k) => h("li", {}, copyButton(k.key_id), " · ", k.status)),
    ),
    h("h3", {}, "Autoryzacja przesyłania"),
    h(
      "ul",
      { class: "res-list" },
      d.auth_keys.map((k) =>
        h("li", {}, copyButton(k.key_id), " · ", k.status),
      ),
    ),
  );
}
function localKeys() {
  return h(
    "section",
    { class: "panel local-vault", "data-local-only": "true" },
    h("h2", {}, "Lokalny skarbiec i sesja"),
    h(
      "p",
      {},
      "Klucze prywatne są lokalne. Nie należą do publicznych danych platformy.",
    ),
    state.vault &&
      field(
        "Klucz autoryzacji uploadu",
        h(
          "select",
          {
            id: "upload-auth",
            onchange: (e) => {
              state.authId = e.target.value;
            },
          },
          h("option", { value: "" }, "Wybierz klucz"),
          state.vault
            .ofKind("auth")
            .map((k) =>
              h(
                "option",
                { value: k.id, selected: k.id === state.authId },
                k.label || short(k.id),
              ),
            ),
        ),
      ),
    h(
      "p",
      { class: "hint" },
      state.me
        ? "Sesja przesyłania aktywna w tej karcie."
        : "Nie sprawdzamy sesji przy odczycie. Zostanie sprawdzona dopiero przed uploadem.",
    ),
    button("Zakończ sesję przesyłania", endSession),
    h(
      "a",
      { class: "btn", href: "/login?restore=1" },
      "Przywróć kopię skarbca",
    ),
  );
}
async function loadHistory() {
  const id = state.current;
  try {
    const result = await api.api(
      "GET",
      `/api/identities/${encodeURIComponent(id)}/events`,
    );
    if (id !== state.current) return;
    state.events = result.events;
    if (state.view === "history") render();
  } catch (e) {
    say(e.message, "bad");
  }
}
function historyView(d) {
  return h(
    "section",
    { class: "panel" },
    h(
      "p",
      { class: "hint" },
      "Ocena serwera: " +
        (d.integrity === "ok"
          ? "podpisy i łańcuch zweryfikowane"
          : "niepotwierdzona integralność") +
        ". Brak bajtów historycznej treści nie oznacza uszkodzenia podpisu.",
    ),
    state.events
      ? h(
          "ol",
          { class: "history-list" },
          [...state.events].reverse().map((envelope) => {
            try {
              const e = JSON.parse(dec.decode(unb64u(envelope.payload)));
              return h(
                "li",
                {},
                h("h3", {}, "#" + e.seq + " · " + actionLabel(e.type)),
                h(
                  "p",
                  { class: "hint" },
                  new Date(e.ts * 1000).toLocaleString("pl-PL"),
                  " · klucz ",
                  copyButton(e.signer),
                ),
                h(
                  "details",
                  {},
                  h("summary", {}, "Podpisana operacja"),
                  h("pre", { class: "code" }, JSON.stringify(e, null, 2)),
                ),
              );
            } catch {
              return h("li", {}, notice("Nie można odczytać koperty.", "bad"));
            }
          }),
        )
      : h("p", {}, "Odczyt dziennika…"),
  );
}

function pendingPanel() {
  const p = api.pendingFor(state.current);
  if (!p) return null;
  const info = h("div", { id: "pending-result", "aria-live": "polite" });
  const check = async () => {
    try {
      const found = await api.checkPending(p.identity);
      if (found) {
        if (state.current !== p.identity) return;
        say("Zapis potwierdzony bez nowego podpisu.", "ok");
        await reload({ discard: true });
      } else
        info.replaceChildren(
          notice(
            "Nie znaleziono jeszcze tej próby. To nie dowodzi, że pierwotne żądanie nie dotrze. Możesz ponowić dokładnie tę samą kopertę.",
            "warn",
          ),
        );
    } catch (e) {
      info.replaceChildren(notice(e.message, "bad"));
    }
  };
  return h(
    "section",
    { class: "panel pending-write" },
    h("h2", {}, "Wynik zapisu nie jest jeszcze znany"),
    h(
      "p",
      {},
      "Nie podpisuj kolejnej wersji. Sprawdź zdarzenie ",
      copyButton(p.id),
    ),
    info,
    button("Sprawdź zapis w dzienniku", check),
    button("Ponów tę samą kopertę", async () => {
      if (
        !(await ask(
          "Ponowić przesłanie?",
          "Wyślemy identyczne ID, treść i podpis. Nie powstanie nowy podpis.",
        ))
      )
        return;
      try {
        await api.retryPending(p.identity);
        if (state.current !== p.identity) return;
        say("Zapis potwierdzony.", "ok");
        await reload({ discard: true });
      } catch (e) {
        info.replaceChildren(notice(e.message, "bad"));
      }
    }),
    h(
      "p",
      { class: "hint" },
      "Próba jest zachowana tylko w pamięci karty. Nie odświeżaj jej do rozstrzygnięcia wyniku.",
    ),
  );
}
async function act(type, body, { after, prepare } = {}) {
  if (state.busy) return false;
  if (api.pendingFor(state.current)) {
    say("Najpierw sprawdź wynik poprzedniej próby.", "warn");
    return false;
  }
  const signer = state.vault?.get(state.signerId);
  if (!signer) {
    say("Odblokuj i wybierz klucz. Ta zmiana nie została podpisana.", "warn");
    return false;
  }
  if (state.data.integrity === "error") {
    say("Zapis wstrzymany z powodu integralności dziennika.", "bad");
    return false;
  }
  const id = state.current,
    key = draftKey(),
    head = structuredClone(bases.get(key) || state.data.head);
  const confirmedBody = structuredClone(body); // UI inputs can no longer change the approved bytes.
  state.busy = true;
  root.setAttribute("aria-busy", "true");
  say(null);
  try {
    if (
      !(await confirmSign({
        type,
        body: confirmedBody,
        signer,
        identity: id,
        context: { data: state.data },
      }))
    )
      return false;
    say(
      prepare
        ? "Przesyłanie bajtów po potwierdzeniu…"
        : "Podpisywanie zmiany lokalnie…",
    );
    if (prepare) await prepare();
    say("Wysyłanie podpisanej operacji…");
    const result = await api.publish({
      signer,
      identity: id,
      type,
      body: confirmedBody,
      head,
    });
    drafts.clear(key);
    dirty.delete(key);
    bases.delete(key);
    if (type === "project.create") state.projectId = result.id;
    if (after) await after();
    state.message = {
      text: "Zdarzenie przyjęte i podpis potwierdzony przez serwer.",
      kind: "ok",
    };
    state.busy = false;
    await reload({ discard: true });
    history.replaceState(null, "", url());
    return true;
  } catch (e) {
    if (e.code === "unknown_outcome") {
      capture();
      state.busy = false;
      render();
    } else {
      if (e.code === "blob_not_found") uploaded.delete(confirmedBody.hash);
      say(e.message, "bad");
      if (["bad_seq", "bad_prev"].includes(e.code)) {
        const box = document.getElementById("msg");
        box.append(
          h(
            "button",
            {
              type: "button",
              class: "btn",
              onclick: async () => {
                if (state.busy) return;
                if (
                  !(await ask(
                    "Odczytać nowszy stan?",
                    "Szkic zostanie zachowany. Porównaj go z aktualnymi danymi; kolejny zapis wymaga ponownego potwierdzenia.",
                    "Odczytaj bez podpisywania",
                  ))
                )
                  return;
                try {
                  capture();
                  await reload();
                  bases.set(key, structuredClone(state.data.head));
                  say(
                    "Odczytano nowszy stan. Sprawdź wartości i ponownie otwórz podsumowanie; niczego nie podpisano.",
                    "warn",
                  );
                } catch (err) {
                  say(err.message, "bad");
                }
              },
            },
            "Odczytaj nowszy stan, zachowaj szkic",
          ),
        );
      }
    }
    return false;
  } finally {
    state.busy = false;
    root.setAttribute("aria-busy", "false");
  }
}
async function uploadSession() {
  let session = null;
  try {
    session = await api.me();
  } catch (e) {
    if (e.status !== 401) throw e;
  }
  if (!session || (state.authId && session.key !== state.authId)) {
    const auth = state.vault?.get(state.authId);
    if (!auth)
      throw new Error("Wybierz klucz autoryzacji uploadu w sekcji Klucze.");
    session = await api.login(auth, (message, priv) =>
      sign("login", enc.encode(message), priv),
    );
  }
  state.me = session;
  api.setCsrf(session.csrf);
}
async function publishFile(file, fields) {
  if (state.busy) return false;
  try {
    validateFile(file, fields.path, fields.media_type);
    const source = fileResource(state.current, fields.path, fields.project_id);
    if (!can("resource.put", source))
      throw new Error("Wybrany klucz nie może publikować w tym miejscu.");
    const exists = state.data.resources.find(
      (r) =>
        r.path === fields.path &&
        (r.project_id || null) === (fields.project_id || null),
    );
    if (exists) {
      if (
        !(await ask(
          "Zastąpić istniejący plik?",
          fields.path +
            " już istnieje. Zachowasz jego ID; poprzednia wersja zostanie zastąpiona.",
          "Przygotuj zastąpienie",
        ))
      )
        return false;
      fields = { ...fields, id: exists.id };
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    const hash = Array.from(await sha256(bytes), (n) =>
      n.toString(16).padStart(2, "0"),
    ).join("");
    return await act(
      "resource.put",
      { ...fields, hash, size: bytes.length },
      {
        prepare: async () => {
          if (uploaded.has(hash)) return;
          await uploadSession();
          const stored = await api.uploadBlob(bytes, fields.media_type);
          if (
            stored.hash !== hash ||
            stored.size !== bytes.length ||
            stored.media_type !== fields.media_type
          )
            throw new Error(
              "Metadane uploadu nie odpowiadają zatwierdzonemu plikowi.",
            );
          uploaded.add(hash);
        },
      },
    );
  } catch (e) {
    say(e.message, "bad");
    return false;
  }
}

// profil

function profileSection(d) {
  const inputs = Object.fromEntries(
    PROFILE_FIELDS.map(([name, , kind]) => [
      name,
      kind === "textarea"
        ? h(
            "textarea",
            { id: "p-" + name, rows: 5, maxlength: 2000 },
            d.profile[name] || "",
          )
        : h("input", {
            id: "p-" + name,
            value: d.profile[name] || "",
            maxlength: name === "website" ? 200 : 80,
          }),
    ]),
  );

  // Editing a draft is never an authorization decision. Validate the actual
  // changed fields before any signature; the server is authoritative as well.
  const allowedFields = PROFILE_FIELDS.filter(([name]) =>
    can("profile.update", d.id + "/profile/" + name),
  ).map(([name]) => name);
  return h(
    "section",
    { class: "panel", "aria-labelledby": "profile-h" },
    h("h2", { id: "profile-h" }, "Profil"),
    h("p", { class: "hint" }, "ID tożsamości: ", copyButton(d.id)),
    h(
      "p",
      { class: "hint" },
      allowedFields.length === PROFILE_FIELDS.length
        ? "Możesz edytować profil. Każda zmiana wymaga osobnego podpisu."
        : "Możesz przygotować szkic. Zapis wymaga uprawnienia do każdego zmienionego pola; zmiana klucza nie zmienia tożsamości.",
    ),
    h(
      "form",
      {
        class: "stack",
        onsubmit: async (e) => {
          e.preventDefault();
          const fields = {};
          for (const [name] of PROFILE_FIELDS) {
            const value = inputs[name].value.trim();
            const before = d.profile[name] ?? "";
            if (value !== before) fields[name] = value === "" ? null : value;
          }
          if (Object.keys(fields).length === 0) {
            return say("Nic się nie zmieniło.");
          }
          const missing = Object.keys(fields).filter(
            (name) => !can("profile.update", d.id + "/profile/" + name),
          );
          if (missing.length) {
            return say(
              "Ten klucz nie może zmienić pól: " +
                missing
                  .map(
                    (name) =>
                      PROFILE_FIELDS.find((f) => f[0] === name)?.[1] || name,
                  )
                  .join(", ") +
                ". Wybierz uprawniony klucz; szkic pozostaje w formularzu.",
              "warn",
            );
          }
          await act("profile.update", { fields });
        },
      },
      PROFILE_FIELDS.map(([name, label]) =>
        field(
          label,
          inputs[name],
          allowedFields.includes(name)
            ? undefined
            : "Do podpisania tego pola potrzebny jest inny klucz lub grant.",
        ),
      ),
      h(
        "div",
        { class: "actions" },
        h(
          "button",
          { class: "btn primary", type: "submit", id: "save-profile" },
          "Podpisz i zapisz profil",
        ),
      ),
    ),
  );
}

function avatarSection(d) {
  const file = h("input", {
    id: "avatar-file",
    type: "file",
    accept: "image/png,image/jpeg,image/webp",
  });
  const status = h(
    "p",
    { class: "hint", role: "status" },
    "Wybór zdjęcia niczego nie wysyła. Maksymalnie 10 MiB.",
  );
  file.addEventListener("change", () => {
    const selected = file.files?.[0];
    status.textContent = selected
      ? "Przygotowano: " +
        selected.name +
        " (" +
        selected.size +
        " B). Niczego nie wysłano."
      : "Nie wybrano pliku.";
  });
  const authorized = can("resource.put", fileResource(d.id, AVATAR_PATH, null));
  return h(
    "section",
    { class: "panel profile-avatar", "aria-labelledby": "avatar-h" },
    h("h2", { id: "avatar-h" }, "Zdjęcie profilowe"),
    h(
      "div",
      { class: "avatar-editor" },
      d.avatar_url
        ? h("img", {
            class: "avatar avatar-large avatar-photo",
            src: d.avatar_url,
            alt: "Bieżące zdjęcie profilowe",
          })
        : h(
            "span",
            { class: "avatar avatar-large", "aria-hidden": "true" },
            (
              label(d).replace(/^@/, "").trim().slice(0, 1) || "O"
            ).toUpperCase(),
          ),
      h(
        "div",
        {},
        h(
          "p",
          {},
          "Obraz jest zasobem w przestrzeni głównej (images/avatar). Jego aktualizacja zachowuje ID.",
        ),
        h(
          "p",
          { class: "hint" },
          "Publikacja wymaga uprawnienia resource.put dla tej ścieżki; nie wynika automatycznie z prawa do edycji opisu.",
        ),
      ),
    ),
    h(
      "form",
      {
        class: "stack",
        id: "avatar-upload",
        onsubmit: async (e) => {
          e.preventDefault();
          const selected = file.files?.[0];
          if (!selected) return say("Wybierz zdjęcie profilowe.", "warn");
          try {
            const mediaType = avatarMediaType(selected);
            if (!can("resource.put", fileResource(d.id, AVATAR_PATH, null)))
              return say(
                "Ten klucz nie może publikować zdjęcia profilowego. Potrzebne jest resource.put na images/avatar w przestrzeni głównej.",
                "warn",
              );
            await publishFile(selected, {
              path: AVATAR_PATH,
              project_id: null,
              media_type: mediaType,
              meta: {
                title: "Zdjęcie profilowe",
                alt: "Zdjęcie profilowe " + label(d),
              },
            });
          } catch (err) {
            say(err.message, "bad");
          }
        },
      },
      field("Nowe zdjęcie", file),
      status,
      h(
        "button",
        {
          type: "submit",
          class: "btn primary",
          id: "save-avatar",
          disabled: !authorized,
        },
        "Sprawdź i opublikuj zdjęcie",
      ),
      !authorized &&
        notice(
          "Wybrany klucz nie posiada uprawnienia do publikacji zdjęcia. Wybierz klucz z odpowiednim grantem.",
          "warn",
        ),
    ),
  );
}

// Widoczność nie jest częścią profilu: zawsze zmieniamy ją podpisanym zdarzeniem.
function visibilitySection(d) {
  const visibility = h(
    "select",
    { id: "i-visibility" },
    h(
      "option",
      { value: "public", selected: d.visibility === "public" },
      "Publiczna (w katalogu)",
    ),
    h(
      "option",
      { value: "unlisted", selected: d.visibility === "unlisted" },
      "Nieindeksowana (tylko z linku)",
    ),
  );
  return h(
    "section",
    { class: "panel", "aria-labelledby": "visibility-h" },
    h("h2", { id: "visibility-h" }, "Widoczność"),
    h(
      "p",
      { class: "muted" },
      "Nieindeksowana tożsamość nie pojawia się w katalogu ani galerii. Profil, historia, pliki i własna strona nadal są dostępne z bezpośredniego adresu.",
    ),
    h(
      "form",
      {
        class: "stack",
        onsubmit: async (e) => {
          e.preventDefault();
          if (visibility.value === d.visibility)
            return say("Widoczność się nie zmieniła.");
          await act("identity.visibility.set", {
            visibility: visibility.value,
          });
        },
      },
      field("Widoczność profilu", visibility),
      h(
        "div",
        { class: "actions" },
        h(
          "button",
          { class: "btn primary", type: "submit", id: "save-visibility" },
          "Podpisz zmianę widoczności",
        ),
      ),
    ),
  );
}

// klucze

function keysSection(d) {
  const label = h("input", {
    id: "k-label",
    maxlength: 40,
    placeholder: "np. laptop, bot-wydawca",
  });
  const pasted = h("input", {
    id: "k-pasted",
    autocomplete: "off",
    placeholder: "id klucza z innej przeglądarki",
  });
  const authLabel = h("input", {
    id: "ak-label",
    maxlength: 40,
    placeholder: "np. telefon",
  });

  const addDevice = async (e) => {
    e.preventDefault();
    let id = pasted.value.trim();
    let created = null;
    if (!id) {
      created = await generateKey(
        "signing",
        label.value.trim() || "urządzenie",
      );
      id = created.id;
      pasted.value = id;
      state.vault.add(created);
      await state.vault.save();
    }
    const body = { key: id };
    if (label.value.trim()) body.label = label.value.trim();
    await act("key.add", body);
  };

  let stagedAuth = null;
  const addAuth = async (e) => {
    e.preventDefault();
    const created =
      stagedAuth ||
      (await generateKey("auth", authLabel.value.trim() || "upload"));
    stagedAuth = created;
    state.vault.add(created);
    await state.vault.save();
    if (await act("auth_key.add", { key: created.id })) stagedAuth = null;
  };

  const activeAuth = d.auth_keys.filter((k) => k.status === "active").length;

  return h(
    "section",
    { class: "panel", "aria-labelledby": "keys-h" },
    h("h2", { id: "keys-h" }, "Klucze"),
    h(
      "p",
      { class: "section-note" },
      "Klucz założycielski podpisuje i nadaje uprawnienia. Klucze autoryzacji uwierzytelniają wysyłanie plików; odczyt Pracowni jest publiczny. Klucze urządzeń i botów dopisujesz tu, a ich uprawnienia dają granty.",
    ),
    h(
      "dl",
      { class: "facts" },
      h(
        "div",
        {},
        h("dt", {}, "Klucz założycielski"),
        h("dd", {}, copyButton(d.founding_key)),
      ),
    ),
    h("h3", {}, "Klucze logowania"),
    h(
      "ul",
      { class: "res-list" },
      d.auth_keys.map((k) =>
        h(
          "li",
          {},
          h(
            "span",
            { class: "res-main" },
            copyButton(k.key_id),
            " ",
            k.status === "revoked"
              ? h("span", { class: "tag bad" }, "cofnięty")
              : state.vault?.get(k.key_id) &&
                  h("span", { class: "tag" }, "w tej przeglądarce"),
          ),
          k.status === "active" &&
            activeAuth > 1 &&
            h(
              "button",
              {
                class: "btn small",
                type: "button",
                onclick: () => act("auth_key.revoke", { key: k.key_id }),
              },
              "Cofnij",
            ),
        ),
      ),
    ),
    h(
      "form",
      {
        class: "inline",
        onsubmit: (e) => addAuth(e).catch((err) => say(err.message, "bad")),
      },
      field("Nowy klucz logowania (powstaje tu, trafia do skarbca)", authLabel),
      h("button", { class: "btn", type: "submit", id: "add-auth" }, "Dodaj"),
    ),
    h("h3", {}, "Klucze urządzeń i botów"),
    d.members.length === 0
      ? h("p", { class: "muted" }, "Brak dopisanych kluczy.")
      : h(
          "ul",
          { class: "res-list" },
          d.members.map((m) =>
            h(
              "li",
              {},
              h(
                "span",
                { class: "res-main" },
                copyButton(m.key_id),
                " ",
                m.label && h("span", { class: "muted" }, m.label),
                " ",
                m.status === "revoked" &&
                  h("span", { class: "tag bad" }, "cofnięty"),
              ),
              m.status === "active" &&
                h(
                  "button",
                  {
                    class: "btn small",
                    type: "button",
                    onclick: () => act("key.revoke", { key: m.key_id }),
                  },
                  "Cofnij",
                ),
            ),
          ),
        ),
    h(
      "form",
      {
        class: "stack",
        onsubmit: (e) => addDevice(e).catch((err) => say(err.message, "bad")),
      },
      h(
        "div",
        { class: "grid2" },
        field("Etykieta", label),
        field(
          "Albo wklej id istniejącego klucza",
          pasted,
          "Puste = wygeneruj nowy klucz w tej przeglądarce.",
        ),
      ),
      h(
        "div",
        { class: "actions" },
        h(
          "button",
          { class: "btn", type: "submit", id: "add-device" },
          "Dopisz klucz",
        ),
      ),
    ),
  );
}

// kopie zapasowe

function backupSection() {
  return h(
    "section",
    { class: "panel", "aria-labelledby": "backup-h" },
    h("h2", { id: "backup-h" }, "Kopie zapasowe i eksport"),
    h(
      "p",
      { class: "section-note" },
      "Skarbiec jest szyfrowany Twoim hasłem. Kopia zapasowa to ten sam zaszyfrowany plik: bez niego i bez hasła klucze przepadną z przeglądarką.",
    ),
    h(
      "div",
      { class: "actions" },
      h(
        "button",
        {
          class: "btn",
          type: "button",
          id: "backup",
          onclick: async () =>
            download(
              `oktavarium-kopia-${new Date().toISOString().slice(0, 10)}.json`,
              await state.vault.backupFile(),
            ),
        },
        "Pobierz zaszyfrowaną kopię",
      ),
      h(
        "details",
        { class: "danger" },
        h("summary", {}, "Eksport klucza do CLI (jawny plik)"),
        h(
          "p",
          { class: "muted" },
          "Plik zawiera klucz prywatny bez szyfrowania, w formacie `mix oktavarium.key.gen`. Kto go ma, może podpisywać jako ten klucz.",
        ),
        state.vault.keys.map((k) =>
          h(
            "button",
            {
              class: "btn small",
              type: "button",
              onclick: async () =>
                (await ask(
                  "Eksport jawnego klucza",
                  "Ten plik nie jest szyfrowany. Nie udostępniaj go innym.",
                  "Eksportuj",
                )) &&
                download(
                  `${k.kind}-${short(k.id).replace("…", "-")}.key`,
                  await cliKeyfile(k),
                ),
            },
            `${k.kind} · ${short(k.id)}`,
          ),
        ),
      ),
    ),
  );
}

if (root?.dataset.page === "studio") start();
