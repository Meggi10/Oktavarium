import { failure } from "../lib/failure.js";
import { sign, sha256 } from "../lib/crypto.js";
import { short, enc } from "../lib/bytes.js";
import { localVault, rememberVault, lockVault } from "../lib/local-state.js";
import { unlockDialog } from "../lib/vault-ui.js";
import { Drafts } from "../lib/drafts.js";
import * as api from "../lib/api.js";
import { h, mount, field, notice, confirmSign, ask } from "../lib/ui.js";
import { permits, fileResource } from "../lib/permissions.js";
import { copyButton } from "../lib/copy-id.js";
import { projectsSection } from "./studio-projects.js";
import { resourcesSection, validateFile } from "./studio-resources.js";
import { grantsSection } from "./studio-grants.js";
import { createProfileSections } from "./studio-profile.js";
import { createKeySections } from "./studio-keys.js";
import { createReadSections } from "./studio-read.js";
const root = document.getElementById("app");
const views = {
  overview: "Przegl\u0105d",
  profile: "Profil",
  projects: "Projekty",
  resources: "Zasoby",
  collaboration: "Wsp\xF3\u0142praca",
  keys: "Klucze",
  history: "Historia",
};
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
  dirty = /* @__PURE__ */ new Set(),
  bases = /* @__PURE__ */ new Map();
const uploaded = /* @__PURE__ */ new Set();
let startPromise = null,
  ticket = 0;
const draftKey = () => [state.current, state.view, state.projectId].join(":");
const content = () => document.getElementById("studio-content");
function capture() {
  const target = content();
  if (target && dirty.has(draftKey())) drafts.capture(draftKey(), target);
}
const can = (action, resource) =>
  state.data?.integrity !== "error" &&
  Boolean(state.vault?.get(state.signerId)) &&
  (state.signerId === state.data?.founding_key ||
    permits(state.access, action, resource));
const label = (d) =>
  d?.profile?.display_name ||
  d?.display_name ||
  (d?.handle
    ? "@" + d.handle
    : d?.id
      ? short(d.id)
      : "Wybierz to\u017Csamo\u015B\u0107");
const { profileSection, avatarSection, visibilitySection } =
  createProfileSections({ can, act, publishFile, say, label });
const { keysSection, backupSection } = createKeySections({ state, act, say });
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
  "/i/" + encodeURIComponent(state.data?.handle || state.current || "");
const { overview, readKeys, localKeys, loadHistory, historyView } =
  createReadSections({
    state,
    label,
    go,
    url,
    button,
    endSession,
    say,
    render,
  });
function parseUrl() {
  const p = new URLSearchParams(location.search);
  const view = p.get("view");
  state.view = view && Object.hasOwn(views, view) ? view : "overview";
  state.projectId =
    p.get("project") || (p.get("scope") === "root" ? null : "all");
  return p.get("ref") || state.directory[0]?.id || null;
}
function start() {
  if (startPromise) return startPromise;
  document.title = "Pracownia | Oktavarium";
  document.body.dataset.workspace = "true";
  root.classList.add("studio-app");
  state.vault = localVault();
  state.signerId = state.vault?.ofKind("signing")[0]?.id || null;
  state.authId = state.vault?.ofKind("auth")[0]?.id || null;
  const requestedRef = parseUrl();
  render();
  window.addEventListener("popstate", onPop);
  window.addEventListener("beforeunload", (e) => {
    if (dirty.size || api.hasPending()) {
      e.preventDefault();
      e.returnValue = "";
    }
  });
  root.addEventListener("input", (e) => {
    const target = e.target;
    if (
      !target.closest("#studio-content form") ||
      target.type === "password" ||
      target.closest("[data-local-only]")
    )
      return;
    const key = draftKey();
    dirty.add(key);
    if (!bases.has(key) && state.data?.head)
      bases.set(key, structuredClone(state.data.head));
  });
  startPromise = (async () => {
    const catalogue = (async () => {
      try {
        const entries = await api.identities();
        if (!Array.isArray(entries))
          throw new Error("Nieprawid\u0142owa odpowied\u017A katalogu.");
        state.directory = entries;
        state.directoryError = null;
        if (!requestedRef && ticket === 0 && !state.current && entries.length)
          await select(entries[0].id, false);
        else {
          capture();
          render();
        }
      } catch (e) {
        state.directoryError = failure(e).message;
        capture();
        render();
      }
    })();
    if (requestedRef) await select(requestedRef, false);
    else await catalogue;
  })().catch((e) => {
    state.loading = false;
    state.message = {
      text:
        "Nie uda\u0142o si\u0119 uruchomi\u0107 Pracowni: " +
        failure(e).message,
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
    state.loading = false;
    render();
    await refreshAccess().catch((e) => {
      state.message = {
        text:
          "Nie mo\u017Cna odczyta\u0107 uprawnie\u0144: " + failure(e).message,
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
      text:
        "Nie uda\u0142o si\u0119 otworzy\u0107 to\u017Csamo\u015Bci: " +
        failure(e).message,
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
  if (!identity) return;
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
    state.message = { text: failure(e).message, kind: "bad" };
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
    say(failure(e).message, "bad");
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
    if (!state.me) {
      const session = await api.me();
      api.setCsrf(session.csrf);
    }
    await api.logout();
    state.me = null;
    say(
      "Sesja przesy\u0142ania zako\u0144czona. Klucze pozostaj\u0105 niezale\u017Cne.",
    );
  } catch (e) {
    if (failure(e).status === 401) {
      state.me = null;
      api.setCsrf(null);
      say("Nie ma aktywnej sesji przesy\u0142ania.");
    } else say(failure(e).message, "bad");
  }
}
function button(text, fn, cls = "") {
  return h(
    "button",
    {
      type: "button",
      class: "btn " + cls,
      disabled: state.busy,
      onclick: () =>
        Promise.resolve(fn()).catch((e) => say(failure(e).message, "bad")),
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
        select(e.target.value).catch((err) => say(failure(err).message, "bad")),
    },
    available.size
      ? [...available.values()].map((i) =>
          h(
            "option",
            { value: i.id, selected: i.id === state.current },
            label(i),
          ),
        )
      : h("option", { value: "" }, "Brak to\u017Csamo\u015Bci"),
  );
  const ref = h("input", {
    id: "studio-ref",
    placeholder: "@uchwyt lub pe\u0142ne ID",
    autocomplete: "off",
  });
  const browse = h(
    "form",
    {
      class: "stack",
      onsubmit: (e) => {
        e.preventDefault();
        select(ref.value.trim().replace(/^@/, "")).catch((err) =>
          say(failure(err).message, "bad"),
        );
      },
    },
    field("Otw\xF3rz przez adres", ref),
    h(
      "button",
      { type: "submit", class: "btn", disabled: state.busy },
      "Otw\xF3rz",
    ),
  );
  const sidebar = h(
    "aside",
    { class: "studio-sidebar" },
    field("Przegl\u0105dana to\u017Csamo\u015B\u0107", identitySelect),
    h(
      "details",
      {},
      h("summary", {}, "To\u017Csamo\u015B\u0107 spoza katalogu"),
      browse,
    ),
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
      "Wyb\xF3r to\u017Csamo\u015Bci nie zmienia klucza. Odczyt jest otwarty.",
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
      "Ca\u0142a to\u017Csamo\u015B\u0107",
    ),
    h(
      "option",
      { value: "", selected: state.projectId === null },
      "Przestrze\u0144 g\u0142\xF3wna (bez projektu)",
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
            say(failure(err).message, "bad");
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
            (k.label || "Klucz") + " \xB7 " + short(k.id),
          ),
        ),
    );
  const active =
    Boolean(state.vault?.get(state.signerId)) &&
    (state.signerId === d?.founding_key ||
      (state.access?.signing_key &&
        (state.access.founder || state.access.grants.length > 0)));
  const accessText = !state.vault
    ? "Tryb odczytu. Do przegl\u0105dania nie potrzebujesz kluczy ani sesji."
    : active
      ? "Klucz odblokowany. Dost\u0119pne dzia\u0142ania zale\u017C\u0105 od jego uprawnie\u0144."
      : "Klucz odblokowany, brak uprawnie\u0144 w tej to\u017Csamo\u015Bci. Odczyt pozostaje dost\u0119pny.";
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
              d?.kind === "collective"
                ? "Kolektyw"
                : "To\u017Csamo\u015B\u0107",
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
          d && field("Zakres zasob\xF3w", scope),
          signer && field("Aktywny klucz", signer),
        ),
        ["profile", "keys"].includes(state.view) &&
          state.projectId !== "all" &&
          h(
            "p",
            { class: "hint" },
            "Ta sekcja dotyczy to\u017Csamo\u015Bci, nie projektu. Zakres zasob\xF3w zostaje zapami\u0119tany.",
          ),
        notice(accessText),
        state.directoryError &&
          notice(
            "Katalog jest chwilowo niedost\u0119pny: " +
              state.directoryError +
              ". Mo\u017Cesz otworzy\u0107 to\u017Csamo\u015B\u0107 po uchwycie lub ID.",
            "warn",
          ),
        d?.visibility === "unlisted" &&
          notice(
            "Nieindeksowana: poza katalogiem, ale wszystkie dane s\u0105 odczytywalne przez adres.",
          ),
        d?.integrity === "error" &&
          notice(
            "Nie uda\u0142o si\u0119 zweryfikowa\u0107 dziennika. Zapis jest wstrzymany; mo\u017Cesz przegl\u0105da\u0107 dane i histori\u0119.",
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
                  state.loading
                    ? "Odczyt to\u017Csamo\u015Bci\u2026"
                    : "Wybierz przestrze\u0144",
                ),
                h(
                  "p",
                  { role: "status" },
                  state.loading
                    ? "Pobieramy dane publiczne. Je\u015Bli serwer nie odpowie, zobaczysz b\u0142\u0105d i mo\u017Cesz spr\xF3bowa\u0107 ponownie."
                    : "Otw\xF3rz to\u017Csamo\u015B\u0107 przez adres albo utw\xF3rz pierwsz\u0105.",
                ),
                state.message?.kind === "bad" &&
                  button("Spr\xF3buj ponownie", () =>
                    select(parseUrl(), false),
                  ),
                h(
                  "a",
                  { class: "btn", href: "/join" },
                  "Nowa to\u017Csamo\u015B\u0107",
                ),
              ),
        ),
      ),
    ),
  );
  const target = content();
  if (target) drafts.restore(draftKey(), target);
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
                  alt: "Zdj\u0119cie profilowe",
                }),
              h("p", {}, d.profile.bio || "Brak opisu."),
              h("p", {}, d.profile.location || ""),
              h("p", {}, d.profile.website || ""),
            ),
        editable
          ? visibilitySection(d)
          : notice(
              "Obecno\u015B\u0107 w katalogu: " +
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
            "Nie znaleziono jeszcze tej pr\xF3by. To nie dowodzi, \u017Ce pierwotne \u017C\u0105danie nie dotrze. Mo\u017Cesz ponowi\u0107 dok\u0142adnie t\u0119 sam\u0105 kopert\u0119.",
            "warn",
          ),
        );
    } catch (e) {
      info.replaceChildren(notice(failure(e).message, "bad"));
    }
  };
  return h(
    "section",
    { class: "panel pending-write" },
    h("h2", {}, "Wynik zapisu nie jest jeszcze znany"),
    h(
      "p",
      {},
      "Nie podpisuj kolejnej wersji. Sprawd\u017A zdarzenie ",
      copyButton(p.id),
    ),
    info,
    button("Sprawd\u017A zapis w dzienniku", check),
    button("Pon\xF3w t\u0119 sam\u0105 kopert\u0119", async () => {
      if (
        !(await ask(
          "Ponowi\u0107 przes\u0142anie?",
          "Wy\u015Blemy identyczne ID, tre\u015B\u0107 i podpis. Nie powstanie nowy podpis.",
        ))
      )
        return;
      try {
        await api.retryPending(p.identity);
        if (state.current !== p.identity) return;
        say("Zapis potwierdzony.", "ok");
        await reload({ discard: true });
      } catch (e) {
        info.replaceChildren(notice(failure(e).message, "bad"));
      }
    }),
    h(
      "p",
      { class: "hint" },
      "Pr\xF3ba jest zachowana tylko w pami\u0119ci karty. Nie od\u015Bwie\u017Caj jej do rozstrzygni\u0119cia wyniku.",
    ),
  );
}
async function act(type, body, { after, prepare } = {}) {
  if (state.busy) return false;
  if (!state.current || !state.data) {
    say("Wybierz to\u017Csamo\u015B\u0107 i poczekaj na jej dane.", "warn");
    return false;
  }
  if (api.pendingFor(state.current)) {
    say("Najpierw sprawd\u017A wynik poprzedniej pr\xF3by.", "warn");
    return false;
  }
  const signer = state.vault?.get(state.signerId);
  if (!signer) {
    say(
      "Odblokuj i wybierz klucz. Ta zmiana nie zosta\u0142a podpisana.",
      "warn",
    );
    return false;
  }
  if (state.data.integrity === "error") {
    say("Zapis wstrzymany z powodu integralno\u015Bci dziennika.", "bad");
    return false;
  }
  const id = state.current,
    key = draftKey(),
    head = structuredClone(bases.get(key) || state.data.head);
  const confirmedBody = structuredClone(body);
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
        ? "Przesy\u0142anie bajt\xF3w po potwierdzeniu\u2026"
        : "Podpisywanie zmiany lokalnie\u2026",
    );
    if (prepare) await prepare();
    say("Wysy\u0142anie podpisanej operacji\u2026");
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
      text: "Zdarzenie przyj\u0119te i podpis potwierdzony przez serwer.",
      kind: "ok",
    };
    state.busy = false;
    await reload({ discard: true });
    history.replaceState(null, "", url());
    return true;
  } catch (e) {
    if (failure(e).code === "unknown_outcome") {
      capture();
      state.busy = false;
      render();
    } else {
      if (failure(e).code === "blob_not_found")
        uploaded.delete(confirmedBody.hash);
      say(failure(e).message, "bad");
      if (["bad_seq", "bad_prev"].includes(failure(e).code)) {
        const box = document.getElementById("msg");
        box?.append(
          h(
            "button",
            {
              type: "button",
              class: "btn",
              onclick: async () => {
                if (state.busy) return;
                if (
                  !(await ask(
                    "Odczyta\u0107 nowszy stan?",
                    "Szkic zostanie zachowany. Por\xF3wnaj go z aktualnymi danymi; kolejny zapis wymaga ponownego potwierdzenia.",
                    "Odczytaj bez podpisywania",
                  ))
                )
                  return;
                try {
                  capture();
                  await reload();
                  if (state.data)
                    bases.set(key, structuredClone(state.data.head));
                  say(
                    "Odczytano nowszy stan. Sprawd\u017A warto\u015Bci i ponownie otw\xF3rz podsumowanie; niczego nie podpisano.",
                    "warn",
                  );
                } catch (err) {
                  say(failure(err).message, "bad");
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
    if (failure(e).status !== 401) throw e;
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
  if (!state.current || !state.data) {
    say("Wybierz to\u017Csamo\u015B\u0107 i poczekaj na jej dane.", "warn");
    return false;
  }
  try {
    validateFile(file, fields.path, fields.media_type);
    const source = fileResource(state.current, fields.path, fields.project_id);
    if (!can("resource.put", source))
      throw new Error(
        "Wybrany klucz nie mo\u017Ce publikowa\u0107 w tym miejscu.",
      );
    const exists = state.data.resources.find(
      (r) =>
        r.path === fields.path &&
        (r.project_id || null) === (fields.project_id || null),
    );
    if (exists) {
      if (
        !(await ask(
          "Zast\u0105pi\u0107 istniej\u0105cy plik?",
          fields.path +
            " ju\u017C istnieje. Zachowasz jego ID; poprzednia wersja zostanie zast\u0105piona.",
          "Przygotuj zast\u0105pienie",
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
              "Metadane uploadu nie odpowiadaj\u0105 zatwierdzonemu plikowi.",
            );
          uploaded.add(hash);
        },
      },
    );
  } catch (e) {
    say(failure(e).message, "bad");
    return false;
  }
}
if (root?.dataset.page === "studio") start();
export { start };
