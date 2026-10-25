import { failure } from "../lib/failure.js";
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
  pending: null,
  values: {
    kind:
      new URLSearchParams(location.search).get("kind") === "collective"
        ? "collective"
        : "person",
    visibility: "public",
    handle: "",
    displayName: "",
    invite: "",
  },
};
let leaving = false;
window.addEventListener("beforeunload", (e) => {
  if (!leaving && ((state.founder && !state.created) || api.hasPending())) {
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
    state.error = failure(e).message;
    if (failure(e).code === "unknown_outcome" && !state.created)
      state.pending = failure(e).attemptIdentity;
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
    minlength: state.existing ? void 0 : MIN_PASSPHRASE,
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
      field("Rodzaj to\u017Csamo\u015Bci", kind),
      field(
        "Obecno\u015B\u0107 w katalogu",
        visibility,
        "Nieindeksowana nie oznacza prywatnej.",
      ),
    ),
    field(
      "Uchwyt (opcjonalny)",
      handle,
      "2\u201332 znaki: ma\u0142e litery, cyfry, _ i -.",
    ),
    field(
      "Nazwa wy\u015Bwietlana (opcjonalna)",
      displayName,
      "Np. Pracownia P\xF3\u0142noc. Nie zmienia @uchwytu ani adresu; po utworzeniu wymaga osobnego podpisu.",
    ),
    invite && field("Token od operatora instancji", invite),
  );
  if (!state.founder) {
    if (!localVault())
      form.append(
        ...[
          field(
            state.existing
              ? "Has\u0142o obecnego skarbca"
              : "Has\u0142o nowego skarbca",
            secret,
          ),
          repeat && field("Powt\xF3rz has\u0142o", repeat),
        ].filter(Boolean),
      );
    else
      form.append(
        notice(
          "Lokalny skarbiec jest odblokowany. Dodasz klucze bez zast\u0119powania istniej\u0105cych.",
        ),
      );
    if (state.existing)
      form.append(
        h(
          "label",
          { class: "check" },
          reuse,
          " U\u017Cyj istniej\u0105cego klucza autoryzacji. Klucz za\u0142o\u017Cycielski b\u0119dzie nowy.",
        ),
      );
    form.append(
      h(
        "button",
        { type: "submit", class: "btn primary", disabled: state.busy },
        state.busy ? "Przygotowanie\u2026" : "Przygotuj klucze lokalnie",
      ),
    );
  } else {
    form.append(
      h(
        "section",
        { class: "panel" },
        h("h2", {}, "Zabezpiecz klucze przed utworzeniem to\u017Csamo\u015Bci"),
        h(
          "p",
          {},
          "Klucz za\u0142o\u017Cycielski: ",
          h("code", {}, state.founder.id),
        ),
        h(
          "p",
          { class: "hint" },
          "Zmiana uchwytu nie generuje nowych kluczy. Kopia zawiera ca\u0142y przygotowany skarbiec.",
        ),
        button(
          "Pobierz zaszyfrowan\u0105 kopi\u0119",
          async () => {
            download(
              "oktavarium-kopia-" +
                /* @__PURE__ */ new Date().toISOString().slice(0, 10) +
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
          " Potwierdzam, \u017Ce kopia zosta\u0142a zapisana w bezpiecznym miejscu.",
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
        "Sprawd\u017A utworzenie to\u017Csamo\u015Bci",
      ),
    );
  }
  mount(
    root,
    h(
      "p",
      { class: "eyebrow" },
      "To\u017Csamo\u015B\u0107 \u2192 klucze \u2192 kopia \u2192 podpis",
    ),
    h("h1", {}, "Za\u0142\xF3\u017C to\u017Csamo\u015B\u0107"),
    h(
      "p",
      { class: "lead" },
      "Osoba i kolektyw maj\u0105 ten sam model. Odczyt jest otwarty; klucze s\u0142u\u017C\u0105 do zatwierdzania zmian.",
    ),
    state.error && notice(state.error, "bad"),
    form,
    pending(),
    h(
      "p",
      { class: "hint" },
      "Nie ma resetu has\u0142a przez serwer. Zachowaj kopi\u0119 i has\u0142o. Nie udost\u0119pniaj prywatnego klucza wsp\xF3\u0142pracownikom \u2014 nadaj grant ich kluczowi.",
    ),
    h("a", { href: "/login" }, "Mam ju\u017C klucze"),
  );
}
async function prepare(pass, repeat, reuse) {
  const v = state.values;
  if (v.handle && !/^[a-z0-9][a-z0-9_-]{1,31}$/.test(v.handle))
    throw new Error("Nieprawid\u0142owy uchwyt.");
  if (
    v.displayName &&
    (v.displayName.length > 80 || /\p{Cc}/u.test(v.displayName))
  )
    throw new Error(
      "Nazwa wy\u015Bwietlana nie mo\u017Ce zawiera\u0107 znak\xF3w steruj\u0105cych ani przekracza\u0107 80 znak\xF3w.",
    );
  if (closed && !v.invite) throw new Error("Wklej token od operatora.");
  const existing =
    localVault() || (state.existing ? await Vault.unlock(pass) : null);
  if (!existing && (pass.length < MIN_PASSPHRASE || pass !== repeat))
    throw new Error(
      "Has\u0142a musz\u0105 si\u0119 zgadza\u0107 i mie\u0107 co najmniej " +
        MIN_PASSPHRASE +
        " znak\xF3w.",
    );
  const staged = Vault.empty(existing?.passphrase || pass);
  if (existing) staged.data = structuredClone(existing.data);
  const founder = await generateKey(
    "signing",
    v.handle ? "@" + v.handle : "Za\u0142o\u017Cycielski",
  );
  const auth =
    (reuse && existing?.ofKind("auth")[0]) ||
    (await generateKey("auth", "Przesy\u0142anie plik\xF3w"));
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
  if (!state.vault || !state.founder || !state.auth)
    throw new Error("Przygotuj i zabezpiecz klucze przed utworzeniem.");
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
    }))
  )
    return;
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
  if (!state.vault || !state.founder)
    throw new Error(
      "To\u017Csamo\u015B\u0107 powsta\u0142a, ale nie ma odblokowanego skarbca do zapisania etykiety.",
    );
  state.vault.update(state.founder.id, { identity: receipt.identity });
  try {
    await state.vault.save();
  } catch (e) {
    state.error =
      "To\u017Csamo\u015B\u0107 powsta\u0142a, ale nie zapisano jej lokalnej etykiety. Klucze by\u0142y zapisane przed publikacj\u0105. Pobierz zaktualizowan\u0105 kopi\u0119. " +
      failure(e).message;
  }
}
function pending() {
  if (!state.pending) return null;
  const id = state.pending;
  return h(
    "section",
    { class: "panel pending-write" },
    h("h2", {}, "Nieznany wynik utworzenia"),
    h("p", {}, "ID pr\xF3by: ", h("code", {}, id)),
    button("Sprawd\u017A t\u0119 sam\u0105 pr\xF3b\u0119", async () => {
      const r = await api.checkPending(id);
      if (r) await finish(r);
      else
        state.error =
          "Nie znaleziono jeszcze zdarzenia. Brak odpowiedzi nie oznacza odrzucenia.";
    }),
    button("Wy\u015Blij ponownie identyczn\u0105 kopert\u0119", async () =>
      finish(await api.retryPending(id)),
    ),
  );
}
async function publishName() {
  const name = state.values.displayName;
  if (
    !name ||
    state.namePublished ||
    state.namePending ||
    !state.founder ||
    !state.created
  )
    return;
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
    if (failure(e).code === "unknown_outcome") state.namePending = true;
    throw e;
  }
}
async function reconcileName(retry) {
  if (!state.created) return;
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
  if (!state.created || !state.vault) return;
  const vault = state.vault;
  const identity = state.created.identity;
  const needsName = Boolean(state.values.displayName) && !state.namePublished;
  mount(
    root,
    h("p", { class: "eyebrow" }, "Genesis przyj\u0119te"),
    h("h1", {}, "To\u017Csamo\u015B\u0107 jest gotowa"),
    state.error && notice(state.error, "warn"),
    h("p", {}, "ID: ", h("code", {}, identity)),
    h(
      "p",
      {},
      "Nie logowali\u015Bmy do serwera. Klucze pozostaj\u0105 odblokowane lokalnie.",
    ),
    needsName &&
      h(
        "section",
        { class: "panel stack", id: "publish-display-name" },
        h("h2", {}, "Nazwa wy\u015Bwietlana"),
        h(
          "p",
          {},
          "Wybrana nazwa: ",
          h("strong", {}, state.values.displayName),
        ),
        h(
          "p",
          { class: "hint" },
          "Utworzenie to\u017Csamo\u015Bci nie zapisuje profilu. Nazw\u0119 trzeba potwierdzi\u0107 osobnym podpisem. Mo\u017Cesz te\u017C doda\u0107 j\u0105 p\xF3\u017Aniej w Pracowni.",
        ),
        state.namePending
          ? h(
              "div",
              { class: "stack pending-write" },
              notice(
                "Nie wiadomo, czy aktualizacja nazwy dotar\u0142a. Nie tw\xF3rz nowego podpisu przed sprawdzeniem poprzedniej pr\xF3by.",
                "warn",
              ),
              button(
                "Sprawd\u017A zapis nazwy",
                () => reconcileName(false),
                "name-check",
              ),
              button(
                "Pon\xF3w t\u0119 sam\u0105 kopert\u0119",
                () => reconcileName(true),
                "name-retry",
              ),
            )
          : button(
              "Sprawd\u017A i podpisz nazw\u0119",
              publishName,
              "publish-name",
            ),
      ),
    state.namePublished &&
      notice("Nazwa wy\u015Bwietlana zosta\u0142a zapisana w profilu.", "ok"),
    button(
      "Pobierz kopi\u0119 z adresem nowej to\u017Csamo\u015Bci",
      async () =>
        download("oktavarium-kopia-utworzona.json", await vault.backupFile()),
    ),
    button(
      "Otw\xF3rz w Pracowni",
      async () => {
        leaving = true;
        await enterStudio(vault, identity);
      },
      "enter-studio",
    ),
  );
}
(async () => {
  state.existing = await hasVault();
  render();
})().catch((e) => {
  state.error = failure(e).message;
  render();
});
