// A new founder key is staged locally. Backup and local commit precede genesis.
import { generateKey } from "../lib/crypto.js";
import { Vault, hasVault, MIN_PASSPHRASE } from "../lib/keystore.js";
import { localVault, enterStudio } from "../lib/local-state.js";
import * as api from "../lib/api.js";
import { h, mount, field, notice, download, confirmSign } from "../lib/ui.js";
const root = document.getElementById("app");
root.classList.add("auth-app");
const closed = root.dataset.registration === "closed";
const state = {
  stage: "details",
  existing: false,
  vault: null,
  founder: null,
  auth: null,
  backupDownloaded: false,
  backedUp: false,
  busy: false,
  error: null,
  created: null,
  namePublished: false,
  namePending: false,
  values: {
    kind:
      new URLSearchParams(location.search).get("kind") === "collective"
        ? "collective"
        : "person",
    visibility: "public",
    handle: "",
    displayName: "",
    invite: "",
    reuse: true,
  },
};
let leaving = false;
window.addEventListener("beforeunload", (e) => {
  if (!leaving && state.founder && !state.created) {
    e.preventDefault();
    e.returnValue = "";
  }
});
const button = (label, fn, id) =>
  h(
    "button",
    {
      type: "button",
      id,
      class: "btn",
      disabled: state.busy,
      onclick: () => run(fn),
    },
    label,
  );
async function run(fn) {
  if (state.busy) return;
  state.busy = true;
  state.error = null;
  try {
    await fn();
  } catch (e) {
    state.error = e.message;
    if (e.code === "unknown_outcome" && !state.created)
      state.pending = e.attempt.identity;
  } finally {
    state.busy = false;
    render();
  }
}
function render() {
  if (root.dataset.page !== "join") return;
  if (state.created) return success();
  const v = state.values;
  const kind = h(
    "select",
    { id: "kind", name: "kind", disabled: Boolean(state.pending) },
    h("option", { value: "person", selected: v.kind === "person" }, "Osoba"),
    h(
      "option",
      { value: "collective", selected: v.kind === "collective" },
      "Kolektyw",
    ),
  );
  const visibility = h(
    "select",
    { id: "visibility", name: "visibility", disabled: Boolean(state.pending) },
    h(
      "option",
      { value: "public", selected: v.visibility === "public" },
      "W katalogu",
    ),
    h(
      "option",
      { value: "unlisted", selected: v.visibility === "unlisted" },
      "Nieindeksowana (odczyt przez adres)",
    ),
  );
  const handle = h("input", {
    id: "handle",
    value: v.handle,
    autocomplete: "off",
    maxlength: 32,
    pattern: "[a-z0-9][a-z0-9_\\-]{1,31}",
    disabled: Boolean(state.pending),
  });
  const displayName = h("input", {
    id: "display-name",
    value: v.displayName,
    autocomplete: "off",
    maxlength: 80,
    placeholder: "np. Pracownia Kaligula",
  });
  const invite =
    closed &&
    h("input", {
      id: "invite",
      value: v.invite,
      autocomplete: "off",
      required: true,
      disabled: Boolean(state.pending),
    });
  const secret = h("input", {
    id: "pass",
    type: "password",
    required: !localVault(),
    minlength: state.existing ? undefined : MIN_PASSPHRASE,
    autocomplete: state.existing ? "current-password" : "new-password",
  });
  const repeat =
    !state.existing &&
    h("input", {
      id: "pass2",
      type: "password",
      required: true,
      autocomplete: "new-password",
    });
  const reuse = h("input", { id: "reuse", type: "checkbox", checked: true });
  const snapshot = () => {
    state.values = {
      kind: kind.value,
      visibility: visibility.value,
      handle: handle.value.trim(),
      displayName: displayName.value.trim(),
      invite: invite ? invite.value.trim() : "",
    };
  };
  for (const input of [kind, visibility, handle, displayName, invite].filter(
    Boolean,
  ))
    input.addEventListener("input", snapshot);
  const form = h(
    "form",
    {
      id: "join-form",
      class: "stack",
      onsubmit: (e) => {
        e.preventDefault();
        snapshot();
        const pass = secret.value,
          pass2 = repeat?.value;
        run(() =>
          state.founder ? create() : prepare(pass, pass2, reuse.checked),
        );
      },
    },
    h(
      "div",
      { class: "grid2" },
      field("Rodzaj tożsamości", kind),
      field(
        "Obecność w katalogu",
        visibility,
        "Nieindeksowana nie oznacza prywatnej.",
      ),
    ),
    field(
      "Uchwyt (opcjonalny)",
      handle,
      "2–32 znaki: małe litery, cyfry, _ i -.",
    ),
    field(
      "Nazwa wyświetlana (opcjonalna)",
      displayName,
      "Np. Pracownia Północ. Nie zmienia @uchwytu ani adresu; po utworzeniu wymaga osobnego podpisu.",
    ),
    invite && field("Token od operatora instancji", invite),
  );
  if (!state.founder) {
    if (!localVault())
      form.append(
        ...[
          field(
            state.existing ? "Hasło obecnego skarbca" : "Hasło nowego skarbca",
            secret,
          ),
          repeat && field("Powtórz hasło", repeat),
        ].filter(Boolean),
      );
    else
      form.append(
        notice(
          "Lokalny skarbiec jest odblokowany. Dodasz klucze bez zastępowania istniejących.",
        ),
      );
    if (state.existing)
      form.append(
        h(
          "label",
          { class: "check" },
          reuse,
          " Użyj istniejącego klucza autoryzacji. Klucz założycielski będzie nowy.",
        ),
      );
    form.append(
      h(
        "button",
        { type: "submit", class: "btn primary", disabled: state.busy },
        state.busy ? "Przygotowanie…" : "Przygotuj klucze lokalnie",
      ),
    );
  } else {
    form.append(
      h(
        "section",
        { class: "panel" },
        h("h2", {}, "Zabezpiecz klucze przed utworzeniem tożsamości"),
        h("p", {}, "Klucz założycielski: ", h("code", {}, state.founder.id)),
        h(
          "p",
          { class: "hint" },
          "Zmiana uchwytu nie generuje nowych kluczy. Kopia zawiera cały przygotowany skarbiec.",
        ),
        button(
          "Pobierz zaszyfrowaną kopię",
          async () => {
            download(
              "oktavarium-kopia-" +
                new Date().toISOString().slice(0, 10) +
                ".json",
              await state.vault.backupFile(),
            );
            state.backupDownloaded = true;
          },
          "join-backup",
        ),
        h(
          "label",
          { class: "check" },
          h("input", {
            id: "backed",
            type: "checkbox",
            checked: state.backedUp,
            disabled: !state.backupDownloaded || Boolean(state.pending),
            onchange: (e) => {
              state.backedUp = e.target.checked;
              render();
            },
          }),
          " Potwierdzam, że kopia została zapisana w bezpiecznym miejscu.",
        ),
      ),
      h(
        "button",
        {
          id: "create",
          type: "submit",
          class: "btn primary",
          disabled: state.busy || !state.backedUp || Boolean(state.pending),
        },
        "Sprawdź utworzenie tożsamości",
      ),
    );
  }
  mount(
    root,
    h("p", { class: "eyebrow" }, "Tożsamość → klucze → kopia → podpis"),
    h("h1", {}, "Załóż tożsamość"),
    h(
      "p",
      { class: "lead" },
      "Osoba i kolektyw mają ten sam model. Odczyt jest otwarty; klucze służą do zatwierdzania zmian.",
    ),
    state.error && notice(state.error, "bad"),
    form,
    pending(),
    h(
      "p",
      { class: "hint" },
      "Nie ma resetu hasła przez serwer. Zachowaj kopię i hasło. Nie udostępniaj prywatnego klucza współpracownikom — nadaj grant ich kluczowi.",
    ),
    h("a", { href: "/login" }, "Mam już klucze"),
  );
}
async function prepare(pass, repeat, reuse) {
  const v = state.values;
  if (v.handle && !/^[a-z0-9][a-z0-9_-]{1,31}$/.test(v.handle))
    throw new Error("Nieprawidłowy uchwyt.");
  if (
    v.displayName &&
    (v.displayName.length > 80 || /[\x00-\x1f\x7f-\x9f]/u.test(v.displayName))
  )
    throw new Error(
      "Nazwa wyświetlana nie może zawierać znaków sterujących ani przekraczać 80 znaków.",
    );
  if (closed && !v.invite) throw new Error("Wklej token od operatora.");
  const existing =
    localVault() || (state.existing ? await Vault.unlock(pass) : null);
  if (!existing && (pass.length < MIN_PASSPHRASE || pass !== repeat))
    throw new Error(
      "Hasła muszą się zgadzać i mieć co najmniej " +
        MIN_PASSPHRASE +
        " znaków.",
    );
  const staged = Vault.empty(existing?.passphrase || pass);
  if (existing) staged.data = structuredClone(existing.data);
  const founder = await generateKey(
    "signing",
    v.handle ? "@" + v.handle : "Założycielski",
  );
  const auth =
    (reuse && existing?.ofKind("auth")[0]) ||
    (await generateKey("auth", "Przesyłanie plików"));
  staged.add(founder);
  staged.add(auth);
  state.vault = staged;
  state.founder = founder;
  state.auth = auth;
  state.backedUp = false;
  state.backupDownloaded = false;
}
async function create() {
  if (!state.backedUp || state.pending) return;
  const v = state.values;
  const body = {
    kind: v.kind,
    visibility: v.visibility,
    auth_keys: [state.auth.id],
    ...(v.handle ? { handle: v.handle } : {}),
  };
  if (
    !(await confirmSign({
      type: "identity.genesis",
      body,
      signer: state.founder,
      identity: null,
    }))
  )
    return;
  // failed IndexedDB commit stops here
  await state.vault.save();
  const receipt = await api.genesis({
    founder: state.founder,
    body,
    invite: v.invite,
  });
  await finish(receipt);
}
async function finish(receipt) {
  state.created = receipt;
  state.pending = null;
  state.vault.update(state.founder.id, { identity: receipt.identity });
  try {
    await state.vault.save();
  } catch (e) {
    state.error =
      "Tożsamość powstała, ale nie zapisano jej lokalnej etykiety. Klucze były zapisane przed publikacją. Pobierz zaktualizowaną kopię. " +
      e.message;
  }
}
function pending() {
  if (!state.pending) return null;
  const id = state.pending;
  return h(
    "section",
    { class: "panel pending-write" },
    h("h2", {}, "Nieznany wynik utworzenia"),
    h("p", {}, "ID próby: ", h("code", {}, id)),
    button("Sprawdź tę samą próbę", async () => {
      const r = await api.checkPending(id);
      if (r) await finish(r);
      else
        state.error =
          "Nie znaleziono jeszcze zdarzenia. Brak odpowiedzi nie oznacza odrzucenia.";
    }),
    button("Wyślij ponownie identyczną kopertę", async () =>
      finish(await api.retryPending(id)),
    ),
  );
}
// Genesis intentionally contains no profile fields. The display name is a second,
// separately approved signed event, not an implicit side effect of registration.
async function publishName() {
  const name = state.values.displayName;
  if (!name || state.namePublished || state.namePending) return;
  const body = { fields: { display_name: name } };
  if (
    !(await confirmSign({
      type: "profile.update",
      body,
      signer: state.founder,
      identity: state.created.identity,
      context: { data: { handle: state.values.handle, profile: {} } },
    }))
  )
    return;
  try {
    await api.publish({
      signer: state.founder,
      identity: state.created.identity,
      type: "profile.update",
      body,
    });
    state.namePublished = true;
  } catch (e) {
    if (e.code === "unknown_outcome") state.namePending = true;
    throw e;
  }
}

async function reconcileName(retry) {
  const identity = state.created.identity;
  const receipt = retry
    ? await api.retryPending(identity)
    : await api.checkPending(identity);
  if (receipt) {
    state.namePending = false;
    state.namePublished = true;
  } else {
    state.error =
      "Nie odnaleziono jeszcze podpisanej nazwy. Wynik pozostaje nieznany.";
  }
}

function success() {
  const needsName = Boolean(state.values.displayName) && !state.namePublished;
  mount(
    root,
    h("p", { class: "eyebrow" }, "Genesis przyjęte"),
    h("h1", {}, "Tożsamość jest gotowa"),
    state.error && notice(state.error, "warn"),
    h("p", {}, "ID: ", h("code", {}, state.created.identity)),
    h(
      "p",
      {},
      "Nie logowaliśmy do serwera. Klucze pozostają odblokowane lokalnie.",
    ),
    needsName &&
      h(
        "section",
        { class: "panel stack", id: "publish-display-name" },
        h("h2", {}, "Nazwa wyświetlana"),
        h(
          "p",
          {},
          "Wybrana nazwa: ",
          h("strong", {}, state.values.displayName),
        ),
        h(
          "p",
          { class: "hint" },
          "Utworzenie tożsamości nie zapisuje profilu. Nazwę trzeba potwierdzić osobnym podpisem. Możesz też dodać ją później w Pracowni.",
        ),
        state.namePending
          ? h(
              "div",
              { class: "stack pending-write" },
              notice(
                "Nie wiadomo, czy aktualizacja nazwy dotarła. Nie twórz nowego podpisu przed sprawdzeniem poprzedniej próby.",
                "warn",
              ),
              button(
                "Sprawdź zapis nazwy",
                () => reconcileName(false),
                "name-check",
              ),
              button(
                "Ponów tę samą kopertę",
                () => reconcileName(true),
                "name-retry",
              ),
            )
          : button("Sprawdź i podpisz nazwę", publishName, "publish-name"),
      ),
    state.namePublished &&
      notice("Nazwa wyświetlana została zapisana w profilu.", "ok"),
    button("Pobierz kopię z adresem nowej tożsamości", async () =>
      download(
        "oktavarium-kopia-utworzona.json",
        await state.vault.backupFile(),
      ),
    ),
    button(
      "Otwórz w Pracowni",
      async () => {
        leaving = true;
        await enterStudio(state.vault, state.created.identity);
      },
      "enter-studio",
    ),
  );
}
(async () => {
  state.existing = await hasVault();
  render();
})().catch((e) => {
  state.error = e.message;
  render();
});
