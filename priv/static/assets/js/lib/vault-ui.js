import { failure } from "./failure.js";
import { Vault, hasVault } from "./keystore.js";
import { h, field, notice, modal } from "./ui.js";
async function unlockDialog() {
  if (!(await hasVault()))
    return modal("Brak skarbca w tej przegl\u0105darce", (box, done) => {
      box.append(
        h(
          "p",
          {},
          "Odczyt dzia\u0142a bez kluczy. Do zapisu przywr\xF3\u0107 kopi\u0119 albo utw\xF3rz to\u017Csamo\u015B\u0107.",
        ),
        h(
          "a",
          { class: "btn", href: "/login?restore=1" },
          "Przywr\xF3\u0107 kopi\u0119",
        ),
        h(
          "a",
          { class: "btn", href: "/join" },
          "Nowa to\u017Csamo\u015B\u0107",
        ),
        h(
          "button",
          { class: "btn", type: "button", onclick: () => done(false) },
          "Wr\xF3\u0107 do odczytu",
        ),
      );
    });
  return modal("Odblokuj klucze lokalnie", (box, done) => {
    const pass = h("input", {
      id: "unlock-pass",
      type: "password",
      required: true,
      autocomplete: "current-password",
    });
    const error = h("div", { role: "alert" });
    const submit = h(
      "button",
      { type: "submit", class: "btn primary" },
      "Odblokuj",
    );
    box.append(
      h(
        "p",
        {},
        "Has\u0142o nie jest wysy\u0142ane. Odblokowanie nie tworzy sesji przesy\u0142ania i niczego nie podpisuje.",
      ),
      h(
        "form",
        {
          class: "stack",
          onsubmit: async (e) => {
            e.preventDefault();
            if (submit.disabled) return;
            submit.disabled = true;
            try {
              const vault = await Vault.unlock(pass.value);
              pass.value = "";
              done(vault);
            } catch (err) {
              error.replaceChildren(notice(failure(err).message, "bad"));
              submit.disabled = false;
            }
          },
        },
        field("Has\u0142o skarbca", pass),
        error,
        submit,
      ),
      h(
        "a",
        { href: "/login?restore=1" },
        "Przywracanie i pomoc z dost\u0119pem",
      ),
    );
  });
}
export { unlockDialog };
