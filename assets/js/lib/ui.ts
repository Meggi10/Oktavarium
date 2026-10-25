import { copyButton } from "./copy-id.js";
import type { IdentityDetails } from "./models.js";

type SummaryContext = {
  data?: Pick<
    Partial<IdentityDetails>,
    "projects" | "resources" | "profile" | "handle"
  >;
};

// Minimalne pomocniki DOM. Cała treść trafia przez `textContent`, nigdy `innerHTML`,
// więc dane z serwera i od innych użytkowników nie mogą wstrzyknąć znaczników.

type UiAttrs = Record<string, any> & {
  onclick?: (event: any) => unknown;
  onsubmit?: (event: any) => unknown;
  onchange?: (event: any) => unknown;
  oninput?: (event: any) => unknown;
  onerror?: (event: any) => unknown;
};

// Dynamic tags and attributes are contained here; form events enter through this adapter.
export function h(
  tag: string,
  attrs: UiAttrs = {},
  ...children: unknown[]
): any {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === false || v == null) continue;
    if (k === "class") el.className = [v].flat().filter(Boolean).join(" ");
    else if (k.startsWith("on") && typeof v === "function")
      el.addEventListener(k.slice(2), v);
    else if (
      k === "value" ||
      k === "checked" ||
      k === "disabled" ||
      k === "hidden"
    )
      (el as any)[k] = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  append(el, children);
  return el;
}

function append(el: Element, children: unknown[]) {
  for (const c of children.flat(Infinity)) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
}

export function mount(root: Element, ...children: unknown[]) {
  root.replaceChildren();
  append(root, children);
}

export const $ = (sel: string, root: ParentNode = document) =>
  root.querySelector(sel);

/** Pole formularza z etykietą. */
export function field(
  label: string,
  input: Node,
  hint: string | null | undefined = null,
) {
  return h(
    "label",
    { class: "field" },
    h("span", { class: "field-label" }, label),
    input,
    hint && h("span", { class: "hint" }, hint),
  );
}

export function notice(text: string, kind = "info") {
  return h(
    "p",
    { class: "notice " + kind, role: kind === "bad" ? "alert" : "status" },
    text,
  );
}

/** Pobranie pliku wygenerowanego w przeglądarce. */
export function download(
  name: string,
  content: unknown,
  type = "application/json",
) {
  const blob = new Blob(
    [typeof content === "string" ? content : JSON.stringify(content, null, 2)],
    { type },
  );
  const url = URL.createObjectURL(blob);
  const a = h("a", { href: url, download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

// Dialogs return consent, not a signature. Escape is always cancellation.
let dialogSerial = 0;
export function modal<T>(
  title: string,
  build: (body: HTMLDivElement, done: (result: T | false) => void) => void,
): Promise<T | false> {
  const trigger = document.activeElement;
  return new Promise<T | false>((resolve) => {
    const id = "dialog-title-" + ++dialogSerial;
    const dialog = h("dialog", { class: "sign-dialog", "aria-labelledby": id });
    let finished = false;
    const done = (result: T | false) => {
      if (finished) return;
      finished = true;
      dialog.close();
      dialog.remove();
      if (trigger?.isConnected) (trigger as HTMLElement).focus();
      else document.getElementById("main")?.focus();
      resolve(result);
    };
    dialog.append(
      h(
        "div",
        { class: "dialog-head" },
        h("h2", { id }, title),
        h(
          "button",
          {
            type: "button",
            class: "btn",
            "aria-label": "Zamknij",
            onclick: () => done(false),
          },
          "×",
        ),
      ),
    );
    const body = h("div", { class: "dialog-body" });
    dialog.append(body);
    build(body, done);
    dialog.addEventListener("cancel", (e: Event) => {
      e.preventDefault();
      done(false);
    });
    document.body.append(dialog);
    dialog.showModal();
  });
}

export const ACTION_LABELS = {
  "identity.genesis": "Utworzenie tożsamości",
  "profile.update": "Zmiana profilu",
  "identity.visibility.set": "Zmiana obecności w katalogu",
  "project.create": "Utworzenie projektu",
  "project.update": "Zmiana projektu",
  "project.delete": "Usunięcie pustego projektu",
  "resource.put": "Publikowanie i aktualizowanie plików",
  "resource.delete": "Usuwanie plików",
  "resource.*": "Zarządzanie plikami (także usuwanie)",
  "project.*": "Zarządzanie projektem",
  "grant.create": "Nadanie dostępu",
  "grant.revoke": "Cofnięcie dostępu",
  "key.add": "Dopisanie klucza sygnowania",
  "key.revoke": "Cofnięcie klucza sygnowania",
  "auth_key.add": "Dopisanie klucza autoryzacji",
  "auth_key.revoke": "Cofnięcie klucza autoryzacji",
  "*": "Wszystkie działania w zakresie",
};
const fieldNames = {
  display_name: "Nazwa wyświetlana",
  bio: "Opis",
  location: "Miejsce",
  website: "Strona",
  title: "Tytuł",
  description: "Opis",
  alt: "Tekst alternatywny",
  collection: "Kolekcja",
};
export const actionLabel = (type: string) =>
  (ACTION_LABELS as Record<string, string>)[type] || type;
const text = (v: unknown) =>
  v == null || v === ""
    ? "(brak)"
    : typeof v === "object"
      ? JSON.stringify(v)
      : String(v);

export function changeSummary(
  type: string,
  body: Record<string, any>,
  context: SummaryContext = {},
) {
  const d = context.data,
    project = d?.projects?.find((p) => p.id === (body.project_id || body.id));
  const file = d?.resources?.find((r) => r.id === body.id);
  const rows = [];
  if (body.fields)
    for (const [key, value] of Object.entries(body.fields))
      rows.push([
        (fieldNames as Record<string, string>)[key] || key,
        text(d?.profile?.[key]) + " → " + text(value),
      ]);
  if (body.meta)
    for (const [key, value] of Object.entries(body.meta))
      rows.push([
        (fieldNames as Record<string, string>)[key] || key,
        text(value),
      ]);
  if (body.kind)
    rows.push(["Rodzaj", body.kind === "collective" ? "Kolektyw" : "Osoba"]);
  if (body.handle) rows.push(["Uchwyt", "@" + body.handle]);
  if (body.visibility)
    rows.push([
      "Katalog",
      body.visibility === "unlisted"
        ? "Nieindeksowana; odczyt nadal publiczny"
        : "Widoczna w katalogu",
    ]);
  if (body.slug) rows.push(["Adres / slug", body.slug]);
  if (body.path || file) rows.push(["Plik", body.path || file?.path || ""]);
  if (type.startsWith("resource.")) {
    const targetId = Object.hasOwn(body, "project_id")
      ? body.project_id
      : file?.project_id;
    const target = d?.projects?.find((p) => p.id === targetId);
    rows.push([
      type === "resource.delete" ? "Miejsce usuwanego pliku" : "Cel",
      target ? target.meta.title || target.slug : "Przestrzeń główna",
    ]);
    if (file)
      rows.push([
        "Istniejący zasób",
        file.id + " (ID pozostaje przy aktualizacji)",
      ]);
    if (
      file &&
      ((body.path && body.path !== file.path) ||
        (Object.hasOwn(body, "project_id") &&
          body.project_id !== file.project_id))
    ) {
      const from = d?.projects?.find((p) => p.id === file.project_id);
      rows.push([
        "Przeniesienie ze źródła",
        (from?.meta.title || "Przestrzeń główna") + " / " + file.path,
      ]);
    }
  } else if (project)
    rows.push(["Projekt", project.meta.title || project.slug]);
  if (body.subject) rows.push(["Klucz odbiorcy", body.subject]);
  if (body.action) rows.push(["Dostęp", actionLabel(body.action)]);
  if (body.resource) rows.push(["Zakres", body.resource]);
  if (body.parent_grant) rows.push(["Grant nadrzędny", body.parent_grant]);
  if (type === "grant.create") {
    rows.push([
      "Przekazywanie dalej",
      body.delegable ? "Tak, tylko węższy zakres" : "Nie",
    ]);
    rows.push([
      "Do kiedy",
      body.expires_at
        ? new Date(body.expires_at * 1000).toLocaleString("pl-PL")
        : "Bez terminu",
    ]);
  }
  if (body.grant) rows.push(["Cofany grant", body.grant]);
  if (body.key) rows.push(["Klucz publiczny", body.key]);
  if (body.hash) rows.push(["SHA-256 pliku", body.hash]);
  return rows;
}
export function confirmSign({
  type,
  body,
  signer,
  identity,
  context = {},
}: {
  type: string;
  body: Record<string, any>;
  signer: { id: string; label?: string | null };
  identity?: string;
  context?: SummaryContext;
}) {
  const removal = type.endsWith(".delete") || type.endsWith(".revoke");
  const moving =
    type === "resource.put" &&
    body.id &&
    context.data?.resources?.some(
      (r) =>
        r.id === body.id &&
        (r.path !== body.path || r.project_id !== body.project_id),
    );
  const verb =
    type === "resource.put"
      ? moving
        ? "Podpisz i przenieś"
        : "Podpisz i opublikuj"
      : type === "grant.revoke"
        ? "Podpisz i cofnij dostęp"
        : removal
          ? "Podpisz usunięcie"
          : "Podpisz i zapisz";
  return modal("Sprawdź zmianę przed podpisem", (box, done) => {
    append(box, [
      h("p", { class: "eyebrow" }, actionLabel(type)),
      h(
        "dl",
        { class: "sign-meta" },
        ...[
          [
            "Tożsamość",
            context.data?.profile?.display_name ||
              context.data?.handle ||
              identity ||
              "Nowa tożsamość",
          ],
          ["Podpisujący klucz", (signer.label || "Klucz") + " · " + signer.id],
          ...changeSummary(type, body, context),
        ].map(([label, value]) =>
          h(
            "div",
            {},
            h("dt", {}, label),
            h(
              "dd",
              {},
              typeof value === "string" &&
                /SHA-256|klucz|identyfikator|grant/i.test(label) &&
                /^(?:[a-f0-9]{64}|[A-Za-z0-9_-]{43})$/.test(value)
                ? copyButton(value)
                : value,
            ),
          ),
        ),
      ),
      type === "resource.put" &&
        h(
          "p",
          { class: "notice warn" },
          "Aktualizacja może zastąpić istniejący plik. Bajty są wysyłane po tej zgodzie; publikację potwierdza dopiero przyjęcie zdarzenia.",
        ),
      type === "grant.create" &&
        body.action.includes("put") &&
        h(
          "p",
          { class: "notice warn" },
          "Publikowanie obejmuje także aktualizację cudzych plików w tym zakresie. Nie jest to wyłącznie dodawanie nowych.",
        ),
      removal &&
        h(
          "p",
          { class: "notice warn" },
          type === "grant.revoke"
            ? "Potomkowie utracą podstawę tej delegacji. Odczyt i dotychczasowe materiały pozostają dostępne."
            : "To nie jest fizyczne wymazanie historii ani bajtów ze wszystkich kopii.",
        ),
      h(
        "details",
        {},
        h("summary", {}, "Szczegóły techniczne"),
        h(
          "p",
          { class: "hint" },
          "Zamiar operacji przed zamianą tekstów na referencje SHA-256. To nie jest jeszcze podpisana koperta.",
        ),
        h(
          "pre",
          { class: "code" },
          JSON.stringify({ type, identity, body }, null, 2),
        ),
      ),
      h(
        "p",
        { class: "hint" },
        "Historia operacji pozostaje publiczna. Treści profilu i metadanych są powiązane ze skrótami; odczyt nie wymaga kluczy.",
      ),
      h(
        "div",
        { class: "actions" },
        h(
          "button",
          {
            id: "confirm-sign",
            type: "button",
            class: "btn " + (removal ? "danger" : "primary"),
            onclick: () => done(true),
          },
          verb,
        ),
        h(
          "button",
          {
            id: "cancel-sign",
            type: "button",
            class: "btn",
            onclick: () => done(false),
          },
          "Wróć do szkicu",
        ),
      ),
    ]);
  });
}

export function ask(title: string, message: string, label = "Potwierdź") {
  return modal(title, (box, done) =>
    box.append(
      h("p", {}, message),
      h(
        "div",
        { class: "actions" },
        h(
          "button",
          { type: "button", class: "btn primary", onclick: () => done(true) },
          label,
        ),
        h(
          "button",
          { type: "button", class: "btn", onclick: () => done(false) },
          "Anuluj",
        ),
      ),
    ),
  );
}
