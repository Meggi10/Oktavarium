import { failure } from "../lib/failure.js";
import { h, field, notice } from "../lib/ui.js";
import { copyButton } from "../lib/copy-id.js";
import { fileResource } from "../lib/permissions.js";
import { AVATAR_PATH, avatarMediaType } from "../lib/avatar.js";
import type { IdentityDetails } from "../lib/models.js";

const PROFILE_FIELDS = [
  ["display_name", "Nazwa wyświetlana", "input"],
  ["bio", "Opis", "textarea"],
  ["location", "Miejsce", "input"],
  ["website", "Strona (https://...)", "input"],
];

export function createProfileSections({
  can,
  act,
  publishFile,
  say,
  label,
}: {
  can: (action: string, resource: string) => boolean;
  act: (type: string, body: Record<string, unknown>) => Promise<boolean>;
  publishFile: (
    file: File,
    fields: {
      path: string;
      project_id: string | null;
      media_type: string;
      meta: Record<string, string>;
    },
  ) => Promise<boolean>;
  say: (message: string, kind?: string) => void;
  label: (identity: IdentityDetails) => string;
}) {
  // profil

  function profileSection(d: IdentityDetails) {
    const inputs = Object.fromEntries(
      PROFILE_FIELDS.map(([name, , kind]) => [
        name,
        kind === "textarea"
          ? h(
              "textarea",
              { id: "p-" + name, rows: 5, maxlength: 2000 },
              d.profile[name] || "",
            )
          : h("input", {
              id: "p-" + name,
              value: d.profile[name] || "",
              maxlength: name === "website" ? 200 : 80,
            }),
      ]),
    );

    // Editing a draft is never an authorization decision. Validate the actual
    // changed fields before any signature; the server is authoritative as well.
    const allowedFields = PROFILE_FIELDS.filter(([name]) =>
      can("profile.update", d.id + "/profile/" + name),
    ).map(([name]) => name);
    return h(
      "section",
      { class: "panel", "aria-labelledby": "profile-h" },
      h("h2", { id: "profile-h" }, "Profil"),
      h("p", { class: "hint" }, "ID tożsamości: ", copyButton(d.id)),
      h(
        "p",
        { class: "hint" },
        allowedFields.length === PROFILE_FIELDS.length
          ? "Możesz edytować profil. Każda zmiana wymaga osobnego podpisu."
          : "Możesz przygotować szkic. Zapis wymaga uprawnienia do każdego zmienionego pola; zmiana klucza nie zmienia tożsamości.",
      ),
      h(
        "form",
        {
          class: "stack",
          onsubmit: async (e) => {
            e.preventDefault();
            const fields: Record<string, string | null> = {};
            for (const [name] of PROFILE_FIELDS) {
              const value = inputs[name].value.trim();
              const before = d.profile[name] ?? "";
              if (value !== before) fields[name] = value === "" ? null : value;
            }
            if (Object.keys(fields).length === 0) {
              return say("Nic się nie zmieniło.");
            }
            const missing = Object.keys(fields).filter(
              (name) => !can("profile.update", d.id + "/profile/" + name),
            );
            if (missing.length) {
              return say(
                "Ten klucz nie może zmienić pól: " +
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
        PROFILE_FIELDS.map(([name, label]) =>
          field(
            label,
            inputs[name],
            allowedFields.includes(name)
              ? undefined
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

  function avatarSection(d: IdentityDetails) {
    const file = h("input", {
      id: "avatar-file",
      type: "file",
      accept: "image/png,image/jpeg,image/webp",
    });
    const status = h(
      "p",
      { class: "hint", role: "status" },
      "Wybór zdjęcia niczego nie wysyła. Maksymalnie 10 MiB.",
    );
    file.addEventListener("change", () => {
      const selected = file.files?.[0];
      status.textContent = selected
        ? "Przygotowano: " +
          selected.name +
          " (" +
          selected.size +
          " B). Niczego nie wysłano."
        : "Nie wybrano pliku.";
    });
    const authorized = can(
      "resource.put",
      fileResource(d.id, AVATAR_PATH, null),
    );
    return h(
      "section",
      { class: "panel profile-avatar", "aria-labelledby": "avatar-h" },
      h("h2", { id: "avatar-h" }, "Zdjęcie profilowe"),
      h(
        "div",
        { class: "avatar-editor" },
        d.avatar_url
          ? h("img", {
              class: "avatar avatar-large avatar-photo",
              src: d.avatar_url,
              alt: "Bieżące zdjęcie profilowe",
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
            "Obraz jest zasobem w przestrzeni głównej (images/avatar). Jego aktualizacja zachowuje ID.",
          ),
          h(
            "p",
            { class: "hint" },
            "Publikacja wymaga uprawnienia resource.put dla tej ścieżki; nie wynika automatycznie z prawa do edycji opisu.",
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
            if (!selected) return say("Wybierz zdjęcie profilowe.", "warn");
            try {
              const mediaType = avatarMediaType(selected);
              if (!can("resource.put", fileResource(d.id, AVATAR_PATH, null)))
                return say(
                  "Ten klucz nie może publikować zdjęcia profilowego. Potrzebne jest resource.put na images/avatar w przestrzeni głównej.",
                  "warn",
                );
              await publishFile(selected, {
                path: AVATAR_PATH,
                project_id: null,
                media_type: mediaType,
                meta: {
                  title: "Zdjęcie profilowe",
                  alt: "Zdjęcie profilowe " + label(d),
                },
              });
            } catch (err) {
              say(failure(err).message, "bad");
            }
          },
        },
        field("Nowe zdjęcie", file),
        status,
        h(
          "button",
          {
            type: "submit",
            class: "btn primary",
            id: "save-avatar",
            disabled: !authorized,
          },
          "Sprawdź i opublikuj zdjęcie",
        ),
        !authorized &&
          notice(
            "Wybrany klucz nie posiada uprawnienia do publikacji zdjęcia. Wybierz klucz z odpowiednim grantem.",
            "warn",
          ),
      ),
    );
  }

  // Widoczność nie jest częścią profilu: zawsze zmieniamy ją podpisanym zdarzeniem.
  function visibilitySection(d: IdentityDetails) {
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
      h("h2", { id: "visibility-h" }, "Widoczność"),
      h(
        "p",
        { class: "muted" },
        "Nieindeksowana tożsamość nie pojawia się w katalogu ani galerii. Profil, historia, pliki i własna strona nadal są dostępne z bezpośredniego adresu.",
      ),
      h(
        "form",
        {
          class: "stack",
          onsubmit: async (e) => {
            e.preventDefault();
            if (visibility.value === d.visibility)
              return say("Widoczność się nie zmieniła.");
            await act("identity.visibility.set", {
              visibility: visibility.value,
            });
          },
        },
        field("Widoczność profilu", visibility),
        h(
          "div",
          { class: "actions" },
          h(
            "button",
            { class: "btn primary", type: "submit", id: "save-visibility" },
            "Podpisz zmianę widoczności",
          ),
        ),
      ),
    );
  }

  return { profileSection, avatarSection, visibilitySection };
}
