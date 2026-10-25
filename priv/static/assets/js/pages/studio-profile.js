import { failure } from "../lib/failure.js";
import { h, field, notice } from "../lib/ui.js";
import { copyButton } from "../lib/copy-id.js";
import { fileResource } from "../lib/permissions.js";
import { AVATAR_PATH, avatarMediaType } from "../lib/avatar.js";
const PROFILE_FIELDS = [
  ["display_name", "Nazwa wy\u015Bwietlana", "input"],
  ["bio", "Opis", "textarea"],
  ["location", "Miejsce", "input"],
  ["website", "Strona (https://...)", "input"],
];
function createProfileSections({ can, act, publishFile, say, label }) {
  function profileSection(d) {
    const inputs = Object.fromEntries(
      PROFILE_FIELDS.map(([name, , kind]) => [
        name,
        kind === "textarea"
          ? h(
              "textarea",
              { id: "p-" + name, rows: 5, maxlength: 2e3 },
              d.profile[name] || "",
            )
          : h("input", {
              id: "p-" + name,
              value: d.profile[name] || "",
              maxlength: name === "website" ? 200 : 80,
            }),
      ]),
    );
    const allowedFields = PROFILE_FIELDS.filter(([name]) =>
      can("profile.update", d.id + "/profile/" + name),
    ).map(([name]) => name);
    return h(
      "section",
      { class: "panel", "aria-labelledby": "profile-h" },
      h("h2", { id: "profile-h" }, "Profil"),
      h("p", { class: "hint" }, "ID to\u017Csamo\u015Bci: ", copyButton(d.id)),
      h(
        "p",
        { class: "hint" },
        allowedFields.length === PROFILE_FIELDS.length
          ? "Mo\u017Cesz edytowa\u0107 profil. Ka\u017Cda zmiana wymaga osobnego podpisu."
          : "Mo\u017Cesz przygotowa\u0107 szkic. Zapis wymaga uprawnienia do ka\u017Cdego zmienionego pola; zmiana klucza nie zmienia to\u017Csamo\u015Bci.",
      ),
      h(
        "form",
        {
          class: "stack",
          onsubmit: async (e) => {
            e.preventDefault();
            const fields = {};
            for (const [name] of PROFILE_FIELDS) {
              const value = inputs[name].value.trim();
              const before = d.profile[name] ?? "";
              if (value !== before) fields[name] = value === "" ? null : value;
            }
            if (Object.keys(fields).length === 0) {
              return say("Nic si\u0119 nie zmieni\u0142o.");
            }
            const missing = Object.keys(fields).filter(
              (name) => !can("profile.update", d.id + "/profile/" + name),
            );
            if (missing.length) {
              return say(
                "Ten klucz nie mo\u017Ce zmieni\u0107 p\xF3l: " +
                  missing
                    .map(
                      (name) =>
                        PROFILE_FIELDS.find((f) => f[0] === name)?.[1] || name,
                    )
                    .join(", ") +
                  ". Wybierz uprawniony klucz; szkic pozostaje w formularzu.",
                "warn",
              );
            }
            await act("profile.update", { fields });
          },
        },
        PROFILE_FIELDS.map(([name, label2]) =>
          field(
            label2,
            inputs[name],
            allowedFields.includes(name)
              ? void 0
              : "Do podpisania tego pola potrzebny jest inny klucz lub grant.",
          ),
        ),
        h(
          "div",
          { class: "actions" },
          h(
            "button",
            { class: "btn primary", type: "submit", id: "save-profile" },
            "Podpisz i zapisz profil",
          ),
        ),
      ),
    );
  }
  function avatarSection(d) {
    const file = h("input", {
      id: "avatar-file",
      type: "file",
      accept: "image/png,image/jpeg,image/webp",
    });
    const status = h(
      "p",
      { class: "hint", role: "status" },
      "Wyb\xF3r zdj\u0119cia niczego nie wysy\u0142a. Maksymalnie 10 MiB.",
    );
    file.addEventListener("change", () => {
      const selected = file.files?.[0];
      status.textContent = selected
        ? "Przygotowano: " +
          selected.name +
          " (" +
          selected.size +
          " B). Niczego nie wys\u0142ano."
        : "Nie wybrano pliku.";
    });
    const authorized = can(
      "resource.put",
      fileResource(d.id, AVATAR_PATH, null),
    );
    return h(
      "section",
      { class: "panel profile-avatar", "aria-labelledby": "avatar-h" },
      h("h2", { id: "avatar-h" }, "Zdj\u0119cie profilowe"),
      h(
        "div",
        { class: "avatar-editor" },
        d.avatar_url
          ? h("img", {
              class: "avatar avatar-large avatar-photo",
              src: d.avatar_url,
              alt: "Bie\u017C\u0105ce zdj\u0119cie profilowe",
            })
          : h(
              "span",
              { class: "avatar avatar-large", "aria-hidden": "true" },
              (
                label(d).replace(/^@/, "").trim().slice(0, 1) || "O"
              ).toUpperCase(),
            ),
        h(
          "div",
          {},
          h(
            "p",
            {},
            "Obraz jest zasobem w przestrzeni g\u0142\xF3wnej (images/avatar). Jego aktualizacja zachowuje ID.",
          ),
          h(
            "p",
            { class: "hint" },
            "Publikacja wymaga uprawnienia resource.put dla tej \u015Bcie\u017Cki; nie wynika automatycznie z prawa do edycji opisu.",
          ),
        ),
      ),
      h(
        "form",
        {
          class: "stack",
          id: "avatar-upload",
          onsubmit: async (e) => {
            e.preventDefault();
            const selected = file.files?.[0];
            if (!selected)
              return say("Wybierz zdj\u0119cie profilowe.", "warn");
            try {
              const mediaType = avatarMediaType(selected);
              if (!can("resource.put", fileResource(d.id, AVATAR_PATH, null)))
                return say(
                  "Ten klucz nie mo\u017Ce publikowa\u0107 zdj\u0119cia profilowego. Potrzebne jest resource.put na images/avatar w przestrzeni g\u0142\xF3wnej.",
                  "warn",
                );
              await publishFile(selected, {
                path: AVATAR_PATH,
                project_id: null,
                media_type: mediaType,
                meta: {
                  title: "Zdj\u0119cie profilowe",
                  alt: "Zdj\u0119cie profilowe " + label(d),
                },
              });
            } catch (err) {
              say(failure(err).message, "bad");
            }
          },
        },
        field("Nowe zdj\u0119cie", file),
        status,
        h(
          "button",
          {
            type: "submit",
            class: "btn primary",
            id: "save-avatar",
            disabled: !authorized,
          },
          "Sprawd\u017A i opublikuj zdj\u0119cie",
        ),
        !authorized &&
          notice(
            "Wybrany klucz nie posiada uprawnienia do publikacji zdj\u0119cia. Wybierz klucz z odpowiednim grantem.",
            "warn",
          ),
      ),
    );
  }
  function visibilitySection(d) {
    const visibility = h(
      "select",
      { id: "i-visibility" },
      h(
        "option",
        { value: "public", selected: d.visibility === "public" },
        "Publiczna (w katalogu)",
      ),
      h(
        "option",
        { value: "unlisted", selected: d.visibility === "unlisted" },
        "Nieindeksowana (tylko z linku)",
      ),
    );
    return h(
      "section",
      { class: "panel", "aria-labelledby": "visibility-h" },
      h("h2", { id: "visibility-h" }, "Widoczno\u015B\u0107"),
      h(
        "p",
        { class: "muted" },
        "Nieindeksowana to\u017Csamo\u015B\u0107 nie pojawia si\u0119 w katalogu ani galerii. Profil, historia, pliki i w\u0142asna strona nadal s\u0105 dost\u0119pne z bezpo\u015Bredniego adresu.",
      ),
      h(
        "form",
        {
          class: "stack",
          onsubmit: async (e) => {
            e.preventDefault();
            if (visibility.value === d.visibility)
              return say("Widoczno\u015B\u0107 si\u0119 nie zmieni\u0142a.");
            await act("identity.visibility.set", {
              visibility: visibility.value,
            });
          },
        },
        field("Widoczno\u015B\u0107 profilu", visibility),
        h(
          "div",
          { class: "actions" },
          h(
            "button",
            { class: "btn primary", type: "submit", id: "save-visibility" },
            "Podpisz zmian\u0119 widoczno\u015Bci",
          ),
        ),
      ),
    );
  }
  return { profileSection, avatarSection, visibilitySection };
}
export { createProfileSections };
