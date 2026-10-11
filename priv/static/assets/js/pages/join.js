// /join: nowa tożsamość. Klucze powstają w przeglądarce; serwer dostaje tylko
// podpisane zdarzenie genesis. Bez pobranej kopii zapasowej nie da się zatwierdzić.
import { generateKey, sign } from "../lib/crypto.js";
import { enc } from "../lib/bytes.js";
import { hasVault, Vault, WrongPassphrase, MIN_PASSPHRASE } from "../lib/keystore.js";
import * as api from "../lib/api.js";
import { h, mount, field, notice, download } from "../lib/ui.js";
import { short } from "../lib/bytes.js";

const root = document.getElementById("app");
const closed = root.dataset.registration === "closed";
const KINDS = [
  ["user", "Użytkownik"],
  ["bot", "Maszyna"],
  ["org", "Organizacja"],
  ["project", "Projekt"],
];

const state = { vault: null, existing: false, founder: null, auth: null, backedUp: false, reuseAuth: true, busy: false, error: null };

async function init() {
  state.existing = await hasVault();
  render();
}

function render() {
  const form = h("form", { class: "stack", onsubmit: onSubmit, novalidate: true });
  const ids = h("div", { class: "keys-preview" });

  const kind = h("select", { id: "kind", name: "kind" }, KINDS.map(([v, l]) => h("option", { value: v }, l)));
  const handle = h("input", {
    id: "handle", name: "handle", autocomplete: "off", maxlength: 32, pattern: "[a-z0-9][a-z0-9_-]{1,31}",
    placeholder: "np. pelagia (opcjonalnie)",
  });
  const invite = closed ? h("input", { id: "invite", name: "invite", autocomplete: "off", required: true }) : null;
  const pass = h("input", { id: "pass", name: "pass", type: "password", autocomplete: "new-password", minlength: MIN_PASSPHRASE, required: true });
  const pass2 = state.existing ? null : h("input", { id: "pass2", type: "password", autocomplete: "new-password", required: true });
  const reuse = state.existing
    ? h("label", { class: "check" }, h("input", { type: "checkbox", id: "reuse", checked: state.reuseAuth, onchange: (e) => (state.reuseAuth = e.target.checked) }),
        " Użyj istniejącego klucza logowania z tej przeglądarki (jeden klucz może należeć do wielu tożsamości)")
    : null;

  if (!state.founder) form.append(
    field("Rodzaj", kind),
    field("Uchwyt", handle, "Małe litery, cyfry, _ i -. Daje adres /i/uchwyt i stronę uchwyt.<domena stron>."),
    invite && field("Zaproszenie", invite, "Rejestracja jest zamknięta. Wklej token od operatora."),
    field(state.existing ? "Hasło skarbca kluczy" : "Hasło do skarbca kluczy", pass,
      state.existing ? "To samo, którym zabezpieczono skarbiec w tej przeglądarce." : `Min. ${MIN_PASSPHRASE} znaków. Szyfruje klucze prywatne; nie da się go odzyskać.`),
    pass2 && field("Powtórz hasło", pass2),
    reuse,
  );

  if (state.founder) {
    form.append(h("dl", { class: "facts" },
      h("div", {}, h("dt", {}, "Rodzaj"), h("dd", {}, KINDS.find(([k]) => k === state.v.kind)[1])),
      h("div", {}, h("dt", {}, "Uchwyt"), h("dd", {}, state.v.handle ? "@" + state.v.handle : "bez uchwytu"))));
  }

  if (!state.founder) {
    form.append(h("div", { class: "actions" }, h("button", { type: "submit", class: "btn primary", disabled: state.busy }, "Wygeneruj klucze")));
  } else {
    ids.append(
      h("h2", {}, "Twoje klucze"),
      h("dl", { class: "facts" },
        h("div", {}, h("dt", {}, "Klucz założycielski (podpisuje zdarzenia)"), h("dd", {}, h("code", { title: state.founder.id }, short(state.founder.id)))),
        h("div", {}, h("dt", {}, "Klucz logowania"), h("dd", {}, h("code", { title: state.auth.id }, short(state.auth.id)), state.auth.reused && " (istniejący)")),
      ),
      notice("Klucze prywatne istnieją tylko tutaj. Jeśli stracisz tę przeglądarkę bez kopii zapasowej, stracisz tożsamość: nie ma resetu hasła.", "warn"),
      h("div", { class: "actions" },
        h("button", { type: "button", class: "btn", onclick: onBackup }, "Pobierz zaszyfrowaną kopię zapasową"),
      ),
      h("label", { class: "check" },
        h("input", { type: "checkbox", id: "backed", checked: state.backedUp, disabled: !state.backupDownloaded, onchange: (e) => { state.backedUp = e.target.checked; render(); } }),
        " Pobrałem kopię i zapisałem ją w bezpiecznym miejscu"),
      h("div", { class: "actions" },
        h("button", { type: "submit", class: "btn primary", id: "create", disabled: !state.backedUp || state.busy }, state.busy ? "Zakładanie…" : "Załóż tożsamość"),
      ),
    );
  }

  if (state.founder) form.append(ids);

  mount(root, h("h1", {}, "Załóż tożsamość"),
    h("p", { class: "lead" }, "Klucze generuje i przechowuje Twoja przeglądarka. Serwer nie zobaczy klucza prywatnego, tylko podpisane zdarzenie założycielskie."),
    state.error && notice(state.error, "bad"), form,
    h("p", { class: "muted" }, "Masz już tożsamość? ", h("a", { href: "/login" }, "Zaloguj się"), "."));
}

const values = () => ({
  kind: document.getElementById("kind").value,
  handle: document.getElementById("handle").value.trim(),
  invite: document.getElementById("invite")?.value.trim(),
  pass: document.getElementById("pass").value,
  pass2: document.getElementById("pass2")?.value,
});

async function onSubmit(e) {
  e.preventDefault();
  if (state.busy) return;
  state.error = null;
  try {
    if (!state.founder) {
      const v = values();
      await generate(v);
      state.v = v;
    } else {
      await create(state.v);
    }
  } catch (err) {
    state.error = err.message;
    state.busy = false;
  }
  render();
}

async function generate(v) {
  if (v.pass.length < MIN_PASSPHRASE) throw new Error(`Hasło musi mieć co najmniej ${MIN_PASSPHRASE} znaków.`);
  if (v.handle && !/^[a-z0-9][a-z0-9_-]{1,31}$/.test(v.handle)) throw new Error("Uchwyt: 2–32 znaków, małe litery, cyfry, _ i -.");
  if (closed && !v.invite) throw new Error("Wklej zaproszenie.");

  if (state.existing) {
    try {
      state.vault = await Vault.unlock(v.pass);
    } catch (e) {
      throw e instanceof WrongPassphrase ? e : new Error("Nie udało się otworzyć skarbca: " + e.message);
    }
  } else {
    if (v.pass !== v.pass2) throw new Error("Hasła się różnią.");
    state.vault = Vault.empty(v.pass);
  }

  state.founder = await generateKey("signing", v.handle ? "@" + v.handle : "założycielski");
  const existingAuth = state.existing && state.reuseAuth ? state.vault.ofKind("auth")[0] : null;
  state.auth = existingAuth ? { ...existingAuth, reused: true } : await generateKey("auth", "logowanie");
  state.backupDownloaded = false;
  state.backedUp = false;
}

async function onBackup() {
  // kopia zawiera także nowe, jeszcze niezapisane klucze
  const staged = Vault.empty(state.vault.passphrase);
  staged.data = JSON.parse(JSON.stringify(state.vault.data));
  staged.add(state.founder);
  if (!state.auth.reused) staged.add(state.auth);
  download(`oktavarium-kopia-${new Date().toISOString().slice(0, 10)}.json`, await staged.backupFile());
  state.backupDownloaded = true;
  render();
}

async function create(v) {
  state.busy = true;
  render();

  // najpierw skarbiec: klucze nie mogą zginąć, nawet jeśli serwer odrzuci zdarzenie
  state.vault.add(state.founder);
  if (!state.auth.reused) state.vault.add(state.auth);
  await state.vault.save();

  const body = { kind: v.kind, auth_keys: [state.auth.id] };
  if (v.handle) body.handle = v.handle;

  const created = await api.genesis({ founder: state.founder, body, invite: v.invite });
  state.vault.update(state.founder.id, { identity: created.identity });
  await state.vault.save();

  await api.login(state.vault.get(state.auth.id), (message, priv) => sign("login", enc.encode(message), priv));
  location.assign("/studio");
}

init().catch((e) => {
  state.error = e.message;
  render();
});
