import { h, field, actionLabel } from "../lib/ui.js";
import { copyButton } from "../lib/copy-id.js";
import { short } from "../lib/bytes.js";
import { delegatedBody, projectResource, active } from "../lib/permissions.js";

const ACTIONS = [
  "resource.put",
  "resource.delete",
  "resource.*",
  "project.update",
  "project.delete",
  "project.*",
  "*",
  "profile.update",
  "identity.visibility.set",
  "key.add",
  "key.revoke",
  "auth_key.add",
  "auth_key.revoke",
  "grant.revoke",
  "project.create",
];
const STATUS = {
  active: "aktywne",
  revoked: "cofnięte",
  expired: "wygasło",
  pending: "oczekuje",
  broken: "łańcuch przerwany",
};

export function grantsSection(
  d,
  { editable = true, access, selected, keys, signerId, act, say, can },
) {
  const known = new Map();
  for (const m of d.members)
    if (m.status === "active") known.set(m.key_id, m.label || "urządzenie");
  for (const k of keys)
    if (k.kind === "signing" && k.id !== d.founding_key)
      known.set(k.id, known.get(k.id) || k.label || "klucz lokalny");
  const subject = h(
    "select",
    { id: "g-subject" },
    [...known].map(([value, label]) =>
      h("option", { value }, label + " · " + short(value)),
    ),
    h("option", { value: "" }, "inny klucz (wpisz poniżej)"),
  );
  const other = h("input", {
    id: "g-other",
    autocomplete: "off",
    placeholder: "pełne id klucza sygnowania",
  });
  const action = h(
    "select",
    { id: "g-action" },
    ACTIONS.map((value) =>
      h(
        "option",
        {
          value,
          selected: value === (selected ? "resource.put" : "profile.update"),
        },
        actionLabel(value),
      ),
    ),
  );
  const scope = h(
    "select",
    { id: "g-project" },
    h(
      "option",
      { value: "", selected: !selected },
      "Tożsamość (zakres ręczny)",
    ),
    d.projects.map((p) =>
      h(
        "option",
        { value: p.id, selected: p.id === selected },
        p.meta.title || p.slug,
      ),
    ),
  );
  const resource = h("input", {
    id: "g-resource",
    value: selected ? "*" : "/profile/*",
    autocomplete: "off",
  });
  scope.addEventListener("change", () => {
    resource.value = scope.value ? "*" : "/profile/*";
  });
  const days = h("input", {
    id: "g-days",
    type: "number",
    min: 1,
    max: 3650,
    step: 1,
    placeholder: "dziedzicz / bez końca",
  });
  const delegable = h("input", { id: "g-delegable", type: "checkbox" });
  const parents = (access?.grants || []).filter(
    (g) => g.delegable && active(g),
  );
  const parent = h(
    "select",
    { id: "g-parent", disabled: Boolean(access?.founder) },
    h(
      "option",
      { value: "" },
      access?.founder ? "Klucz założycielski" : "Wybierz grant nadrzędny",
    ),
    parents.map((g) =>
      h(
        "option",
        { value: g.id },
        `${g.action} · ${g.resource} · ${short(g.id)}`,
      ),
    ),
  );
  const verified = h("input", {
    id: "g-verified",
    type: "checkbox",
    required: true,
  });
  subject.addEventListener("change", () => {
    verified.checked = false;
  });
  other.addEventListener("input", () => {
    verified.checked = false;
  });
  const form = h(
    "form",
    {
      id: "grant-create",
      class: "stack",
      onsubmit: async (e) => {
        e.preventDefault();
        try {
          const subj = other.value.trim() || subject.value;
          if (!verified.checked)
            return say(
              "Porównaj pełny identyfikator klucza odbiorcy i potwierdź go.",
              "bad",
            );
          if (!/^[A-Za-z0-9_-]{43}$/.test(subj))
            return say("Nieprawidłowy identyfikator klucza.", "bad");
          if (!subj) return say("Podaj klucz odbiorcy.", "bad");
          const suffix = resource.value.trim();
          if (!suffix || (!scope.value && !suffix.startsWith("/")))
            return say(
              "Zakres tożsamości zaczyna się od /; wewnątrz projektu użyj np. images/* lub *.",
              "bad",
            );
          const target = scope.value
            ? projectResource(d.id, scope.value) +
              (action.value.startsWith("project.") && suffix === "*"
                ? ""
                : "/" + suffix.replace(/^\/+/, ""))
            : d.id + suffix;
          const body = {
            subject: subj,
            action: action.value,
            resource: target,
            delegable: delegable.checked,
          };
          if (days.value)
            body.expires_at =
              Math.floor(Date.now() / 1000) + Number(days.value) * 86400;
          await act(
            "grant.create",
            delegatedBody(body, access, parent.value || null),
          );
        } catch (e) {
          say(e.message, "bad");
        }
      },
    },
    h(
      "div",
      { class: "grid2" },
      field("Komu", subject),
      field("Albo id klucza", other),
    ),
    h(
      "label",
      { class: "check" },
      verified,
      " Porównano pełny identyfikator z odbiorcą (nie tylko etykietę).",
    ),
    h(
      "div",
      { class: "grid2" },
      field("Co może", action),
      field("Projekt / tożsamość", scope),
    ),
    field(
      "Zakres",
      resource,
      "Projekt: * obejmuje cały projekt; images/* tylko obrazy. Uprawnienia nie są przypisane do nazwy projektu.",
    ),
    field(
      "Na podstawie grantu",
      parent,
      "Delegat musi wskazać własny aktywny grant z prawem dalszego przekazywania.",
    ),
    field(
      "Ważne przez dni",
      days,
      "Puste dziedziczy termin rodzica. Nie można go wydłużyć.",
    ),
    h("label", { class: "check" }, delegable, " może przekazywać dalej"),
    h(
      "button",
      {
        id: "grant",
        type: "submit",
        class: "btn primary",
        disabled: !access?.signing_key || (!access.founder && !parents.length),
      },
      "Nadaj uprawnienie",
    ),
  );
  const visibleGrants = selected
    ? d.grants.filter(
        (g) =>
          g.resource === d.id + "/*" ||
          g.resource === projectResource(d.id, selected) ||
          g.resource.startsWith(projectResource(d.id, selected) + "/"),
      )
    : d.grants;
  const rows = visibleGrants.length
    ? h(
        "table",
        { class: "grants" },
        h(
          "thead",
          {},
          h(
            "tr",
            {},
            ["Komu", "Co", "Gdzie", "Stan", ""].map((label) =>
              h("th", { scope: "col" }, label),
            ),
          ),
        ),
        h(
          "tbody",
          {},
          visibleGrants.map((g) => {
            const revoke =
              signerId === d.founding_key ||
              signerId === g.issuer_key_id ||
              can("grant.revoke", g.resource) ||
              can("grant.revoke", d.id + "/grants/" + g.id);
            return h(
              "tr",
              { class: "grant is-" + g.status, "data-grant-id": g.id },
              h(
                "td",
                { "data-label": "Klucz" },
                known.get(g.subject_key_id) &&
                  h(
                    "span",
                    { class: "hint" },
                    known.get(g.subject_key_id) + " ",
                  ),
                copyButton(g.subject_key_id),
              ),
              h("td", { "data-label": "Dostep" }, actionLabel(g.action)),
              h(
                "td",
                { "data-label": "Zakres" },
                h("code", {}, g.resource.slice(d.id.length)),
                g.parent_grant_id &&
                  h(
                    "p",
                    { class: "muted" },
                    "Rodzic: ",
                    copyButton(g.parent_grant_id),
                  ),
                g.expires_at &&
                  h("p", { class: "muted" }, "Do: ", g.expires_at),
              ),
              h("td", { "data-label": "Stan" }, STATUS[g.status] || g.status),
              h(
                "td",
                {},
                editable &&
                  g.status !== "revoked" &&
                  h(
                    "button",
                    {
                      type: "button",
                      class: "btn small",
                      disabled: !revoke,
                      onclick: () => act("grant.revoke", { grant: g.id }),
                    },
                    "Cofnij",
                  ),
              ),
            );
          }),
        ),
      )
    : h("p", { class: "muted" }, "Brak grantów.");
  return h(
    "section",
    { class: "panel", "aria-labelledby": "grants-h" },
    h("h2", { id: "grants-h" }, "Uprawnienia"),
    h(
      "p",
      { class: "section-note" },
      "resource.put publikuje; resource.delete usuwa i pozwala przenosić ze źródła. project.update zmienia projekt. * to administracja w wybranym zakresie. Nadawanie dalszych grantów wymaga delegable.",
    ),
    editable
      ? form
      : h(
          "p",
          { class: "hint" },
          "Odczyt grantów jest publiczny. Odblokuj klucz, aby nadać lub cofnąć dostęp.",
        ),
    rows,
  );
}
