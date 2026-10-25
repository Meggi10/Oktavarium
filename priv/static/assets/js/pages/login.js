import { failure } from "../lib/failure.js";
import { hasVault, Vault, restoreBackup } from "../lib/keystore.js";
import { localVault, rememberVault, enterStudio } from "../lib/local-state.js";
import { unlockDialog } from "../lib/vault-ui.js";
import { h, mount, field, notice, download } from "../lib/ui.js";
import { short } from "../lib/bytes.js";
const root = document.getElementById("app");
const state = {
  has: false,
  restoring: new URLSearchParams(location.search).has("restore"),
  busy: false,
  error: null,
  restored: null,
  old: localVault(),
  backupDownloaded: false,
  restoreFile: null,
};
const ref = new URLSearchParams(location.search).get("ref");
root.classList.add("auth-app");
const header = () => [
  h("p", { class: "eyebrow" }, "Klucze pozostaj\u0105 w przegl\u0105darce"),
  h(
    "h1",
    {},
    state.restoring ? "Przywr\xF3\u0107 skarbiec" : "Odblokuj klucze",
  ),
  h(
    "p",
    { class: "lead" },
    "Odczyt jest otwarty. Has\u0142o odblokowuje tylko lokalne klucze; nie tworzy sesji na serwerze.",
  ),
  state.error && notice(state.error, "bad"),
];
const btn = (label, fn) =>
  h(
    "button",
    {
      type: "button",
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
  } finally {
    state.busy = false;
    render();
  }
}
function render() {
  if (root.dataset.page !== "login") return;
  if (state.restored) return review();
  const pass = h("input", {
    id: "pass",
    type: "password",
    autocomplete: "current-password",
    required: true,
  });
  const backup = h("input", {
    id: "backup",
    type: "file",
    accept: "application/json,.json",
    required: true,
  });
  if (state.restoreFile) {
    const dt = new DataTransfer();
    dt.items.add(state.restoreFile);
    backup.files = dt.files;
  }
  backup.addEventListener("change", () => {
    state.restoreFile = backup.files[0] || null;
  });
  const form = h(
    "form",
    {
      class: "stack",
      id: state.restoring ? "restore-check" : "unlock-vault",
      onsubmit: (e) => {
        e.preventDefault();
        const secret = pass.value;
        const file = backup.files[0];
        run(async () => {
          if (state.restoring) {
            if (!file || file.size > 5 * 1024 * 1024)
              throw new Error("Wybierz kopi\u0119 JSON o rozmiarze do 5 MiB.");
            let parsed;
            try {
              parsed = JSON.parse(await file.text());
            } catch {
              throw new Error("Plik nie jest poprawnym JSON-em.");
            }
            state.restored = await restoreBackup(parsed, secret);
            pass.value = "";
          } else {
            const vault = await Vault.unlock(secret);
            pass.value = "";
            rememberVault(vault);
            await enterStudio(
              vault,
              ref || vault.keys.find((k) => k.identity)?.identity,
            );
          }
        });
      },
    },
    state.restoring && field("Zaszyfrowana kopia", backup),
    field("Has\u0142o skarbca", pass),
    h(
      "button",
      { type: "submit", class: "btn primary", disabled: state.busy },
      state.busy
        ? "Sprawdzanie\u2026"
        : state.restoring
          ? "Sprawd\u017A kopi\u0119 bez zast\u0119powania"
          : "Odblokuj lokalnie",
    ),
  );
  mount(
    root,
    ...header(),
    form,
    state.has &&
      btn(
        state.restoring
          ? "Mam skarbiec: wr\xF3\u0107 do odblokowania"
          : "Wczytaj kopi\u0119 zapasow\u0105",
        async () => {
          state.restoring = !state.restoring;
          state.error = null;
        },
      ),
    h(
      "details",
      {},
      h("summary", {}, "Nie pami\u0119tam has\u0142a lub nie mam kluczy"),
      h(
        "p",
        {},
        "Serwer nie zna has\u0142a i nie mo\u017Ce go zresetowa\u0107. Sprawd\u017A kopi\u0119, inn\u0105 przegl\u0105dark\u0119 lub inne nadal uprawnione klucze. Nowa to\u017Csamo\u015B\u0107 nie jest odzyskaniem starej.",
      ),
    ),
    h(
      "div",
      { class: "actions" },
      h("a", { class: "btn", href: "/studio" }, "Przegl\u0105daj bez kluczy"),
      h("a", { class: "btn", href: "/join" }, "Nowa to\u017Csamo\u015B\u0107"),
    ),
  );
}
function review() {
  const restored = state.restored;
  if (!restored) return;
  const risk = h("input", { id: "restore-risk", type: "checkbox" });
  const typed = h("input", {
    id: "restore-confirm",
    autocomplete: "off",
    placeholder: state.has ? "ZAST\u0104P" : "",
    required: state.has,
  });
  const lost = state.old?.keys.filter((k) => !restored.get(k.id)) || [];
  const copy = h("input", {
    id: "old-backup-saved",
    type: "checkbox",
    disabled: !state.backupDownloaded,
  });
  const submit = h(
    "button",
    {
      id: "restore-save",
      type: "submit",
      class: "btn danger",
      disabled: state.busy,
    },
    state.has ? "Zast\u0105p lokalny skarbiec" : "Zapisz skarbiec lokalnie",
  );
  mount(
    root,
    ...header(),
    h(
      "section",
      { class: "panel" },
      h("h2", {}, "Kopia zosta\u0142a sprawdzona"),
      h("p", {}, "Klucze w kopii: " + restored.keys.length),
      h(
        "ul",
        { class: "res-list" },
        restored.keys.map((k) =>
          h(
            "li",
            {},
            k.kind === "signing" ? "Sygnowanie: " : "Autoryzacja: ",
            h("code", {}, k.id),
          ),
        ),
      ),
      state.has &&
        notice(
          state.old
            ? lost.length
              ? "Klucze nieobecne w kopii: " +
                lost.map((k) => k.label || short(k.id)).join(", ")
              : "W kopii s\u0105 wszystkie por\xF3wnane klucze."
            : "Obecny skarbiec jest zablokowany. Nie znamy jego zawarto\u015Bci i nie mo\u017Cemy por\xF3wna\u0107 kluczy.",
          "warn",
        ),
      state.has &&
        !state.old &&
        btn("Odblokuj obecny skarbiec do por\xF3wnania", async () => {
          state.old = (await unlockDialog()) || null;
        }),
      state.old &&
        btn("Pobierz kopi\u0119 obecnego skarbca", async () => {
          download(
            "oktavarium-przed-przywroceniem.json",
            await state.old.backupFile(),
          );
          state.backupDownloaded = true;
        }),
    ),
    h(
      "form",
      {
        id: "restore-review",
        class: "stack",
        onsubmit: (e) => {
          e.preventDefault();
          if (state.has && typed.value !== "ZAST\u0104P") {
            state.error =
              "Wpisz ZAST\u0104P, aby potwierdzi\u0107 zast\u0105pienie.";
            render();
            return;
          }
          if (state.has && !risk.checked && !copy.checked) {
            state.error =
              "Potwierd\u017A zachowanie kopii albo ryzyko utraty obecnych lokalnych kluczy.";
            render();
            return;
          }
          run(async () => {
            await restored.save();
            rememberVault(restored);
            await enterStudio(
              restored,
              ref || restored.keys.find((k) => k.identity)?.identity || null,
            );
          });
        },
      },
      state.has &&
        h(
          "label",
          { class: "check" },
          copy,
          " Zapisano kopi\u0119 obecnego skarbca w bezpiecznym miejscu.",
        ),
      state.has &&
        h(
          "label",
          { class: "check" },
          risk,
          " Rozumiem ryzyko utraty kluczy, kt\xF3rych nie ma w przywracanej kopii.",
        ),
      state.has && field("Potwierdzenie zast\u0105pienia", typed),
      notice(
        "To lokalna operacja. Nie odwo\u0142uje kluczy na serwerze i nie przywraca usuni\u0119tych bajt\xF3w publikacji.",
      ),
      submit,
    ),
    btn("Anuluj bez zast\u0119powania", async () => {
      state.restored = null;
      state.error = null;
      state.backupDownloaded = false;
    }),
  );
}
(async () => {
  state.has = await hasVault();
  if (!state.has) state.restoring = true;
  render();
})().catch((e) =>
  mount(root, h("h1", {}, "Skarbiec"), notice(failure(e).message, "bad")),
);
