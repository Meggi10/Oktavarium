import { Vault, hasVault } from "./keystore.js";
import { h, field, notice, modal } from "./ui.js";

export async function unlockDialog() {
  if (!(await hasVault()))
    return modal("Brak skarbca w tej przeglądarce", (box, done) => {
      box.append(
        h(
          "p",
          {},
          "Odczyt działa bez kluczy. Do zapisu przywróć kopię albo utwórz tożsamość.",
        ),
        h("a", { class: "btn", href: "/login?restore=1" }, "Przywróć kopię"),
        h("a", { class: "btn", href: "/join" }, "Nowa tożsamość"),
        h(
          "button",
          { class: "btn", type: "button", onclick: () => done(false) },
          "Wróć do odczytu",
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
        "Hasło nie jest wysyłane. Odblokowanie nie tworzy sesji przesyłania i niczego nie podpisuje.",
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
              error.replaceChildren(notice(err.message, "bad"));
              submit.disabled = false;
            }
          },
        },
        field("Hasło skarbca", pass),
        error,
        submit,
      ),
      h("a", { href: "/login?restore=1" }, "Przywracanie i pomoc z dostępem"),
    );
  });
}
