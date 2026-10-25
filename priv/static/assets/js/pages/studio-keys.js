import { h, field, download, ask } from "../lib/ui.js";
import { generateKey } from "../lib/crypto.js";
import { cliKeyfile } from "../lib/keystore.js";
import { copyButton } from "../lib/copy-id.js";
import { short } from "../lib/bytes.js";
function createKeySections({ state, act, say }) {
  function keysSection(d) {
    const label = h("input", {
      id: "k-label",
      maxlength: 40,
      placeholder: "np. laptop, bot-wydawca",
    });
    const pasted = h("input", {
      id: "k-pasted",
      autocomplete: "off",
      placeholder: "id klucza z innej przegl\u0105darki",
    });
    const authLabel = h("input", {
      id: "ak-label",
      maxlength: 40,
      placeholder: "np. telefon",
    });
    const addDevice = async (e) => {
      e.preventDefault();
      const vault = state.vault;
      if (!vault) throw new Error("Odblokuj skarbiec.");
      let id = pasted.value.trim();
      if (!id) {
        const created = await generateKey(
          "signing",
          label.value.trim() || "urz\u0105dzenie",
        );
        id = created.id;
        pasted.value = id;
        vault.add(created);
        await vault.save();
      }
      const body = { key: id };
      if (label.value.trim()) body.label = label.value.trim();
      await act("key.add", body);
    };
    let stagedAuth = null;
    const addAuth = async (e) => {
      e.preventDefault();
      const vault = state.vault;
      if (!vault) throw new Error("Odblokuj skarbiec.");
      const created =
        stagedAuth ||
        (await generateKey("auth", authLabel.value.trim() || "upload"));
      stagedAuth = created;
      vault.add(created);
      await vault.save();
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
        "Klucz za\u0142o\u017Cycielski podpisuje i nadaje uprawnienia. Klucze autoryzacji uwierzytelniaj\u0105 wysy\u0142anie plik\xF3w; odczyt Pracowni jest publiczny. Klucze urz\u0105dze\u0144 i bot\xF3w dopisujesz tu, a ich uprawnienia daj\u0105 granty.",
      ),
      h(
        "dl",
        { class: "facts" },
        h(
          "div",
          {},
          h("dt", {}, "Klucz za\u0142o\u017Cycielski"),
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
                ? h("span", { class: "tag bad" }, "cofni\u0119ty")
                : state.vault?.get(k.key_id) &&
                    h("span", { class: "tag" }, "w tej przegl\u0105darce"),
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
        field(
          "Nowy klucz logowania (powstaje tu, trafia do skarbca)",
          authLabel,
        ),
        h("button", { class: "btn", type: "submit", id: "add-auth" }, "Dodaj"),
      ),
      h("h3", {}, "Klucze urz\u0105dze\u0144 i bot\xF3w"),
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
                    h("span", { class: "tag bad" }, "cofni\u0119ty"),
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
            "Albo wklej id istniej\u0105cego klucza",
            pasted,
            "Puste = wygeneruj nowy klucz w tej przegl\u0105darce.",
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
  function backupSection() {
    const vault = state.vault;
    if (!vault)
      return h("p", {}, "Odblokuj skarbiec, aby pobra\u0107 kopi\u0119.");
    return h(
      "section",
      { class: "panel", "aria-labelledby": "backup-h" },
      h("h2", { id: "backup-h" }, "Kopie zapasowe i eksport"),
      h(
        "p",
        { class: "section-note" },
        "Skarbiec jest szyfrowany Twoim has\u0142em. Kopia zapasowa to ten sam zaszyfrowany plik: bez niego i bez has\u0142a klucze przepadn\u0105 z przegl\u0105dark\u0105.",
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
                `oktavarium-kopia-${/* @__PURE__ */ new Date().toISOString().slice(0, 10)}.json`,
                await vault.backupFile(),
              ),
          },
          "Pobierz zaszyfrowan\u0105 kopi\u0119",
        ),
        h(
          "details",
          { class: "danger" },
          h("summary", {}, "Eksport klucza do CLI (jawny plik)"),
          h(
            "p",
            { class: "muted" },
            "Plik zawiera klucz prywatny bez szyfrowania, w formacie `mix oktavarium.key.gen`. Kto go ma, mo\u017Ce podpisywa\u0107 jako ten klucz.",
          ),
          vault.keys.map((k) =>
            h(
              "button",
              {
                class: "btn small",
                type: "button",
                onclick: async () =>
                  (await ask(
                    "Eksport jawnego klucza",
                    "Ten plik nie jest szyfrowany. Nie udost\u0119pniaj go innym.",
                    "Eksportuj",
                  )) &&
                  download(
                    `${k.kind}-${short(k.id).replace("\u2026", "-")}.key`,
                    await cliKeyfile(k),
                  ),
              },
              `${k.kind} \xB7 ${short(k.id)}`,
            ),
          ),
        ),
      ),
    );
  }
  return { keysSection, backupSection };
}
export { createKeySections };
