import { h, field, download, ask } from "../lib/ui.js";
import { generateKey } from "../lib/crypto.js";
import { cliKeyfile, type Vault, type VaultKey } from "../lib/keystore.js";
import { copyButton } from "../lib/copy-id.js";
import { short } from "../lib/bytes.js";
import type { IdentityDetails } from "../lib/models.js";

export function createKeySections({
  state,
  act,
  say,
}: {
  state: { vault: Vault | null };
  act: (type: string, body: Record<string, unknown>) => Promise<boolean>;
  say: (message: string, kind?: string) => void;
}) {
  // klucze

  function keysSection(d: IdentityDetails) {
    const label = h("input", {
      id: "k-label",
      maxlength: 40,
      placeholder: "np. laptop, bot-wydawca",
    });
    const pasted = h("input", {
      id: "k-pasted",
      autocomplete: "off",
      placeholder: "id klucza z innej przeglądarki",
    });
    const authLabel = h("input", {
      id: "ak-label",
      maxlength: 40,
      placeholder: "np. telefon",
    });

    const addDevice = async (e: Event) => {
      e.preventDefault();
      const vault = state.vault;
      if (!vault) throw new Error("Odblokuj skarbiec.");
      let id = pasted.value.trim();
      if (!id) {
        const created = await generateKey(
          "signing",
          label.value.trim() || "urządzenie",
        );
        id = created.id;
        pasted.value = id;
        vault.add(created);
        await vault.save();
      }
      const body: { key: string; label?: string } = { key: id };
      if (label.value.trim()) body.label = label.value.trim();
      await act("key.add", body);
    };

    let stagedAuth: VaultKey | null = null;
    const addAuth = async (e: Event) => {
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
        "Klucz założycielski podpisuje i nadaje uprawnienia. Klucze autoryzacji uwierzytelniają wysyłanie plików; odczyt Pracowni jest publiczny. Klucze urządzeń i botów dopisujesz tu, a ich uprawnienia dają granty.",
      ),
      h(
        "dl",
        { class: "facts" },
        h(
          "div",
          {},
          h("dt", {}, "Klucz założycielski"),
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
                ? h("span", { class: "tag bad" }, "cofnięty")
                : state.vault?.get(k.key_id) &&
                    h("span", { class: "tag" }, "w tej przeglądarce"),
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
      h("h3", {}, "Klucze urządzeń i botów"),
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
                    h("span", { class: "tag bad" }, "cofnięty"),
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
            "Albo wklej id istniejącego klucza",
            pasted,
            "Puste = wygeneruj nowy klucz w tej przeglądarce.",
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

  // kopie zapasowe

  function backupSection() {
    const vault = state.vault;
    if (!vault) return h("p", {}, "Odblokuj skarbiec, aby pobrać kopię.");
    return h(
      "section",
      { class: "panel", "aria-labelledby": "backup-h" },
      h("h2", { id: "backup-h" }, "Kopie zapasowe i eksport"),
      h(
        "p",
        { class: "section-note" },
        "Skarbiec jest szyfrowany Twoim hasłem. Kopia zapasowa to ten sam zaszyfrowany plik: bez niego i bez hasła klucze przepadną z przeglądarką.",
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
                `oktavarium-kopia-${new Date().toISOString().slice(0, 10)}.json`,
                await vault.backupFile(),
              ),
          },
          "Pobierz zaszyfrowaną kopię",
        ),
        h(
          "details",
          { class: "danger" },
          h("summary", {}, "Eksport klucza do CLI (jawny plik)"),
          h(
            "p",
            { class: "muted" },
            "Plik zawiera klucz prywatny bez szyfrowania, w formacie `mix oktavarium.key.gen`. Kto go ma, może podpisywać jako ten klucz.",
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
                    "Ten plik nie jest szyfrowany. Nie udostępniaj go innym.",
                    "Eksportuj",
                  )) &&
                  download(
                    `${k.kind}-${short(k.id).replace("…", "-")}.key`,
                    await cliKeyfile(k),
                  ),
              },
              `${k.kind} · ${short(k.id)}`,
            ),
          ),
        ),
      ),
    );
  }

  return { keysSection, backupSection };
}
