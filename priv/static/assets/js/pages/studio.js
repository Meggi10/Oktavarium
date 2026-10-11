// /studio: edycja profilu, zasoby, uprawnienia i klucze. Każda zmiana to zdarzenie
// podpisane w przeglądarce kluczem ze skarbca, po potwierdzeniu w oknie „Co podpisujesz".
import { generateKey } from "../lib/crypto.js";
import { short } from "../lib/bytes.js";
import { Vault, WrongPassphrase, cliKeyfile } from "../lib/keystore.js";
import * as api from "../lib/api.js";
import { h, mount, field, notice, download, confirmSign } from "../lib/ui.js";

const root = document.getElementById("app");

const state = { me: null, vault: null, current: null, data: null, directory: [], signerId: null, message: null, busy: false };

const PROFILE_FIELDS = [
  ["display_name", "Nazwa", "input"],
  ["bio", "Opis", "textarea"],
  ["location", "Miejsce", "input"],
  ["website", "Strona (https://...)", "input"],
];

const ACTIONS = ["profile.update", "resource.put", "resource.delete", "key.add", "key.revoke", "auth_key.add", "auth_key.revoke", "grant.create", "grant.revoke"];

const EXT_TYPES = {
  html: "text/html", htm: "text/html", css: "text/css", js: "text/javascript", mjs: "text/javascript",
  json: "application/json", txt: "text/plain", svg: "image/svg+xml", png: "image/png", jpg: "image/jpeg",
  jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp", ico: "image/x-icon", woff: "font/woff", woff2: "font/woff2",
  mp3: "audio/mpeg", ogg: "audio/ogg", oga: "audio/ogg", opus: "audio/ogg", wav: "audio/wav", flac: "audio/flac", m4a: "audio/mp4",
};

// start

async function start() {
  // Publiczny odczyt nie wymaga sesji; /api/me jest tylko opcjonalnym
  // kontekstem do przyszłego podpisywania zmian.
  try {
    state.me = await api.me();
    api.setCsrf(state.me.csrf);
  } catch (e) {
    if (e.status !== 401) throw e;
  }

  state.directory = await api.identities();
  const ref = new URLSearchParams(location.search).get("ref");
  const initial = ref || state.me?.identities[0]?.id || state.directory[0]?.id;
  if (initial) {
    try {
      await select(initial);
    } catch (e) {
      state.message = { text: e.status === 404 ? "Nie znaleziono tożsamości." : e.message, kind: "bad" };
      renderReadOnly();
    }
  } else {
    renderReadOnly();
  }
}

function renderUnlock(error) {
  if (!state.me) return location.assign("/login");
  const pass = h("input", { id: "pass", type: "password", autocomplete: "current-password", required: true });
  mount(root,
    h("h1", {}, "Pracownia"),
    h("p", { class: "lead" }, "Żeby podpisywać zmiany, odblokuj skarbiec kluczy z tej przeglądarki."),
    error && notice(error, "bad"),
    h("form", { class: "stack", onsubmit: async (e) => {
        e.preventDefault();
        try {
          state.vault = await Vault.unlock(pass.value);
          await select(state.current || state.me.identities[0]?.id);
        } catch (err) {
          renderUnlock(err instanceof WrongPassphrase ? err.message : err.message);
        }
      } },
      field("Hasło skarbca kluczy", pass),
      h("div", { class: "actions" },
        h("button", { class: "btn primary", type: "submit" }, "Odblokuj"),
        h("button", { class: "btn", type: "button", onclick: renderReadOnly }, "Wróć do przeglądania"),
        h("button", { class: "btn", type: "button", onclick: onLogout }, "Wyloguj"))));
}

async function select(id) {
  state.data = id ? await api.identity(id) : null;
  state.current = state.data?.id || null;
  const mine = state.vault?.keys.filter((k) => k.kind === "signing") || [];
  const preferred = mine.find((k) => k.id === state.data?.founding_key) ||
    mine.find((k) => state.data?.members.some((m) => m.key_id === k.id && m.status === "active"));
  state.signerId = preferred?.id ?? mine[0]?.id ?? null;
  if (state.vault && state.data) render();
  else renderReadOnly();
}

async function reload() {
  state.data = await api.identity(state.current);
  if (state.vault) render();
  else renderReadOnly();
}

async function onLogout() {
  await api.logout().catch(() => {});
  location.assign("/login");
}

// Komunikat jest osobnym elementem: zmiana tekstu nie przebudowuje formularzy,
// więc to, co użytkownik wpisał, nie ginie po błędzie.
function say(text, kind = "info") {
  state.message = text ? { text, kind } : null;
  const box = document.getElementById("msg");
  if (box) box.replaceChildren(...(text ? [notice(text, kind)] : []));
}

// Podgląd publicznych danych: bez skarbca, bez sesji i bez formularzy zapisujących.
function renderReadOnly() {
  const d = state.data;
  const ref = h("input", { id: "studio-ref", name: "ref", autocomplete: "off",
    placeholder: "@uchwyt lub pełne id", value: new URLSearchParams(location.search).get("ref") || "" });

  const browse = h("form", { class: "inline", onsubmit: (e) => {
    e.preventDefault();
    const value = ref.value.trim().replace(/^@/, "");
    if (value) location.assign("/studio?ref=" + encodeURIComponent(value));
  } },
    field("Otwórz tożsamość", ref, "Działa również dla nieindeksowanych, jeśli znasz adres."),
    h("button", { class: "btn", type: "submit" }, "Otwórz"));

  const links = h("ul", { class: "res-list" }, state.directory.map((entry) =>
    h("li", {}, h("a", { href: "/studio?ref=" + encodeURIComponent(entry.handle || entry.id) },
      entry.display_name || (entry.handle ? "@" + entry.handle : short(entry.id))),
    " · ", entry.kind === "collective" ? "kolektyw" : "osoba")));

  mount(root,
    h("h1", {}, "Pracownia"),
    h("p", { class: "lead" }, "Przeglądaj profile, materiały, klucze i uprawnienia bez logowania. Podpis jest potrzebny dopiero do zapisu."),
    h("div", { id: "msg", "aria-live": "polite" }, state.message && notice(state.message.text, state.message.kind)),
    browse,
    h("section", { class: "panel", "aria-labelledby": "directory-h" },
      h("h2", { id: "directory-h" }, "Katalog"),
      state.directory.length ? links : h("p", { class: "muted" }, "Jeszcze nie ma publicznych tożsamości.")),
    d && readOnlyIdentity(d));
}

function readOnlyIdentity(d) {
  const profile = d.profile || {};
  return h("div", { class: "stack" },
    h("section", { class: "panel", "aria-labelledby": "preview-h" },
      h("h2", { id: "preview-h" }, profile.display_name || (d.handle ? "@" + d.handle : short(d.id))),
      h("p", { class: "muted" }, d.kind === "collective" ? "Kolektyw" : "Osoba", " · ",
        d.visibility === "unlisted" ? "Nieindeksowana" : "Publiczna", " · ",
        h("a", { href: "/i/" + encodeURIComponent(d.handle || d.id) }, "Profil publiczny")),
      h("p", {}, profile.bio || "Brak opisu."),
      ...["location", "website"].filter((key) => profile[key]).map((key) =>
        h("p", {}, key === "location" ? "Miejsce: " : "Strona: ", profile[key])),
      h("p", { class: "muted" }, "Id: ", h("code", {}, d.id)),
      d.site_url && h("p", {}, h("a", { href: d.site_url, rel: "noopener" }, "Otwórz stronę tożsamości")),
      h("div", { class: "actions" },
        h("button", { class: "btn primary", type: "button", onclick: () => state.me ? renderUnlock() : location.assign("/login") },
          state.me ? "Odblokuj edycję" : "Zaloguj się, aby edytować"))),
    h("section", { class: "panel", "aria-labelledby": "read-res-h" },
      h("h2", { id: "read-res-h" }, "Zasoby"),
      d.resources.length ? h("ul", { class: "res-list" }, d.resources.map((r) =>
        h("li", {},
          r.kind === "image" && h("img", { src: "/blobs/" + r.hash, alt: r.meta?.alt || "", width: 80, loading: "lazy" }),
          h("span", { class: "res-main" }, h("code", {}, r.path), " · ", r.meta?.title || r.media_type,
            " · ", fmtSize(r.size)),
          (r.kind === "image" || r.kind === "audio") && h("a", { href: "/blobs/" + r.hash }, "Otwórz"))))
      : h("p", { class: "muted" }, "Brak zasobów.")),
    h("section", { class: "panel", "aria-labelledby": "read-grants-h" },
      h("h2", { id: "read-grants-h" }, "Uprawnienia"),
      d.grants.length ? h("ul", { class: "res-list" }, d.grants.map((g) =>
        h("li", {}, h("code", {}, g.action), " · ", h("code", {}, g.resource),
          " · ", g.status, " · klucz ", h("code", {}, short(g.subject_key_id)))))
      : h("p", { class: "muted" }, "Brak przyznanych uprawnień.")),
    h("section", { class: "panel", "aria-labelledby": "read-keys-h" },
      h("h2", { id: "read-keys-h" }, "Klucze publiczne"),
      h("p", {}, "Klucz założycielski: ", h("code", {}, d.founding_key)),
      h("h3", {}, "Klucze autoryzacji"),
      h("ul", { class: "res-list" }, d.auth_keys.map((key) => h("li", {}, h("code", {}, key.key_id), " · ", key.status))),
      h("h3", {}, "Klucze sygnowania"),
      d.members.length ? h("ul", { class: "res-list" }, d.members.map((key) =>
        h("li", {}, h("code", {}, key.key_id), " · ", key.status)))
      : h("p", { class: "muted" }, "Brak dodatkowych kluczy.")),
    h("section", { class: "panel", "aria-labelledby": "read-history-h" },
      h("h2", { id: "read-history-h" }, "Dziennik"),
      h("p", {}, "Ostatnie zdarzenie: #", d.head.seq, " · ", h("code", {}, d.head.id)),
      h("p", {}, h("a", { href: "/api/identities/" + encodeURIComponent(d.id) }, "Pełne dane tożsamości (JSON)")),
      h("a", { href: "/api/identities/" + encodeURIComponent(d.id) + "/events" }, "Wszystkie podpisane zdarzenia (JSON)")));
}

// podpisywanie

/** Podpisuje i wysyła zdarzenie; zwraca `true`, gdy zapisane. Błędy trafiają do komunikatu. */
async function act(type, body, { after } = {}) {
  if (state.busy) return false;
  const signer = state.vault.get(state.signerId);
  if (!signer) {
    say("Wybierz klucz, którym podpiszesz zdarzenie (w skarbcu nie ma klucza sygnowania).", "bad");
    return false;
  }
  state.busy = true;
  say(null);
  try {
    await api.publish({ signer, identity: state.current, type, body, confirm: confirmSign });
    if (after) await after();
    state.busy = false;
    state.message = { text: "Zapisano i podpisano.", kind: "ok" };
    await reload();
    return true;
  } catch (e) {
    state.busy = false;
    say(e.cancelled ? null : e.message, "bad");
    return false;
  }
}

// widok

function render() {
  const d = state.data;
  const rel = (resource) => resource.replace(d.id, "");
  const signers = state.vault.keys.filter((k) => k.kind === "signing");

  const ident = h("div", { class: "identity-bar" },
    state.me.identities.length > 1 && field("Tożsamość", h("select", { id: "identity", onchange: (e) => select(e.target.value) },
      state.me.identities.map((i) => h("option", { value: i.id, selected: i.id === state.current }, i.handle ? "@" + i.handle : short(i.id))))),
    field("Podpisuję kluczem", h("select", { id: "signer", onchange: (e) => { state.signerId = e.target.value; } },
      signers.length === 0 && h("option", { value: "" }, "(brak kluczy sygnowania)"),
      signers.map((k) => h("option", { value: k.id, selected: k.id === state.signerId }, `${k.label || "klucz"} · ${short(k.id)}${k.id === d.founding_key ? " · założycielski" : ""}`)))));

  mount(root,
    h("h1", {}, "Pracownia"),
    h("p", { class: "lead" },
      h("strong", {}, d.handle ? "@" + d.handle : short(d.id)), ` (${d.kind}) · `,
      h("a", { href: "/i/" + (d.handle || d.id) }, "strona publiczna"),
      d.site_url && [" · ", h("a", { href: d.site_url, rel: "noopener" }, "strona tożsamości")],
      " · ", h("button", { class: "link", type: "button", onclick: onLogout }, "wyloguj")),
    h("div", { id: "msg", "aria-live": "polite" }, state.message && notice(state.message.text, state.message.kind)),
    ident,
    profileSection(d),
    visibilitySection(d),
    resourcesSection(d),
    grantsSection(d, rel),
    keysSection(d),
    backupSection());
}

// profil

function profileSection(d) {
  const inputs = Object.fromEntries(PROFILE_FIELDS.map(([name, , kind]) => [name, kind === "textarea"
    ? h("textarea", { id: "p-" + name, rows: 3, maxlength: 600 }, d.profile[name] || "")
    : h("input", { id: "p-" + name, value: d.profile[name] || "", maxlength: 200 })]));

  return h("section", { class: "panel", "aria-labelledby": "profile-h" },
    h("h2", { id: "profile-h" }, "Profil"),
    h("form", { class: "stack", onsubmit: async (e) => {
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
        await act("profile.update", { fields });
      } },
      PROFILE_FIELDS.map(([name, label]) => field(label, inputs[name])),
      h("div", { class: "actions" }, h("button", { class: "btn primary", type: "submit", id: "save-profile" }, "Podpisz i zapisz profil"))));
}

// Widoczność nie jest częścią profilu: zawsze zmieniamy ją podpisanym zdarzeniem.
function visibilitySection(d) {
  const visibility = h("select", { id: "i-visibility" },
    h("option", { value: "public", selected: d.visibility === "public" }, "Publiczna (w katalogu)"),
    h("option", { value: "unlisted", selected: d.visibility === "unlisted" }, "Nieindeksowana (tylko z linku)"));
  return h("section", { class: "panel", "aria-labelledby": "visibility-h" },
    h("h2", { id: "visibility-h" }, "Widoczność"),
    h("p", { class: "muted" }, "Nieindeksowana tożsamość nie pojawia się w katalogu ani galerii. Profil, historia, pliki i własna strona nadal są dostępne z bezpośredniego adresu."),
    h("form", { class: "stack", onsubmit: async (e) => {
      e.preventDefault();
      if (visibility.value === d.visibility) return say("Widoczność się nie zmieniła.");
      await act("identity.visibility.set", { visibility: visibility.value });
    } },
      field("Widoczność profilu", visibility),
      h("div", { class: "actions" }, h("button", { class: "btn primary", type: "submit", id: "save-visibility" }, "Podpisz zmianę widoczności"))));
}

// zasoby

const KIND_LABEL = { image: "Obraz", audio: "Nagranie", site: "Plik strony" };

function resourcesSection(d) {
  const kind = h("select", { id: "r-kind" }, Object.entries(KIND_LABEL).map(([v, l]) => h("option", { value: v }, l)));
  const file = h("input", { id: "r-file", type: "file", required: true });
  const name = h("input", { id: "r-name", autocomplete: "off", placeholder: "domyślnie nazwa pliku" });
  const title = h("input", { id: "r-title", maxlength: 120 });
  const alt = h("input", { id: "r-alt", maxlength: 300 });
  const collection = h("input", { id: "r-collection", maxlength: 40, placeholder: "np. okladki" });

  const upload = h("form", { class: "stack", onsubmit: async (e) => {
      e.preventDefault();
      const f = file.files[0];
      if (!f) return;
      const k = kind.value;
      const path = buildPath(k, name.value.trim() || f.name);
      if (!path) {
        return say("Nazwa pliku jest nieprawidłowa (małe litery, cyfry, . _ -).", "bad");
      }
      const type = f.type || EXT_TYPES[(f.name.split(".").pop() || "").toLowerCase()] || "application/octet-stream";
      const meta = {};
      if (title.value.trim()) meta.title = title.value.trim();
      if (alt.value.trim()) meta.alt = alt.value.trim();
      if (collection.value.trim()) meta.collection = collection.value.trim();

      if (state.busy) return;
      try {
        say("Wysyłanie pliku…");
        const blob = await api.uploadBlob(new Uint8Array(await f.arrayBuffer()), type);
        const body = { path, hash: blob.hash, size: blob.size, media_type: blob.media_type };
        if (Object.keys(meta).length) body.meta = meta;
        await act("resource.put", body);
      } catch (err) {
        say(err.message, "bad");
      }
    } },
    h("div", { class: "grid2" }, field("Rodzaj", kind), field("Plik", file)),
    h("div", { class: "grid2" }, field("Nazwa / ścieżka", name, "Obrazy i nagrania: jedna nazwa. Strona: ścieżka np. css/a.css."), field("Tytuł", title)),
    h("div", { class: "grid2" }, field("Tekst alternatywny (obrazy)", alt), field("Kolekcja", collection)),
    h("div", { class: "actions" }, h("button", { class: "btn primary", type: "submit", id: "upload" }, "Wyślij i podpisz")));

  const list = d.resources.length === 0
    ? h("p", { class: "muted" }, "Brak zasobów.")
    : h("ul", { class: "res-list" }, d.resources.map((r) =>
        h("li", {},
          r.kind === "image" && h("img", { src: "/blobs/" + r.hash, alt: r.meta.alt || "", width: 56, height: 56, loading: "lazy" }),
          h("span", { class: "res-main" }, h("code", {}, r.path), " ", h("span", { class: "muted" }, `${r.media_type} · ${fmtSize(r.size)}`), r.meta.title && h("span", {}, " · " + r.meta.title)),
          h("button", { class: "btn small", type: "button", onclick: () => act("resource.delete", { path: r.path }) }, "Usuń"))));

  return h("section", { class: "panel", "aria-labelledby": "res-h" },
    h("h2", { id: "res-h" }, "Zasoby"),
    h("p", { class: "section-note" }, "Obrazy i nagrania trafiają do galerii na stronie głównej. Pliki strony (site/…) serwuje osobna subdomena."),
    upload, list);
}

function buildPath(kind, raw) {
  if (kind === "site") {
    const p = raw.replace(/^\/+/, "");
    return /^[A-Za-z0-9][A-Za-z0-9._-]{0,79}(\/[A-Za-z0-9][A-Za-z0-9._-]{0,79}){0,7}$/.test(p) ? "site/" + p : null;
  }
  const slug = raw.toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^[^a-z0-9]+/, "").slice(0, 80);
  return slug ? (kind === "image" ? "images/" : "audio/") + slug : null;
}

const fmtSize = (n) => (n >= 1048576 ? (n / 1048576).toFixed(1) + " MiB" : n >= 1024 ? (n / 1024).toFixed(1) + " KiB" : n + " B");

// --- uprawnienia ---

const STATUS = { active: "aktywne", revoked: "unieważnione", expired: "wygasło", pending: "jeszcze nie obowiązuje", broken: "łańcuch przerwany" };

function grantsSection(d, rel) {
  const known = new Map();
  for (const m of d.members) if (m.status === "active") known.set(m.key_id, m.label || "urządzenie");
  for (const k of state.vault.keys) if (k.kind === "signing" && k.id !== d.founding_key) known.set(k.id, known.get(k.id) || k.label || "klucz z tej przeglądarki");

  const subject = h("select", { id: "g-subject" }, [...known].map(([id, label]) => h("option", { value: id }, `${label} · ${short(id)}`)), h("option", { value: "" }, "inny (wpisz id poniżej)"));
  const other = h("input", { id: "g-other", autocomplete: "off", placeholder: "id klucza sygnowania" });
  const action = h("select", { id: "g-action" }, ACTIONS.map((a) => h("option", { value: a }, a)));
  const resource = h("input", { id: "g-resource", value: "/profile/*", autocomplete: "off" });
  const days = h("input", { id: "g-days", type: "number", min: 1, max: 3650, placeholder: "bez końca" });
  const delegable = h("input", { id: "g-delegable", type: "checkbox" });

  const form = h("form", { class: "stack", onsubmit: async (e) => {
      e.preventDefault();
      const subj = other.value.trim() || subject.value;
      if (!subj) return;
      const suffix = resource.value.trim();
      if (!suffix.startsWith("/")) {
        return say("Zasób zaczyna się od / (np. /images/*).", "bad");
      }
      const body = { subject: subj, action: action.value, resource: d.id + suffix };
      if (delegable.checked) body.delegable = true;
      if (days.value) body.expires_at = Math.floor(Date.now() / 1000) + Number(days.value) * 86400;
      await act("grant.create", body);
    } },
    h("div", { class: "grid2" }, field("Komu", subject), field("…albo id klucza", other)),
    h("div", { class: "grid2" }, field("Co może", action), field("Gdzie", resource, "Względem tożsamości, np. /images/*, /profile/bio, /site/*")),
    h("div", { class: "grid2" }, field("Ważne dni", days), h("label", { class: "check" }, delegable, " może przekazywać dalej")),
    h("div", { class: "actions" }, h("button", { class: "btn primary", type: "submit", id: "grant" }, "Nadaj uprawnienie")));

  const rows = d.grants.length === 0
    ? h("p", { class: "muted" }, "Nikomu nie nadano uprawnień.")
    : h("table", { class: "grants" },
        h("thead", {}, h("tr", {}, ["Komu", "Co", "Gdzie", "Stan", ""].map((t) => h("th", { scope: "col" }, t)))),
        h("tbody", {}, d.grants.map((g) =>
          h("tr", { class: ["grant", "is-" + g.status] },
            h("td", { "data-label": "Komu" }, h("code", { title: g.subject_key_id }, known.get(g.subject_key_id) || short(g.subject_key_id))),
            h("td", { "data-label": "Co" }, h("code", {}, g.action)),
            h("td", { "data-label": "Gdzie" }, h("code", { title: g.resource }, rel(g.resource))),
            h("td", { "data-label": "Stan" }, h("span", { class: "status is-" + g.status }, STATUS[g.status] || g.status)),
            h("td", {}, g.status !== "revoked" && h("button", { class: "btn small", type: "button", onclick: () => act("grant.revoke", { grant: g.id }) }, "Cofnij"))))));

  return h("section", { class: "panel", "aria-labelledby": "grants-h" },
    h("h2", { id: "grants-h" }, "Uprawnienia"),
    h("p", { class: "section-note" }, "Klucz założycielski może wszystko. Inne klucze (urządzenia, boty) działają tylko w zakresie grantu."),
    form, rows);
}

// klucze

function keysSection(d) {
  const label = h("input", { id: "k-label", maxlength: 40, placeholder: "np. laptop, bot-wydawca" });
  const pasted = h("input", { id: "k-pasted", autocomplete: "off", placeholder: "id klucza z innej przeglądarki" });
  const authLabel = h("input", { id: "ak-label", maxlength: 40, placeholder: "np. telefon" });

  const addDevice = async (e) => {
    e.preventDefault();
    let id = pasted.value.trim();
    let created = null;
    if (!id) {
      created = await generateKey("signing", label.value.trim() || "urządzenie");
      id = created.id;
      state.vault.add(created);
      await state.vault.save();
    }
    const body = { key: id };
    if (label.value.trim()) body.label = label.value.trim();
    await act("key.add", body);
  };

  const addAuth = async (e) => {
    e.preventDefault();
    const created = await generateKey("auth", authLabel.value.trim() || "logowanie");
    state.vault.add(created);
    await state.vault.save();
    await act("auth_key.add", { key: created.id });
  };

  const activeAuth = d.auth_keys.filter((k) => k.status === "active").length;

  return h("section", { class: "panel", "aria-labelledby": "keys-h" },
    h("h2", { id: "keys-h" }, "Klucze"),
    h("p", { class: "section-note" }, "Klucz założycielski podpisuje i nadaje uprawnienia. Klucze logowania wpuszczają do pracowni. Klucze urządzeń i botów dopisujesz tu, a ich uprawnienia dają granty."),
    h("dl", { class: "facts" }, h("div", {}, h("dt", {}, "Klucz założycielski"), h("dd", {}, h("code", { title: d.founding_key }, short(d.founding_key)))),),
    h("h3", {}, "Klucze logowania"),
    h("ul", { class: "res-list" }, d.auth_keys.map((k) => h("li", {},
      h("span", { class: "res-main" }, h("code", { title: k.key_id }, short(k.key_id)), " ", k.status === "revoked" ? h("span", { class: "tag bad" }, "cofnięty") : state.vault.get(k.key_id) && h("span", { class: "tag" }, "w tej przeglądarce")),
      k.status === "active" && activeAuth > 1 && h("button", { class: "btn small", type: "button", onclick: () => act("auth_key.revoke", { key: k.key_id }) }, "Cofnij")))),
    h("form", { class: "inline", onsubmit: addAuth }, field("Nowy klucz logowania (powstaje tu, trafia do skarbca)", authLabel), h("button", { class: "btn", type: "submit", id: "add-auth" }, "Dodaj")),
    h("h3", {}, "Klucze urządzeń i botów"),
    d.members.length === 0 ? h("p", { class: "muted" }, "Brak dopisanych kluczy.") : h("ul", { class: "res-list" }, d.members.map((m) => h("li", {},
      h("span", { class: "res-main" }, h("code", { title: m.key_id }, short(m.key_id)), " ", m.label && h("span", { class: "muted" }, m.label), " ", m.status === "revoked" && h("span", { class: "tag bad" }, "cofnięty")),
      m.status === "active" && h("button", { class: "btn small", type: "button", onclick: () => act("key.revoke", { key: m.key_id }) }, "Cofnij")))),
    h("form", { class: "stack", onsubmit: addDevice },
      h("div", { class: "grid2" }, field("Etykieta", label), field("Albo wklej id istniejącego klucza", pasted, "Puste = wygeneruj nowy klucz w tej przeglądarce.")),
      h("div", { class: "actions" }, h("button", { class: "btn", type: "submit", id: "add-device" }, "Dopisz klucz"))));
}

// kopie zapasowe

function backupSection() {
  return h("section", { class: "panel", "aria-labelledby": "backup-h" },
    h("h2", { id: "backup-h" }, "Kopie zapasowe i eksport"),
    h("p", { class: "section-note" }, "Skarbiec jest szyfrowany Twoim hasłem. Kopia zapasowa to ten sam zaszyfrowany plik: bez niego i bez hasła klucze przepadną z przeglądarką."),
    h("div", { class: "actions" },
      h("button", { class: "btn", type: "button", id: "backup", onclick: async () => download(`oktavarium-kopia-${new Date().toISOString().slice(0, 10)}.json`, await state.vault.backupFile()) }, "Pobierz zaszyfrowaną kopię"),
      h("details", { class: "danger" },
        h("summary", {}, "Eksport klucza do CLI (jawny plik)"),
        h("p", { class: "muted" }, "Plik zawiera klucz prywatny bez szyfrowania, w formacie `mix oktavarium.key.gen`. Kto go ma, może podpisywać jako ten klucz."),
        state.vault.keys.map((k) => h("button", { class: "btn small", type: "button", onclick: async () => download(`${k.kind}-${short(k.id).replace("…", "-")}.key`, await cliKeyfile(k)) }, `${k.kind} · ${short(k.id)}`)))));
}

start().catch((e) => mount(root, h("h1", {}, "Pracownia"), notice(e.message, "bad")));
