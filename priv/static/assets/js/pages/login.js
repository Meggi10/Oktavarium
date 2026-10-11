// /login: odblokowanie skarbca hasłem i logowanie podpisem klucza autoryzacji.
// Bez skarbca w tej przeglądarce można wczytać kopię zapasową.
import { sign } from "../lib/crypto.js";
import { enc, short } from "../lib/bytes.js";
import { hasVault, Vault, WrongPassphrase, restoreBackup } from "../lib/keystore.js";
import * as api from "../lib/api.js";
import { h, mount, field, notice } from "../lib/ui.js";

const root = document.getElementById("app");
const state = { has: false, error: null, busy: false, restoring: false };

async function init() {
  state.has = await hasVault();
  render();
}

function render() {
  const pass = h("input", { id: "pass", type: "password", autocomplete: "current-password", required: true });
  const file = h("input", { id: "backup", type: "file", accept: "application/json,.json" });

  const unlock = h("form", { class: "stack", onsubmit: onLogin },
    field("Hasło skarbca kluczy", pass),
    h("div", { class: "actions" }, h("button", { class: "btn primary", type: "submit", disabled: state.busy }, state.busy ? "Logowanie..." : "Zaloguj")));

  const restore = h("form", { class: "stack", onsubmit: onRestore },
    h("p", {}, "Wczytaj kopię zapasową skarbca (plik pobrany przy zakładaniu tożsamości), a potem zaloguj się hasłem."),
    field("Plik kopii", file),
    field("Hasło skarbca kluczy", h("input", { id: "pass-restore", type: "password", autocomplete: "current-password", required: true })),
    h("div", { class: "actions" }, h("button", { class: "btn primary", type: "submit", disabled: state.busy }, "Przywróć i zaloguj")));

  mount(root,
    h("h1", {}, "Zaloguj się kluczem"),
    h("p", { class: "lead" }, "Logujesz się podpisem klucza z tej przeglądarki; hasło nie jest wysyłane na serwer."),
    state.error && notice(state.error, "bad"),
    state.has && !state.restoring ? unlock : restore,
    state.has && h("p", { class: "muted" },
      h("button", { class: "link", type: "button", onclick: () => { state.restoring = !state.restoring; state.error = null; render(); } },
        state.restoring ? "Wróć do logowania" : "Wczytaj kopię zapasową zamiast tego")),
    h("p", { class: "muted" }, "Nie masz tożsamości? ", h("a", { href: "/join" }, "Załóż ją"), "."));
}

async function finish(vault) {
  const keys = vault.ofKind("auth");
  if (keys.length === 0) throw new Error("W skarbcu nie ma klucza logowania.");
  // próbujemy kolejnych kluczy logowania, aż serwer któryś zna
  let last;
  for (const key of keys) {
    try {
      await api.login(key, (message, priv) => sign("login", enc.encode(message), priv));
      location.assign("/studio");
      return;
    } catch (e) {
      last = e;
      if (e.code !== "unknown_key") throw e;
    }
  }
  throw new Error(`Serwer nie zna żadnego z kluczy logowania (${keys.map((k) => short(k.id)).join(", ")}). ${last?.message ?? ""}`);
}

async function run(fn) {
  if (state.busy) return;
  state.busy = true;
  state.error = null;
  render();
  try {
    await fn();
  } catch (e) {
    state.error = e instanceof WrongPassphrase ? e.message : e.message;
    state.busy = false;
    render();
  }
}

// Wartości pól czytamy zanim `run` przerysuje formularz (render tworzy puste pola).
const onLogin = (e) => {
  e.preventDefault();
  const pass = document.getElementById("pass").value;
  return run(async () => finish(await Vault.unlock(pass)));
};

const onRestore = (e) => {
  e.preventDefault();
  const f = document.getElementById("backup").files[0];
  const pass = document.getElementById("pass-restore").value;
  return run(async () => {
    if (!f) throw new Error("Wybierz plik kopii zapasowej.");
    let parsed;
    try {
      parsed = JSON.parse(await f.text());
    } catch {
      throw new Error("Plik nie jest poprawnym JSON-em.");
    }
    const vault = await restoreBackup(parsed, pass);
    await vault.save();
    await finish(vault);
  });
};

init().catch((e) => {
  state.error = e.message;
  render();
});
