import { copyButton } from "./copy-id.js";
function h(tag, attrs = {}, ...children) {
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
      el[k] = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  append(el, children);
  return el;
}
function append(el, children) {
  for (const c of children.flat(Infinity)) {
    if (c == null || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
}
function mount(root, ...children) {
  root.replaceChildren();
  append(root, children);
}
const $ = (sel, root = document) => root.querySelector(sel);
function field(label, input, hint = null) {
  return h(
    "label",
    { class: "field" },
    h("span", { class: "field-label" }, label),
    input,
    hint && h("span", { class: "hint" }, hint),
  );
}
function notice(text2, kind = "info") {
  return h(
    "p",
    { class: "notice " + kind, role: kind === "bad" ? "alert" : "status" },
    text2,
  );
}
function download(name, content, type = "application/json") {
  const blob = new Blob(
    [typeof content === "string" ? content : JSON.stringify(content, null, 2)],
    { type },
  );
  const url = URL.createObjectURL(blob);
  const a = h("a", { href: url, download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5e3);
}
let dialogSerial = 0;
function modal(title, build) {
  const trigger = document.activeElement;
  return new Promise((resolve) => {
    const id = "dialog-title-" + ++dialogSerial;
    const dialog = h("dialog", { class: "sign-dialog", "aria-labelledby": id });
    let finished = false;
    const done = (result) => {
      if (finished) return;
      finished = true;
      dialog.close();
      dialog.remove();
      if (trigger?.isConnected) trigger.focus();
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
          "\xD7",
        ),
      ),
    );
    const body = h("div", { class: "dialog-body" });
    dialog.append(body);
    build(body, done);
    dialog.addEventListener("cancel", (e) => {
      e.preventDefault();
      done(false);
    });
    document.body.append(dialog);
    dialog.showModal();
  });
}
const ACTION_LABELS = {
  "identity.genesis": "Utworzenie to\u017Csamo\u015Bci",
  "profile.update": "Zmiana profilu",
  "identity.visibility.set": "Zmiana obecno\u015Bci w katalogu",
  "project.create": "Utworzenie projektu",
  "project.update": "Zmiana projektu",
  "project.delete": "Usuni\u0119cie pustego projektu",
  "resource.put": "Publikowanie i aktualizowanie plik\xF3w",
  "resource.delete": "Usuwanie plik\xF3w",
  "resource.*": "Zarz\u0105dzanie plikami (tak\u017Ce usuwanie)",
  "project.*": "Zarz\u0105dzanie projektem",
  "grant.create": "Nadanie dost\u0119pu",
  "grant.revoke": "Cofni\u0119cie dost\u0119pu",
  "key.add": "Dopisanie klucza sygnowania",
  "key.revoke": "Cofni\u0119cie klucza sygnowania",
  "auth_key.add": "Dopisanie klucza autoryzacji",
  "auth_key.revoke": "Cofni\u0119cie klucza autoryzacji",
  "*": "Wszystkie dzia\u0142ania w zakresie",
};
const fieldNames = {
  display_name: "Nazwa wy\u015Bwietlana",
  bio: "Opis",
  location: "Miejsce",
  website: "Strona",
  title: "Tytu\u0142",
  description: "Opis",
  alt: "Tekst alternatywny",
  collection: "Kolekcja",
};
const actionLabel = (type) => ACTION_LABELS[type] || type;
const text = (v) =>
  v == null || v === ""
    ? "(brak)"
    : typeof v === "object"
      ? JSON.stringify(v)
      : String(v);
function changeSummary(type, body, context = {}) {
  const d = context.data,
    project = d?.projects?.find((p) => p.id === (body.project_id || body.id));
  const file = d?.resources?.find((r) => r.id === body.id);
  const rows = [];
  if (body.fields)
    for (const [key, value] of Object.entries(body.fields))
      rows.push([
        fieldNames[key] || key,
        text(d?.profile?.[key]) + " \u2192 " + text(value),
      ]);
  if (body.meta)
    for (const [key, value] of Object.entries(body.meta))
      rows.push([fieldNames[key] || key, text(value)]);
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
      target
        ? target.meta.title || target.slug
        : "Przestrze\u0144 g\u0142\xF3wna",
    ]);
    if (file)
      rows.push([
        "Istniej\u0105cy zas\xF3b",
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
        "Przeniesienie ze \u017Ar\xF3d\u0142a",
        (from?.meta.title || "Przestrze\u0144 g\u0142\xF3wna") +
          " / " +
          file.path,
      ]);
    }
  } else if (project)
    rows.push(["Projekt", project.meta.title || project.slug]);
  if (body.subject) rows.push(["Klucz odbiorcy", body.subject]);
  if (body.action) rows.push(["Dost\u0119p", actionLabel(body.action)]);
  if (body.resource) rows.push(["Zakres", body.resource]);
  if (body.parent_grant) rows.push(["Grant nadrz\u0119dny", body.parent_grant]);
  if (type === "grant.create") {
    rows.push([
      "Przekazywanie dalej",
      body.delegable ? "Tak, tylko w\u0119\u017Cszy zakres" : "Nie",
    ]);
    rows.push([
      "Do kiedy",
      body.expires_at
        ? new Date(body.expires_at * 1e3).toLocaleString("pl-PL")
        : "Bez terminu",
    ]);
  }
  if (body.grant) rows.push(["Cofany grant", body.grant]);
  if (body.key) rows.push(["Klucz publiczny", body.key]);
  if (body.hash) rows.push(["SHA-256 pliku", body.hash]);
  return rows;
}
function confirmSign({ type, body, signer, identity, context = {} }) {
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
        ? "Podpisz i przenie\u015B"
        : "Podpisz i opublikuj"
      : type === "grant.revoke"
        ? "Podpisz i cofnij dost\u0119p"
        : removal
          ? "Podpisz usuni\u0119cie"
          : "Podpisz i zapisz";
  return modal("Sprawd\u017A zmian\u0119 przed podpisem", (box, done) => {
    append(box, [
      h("p", { class: "eyebrow" }, actionLabel(type)),
      h(
        "dl",
        { class: "sign-meta" },
        ...[
          [
            "To\u017Csamo\u015B\u0107",
            context.data?.profile?.display_name ||
              context.data?.handle ||
              identity ||
              "Nowa to\u017Csamo\u015B\u0107",
          ],
          [
            "Podpisuj\u0105cy klucz",
            (signer.label || "Klucz") + " \xB7 " + signer.id,
          ],
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
          "Aktualizacja mo\u017Ce zast\u0105pi\u0107 istniej\u0105cy plik. Bajty s\u0105 wysy\u0142ane po tej zgodzie; publikacj\u0119 potwierdza dopiero przyj\u0119cie zdarzenia.",
        ),
      type === "grant.create" &&
        body.action.includes("put") &&
        h(
          "p",
          { class: "notice warn" },
          "Publikowanie obejmuje tak\u017Ce aktualizacj\u0119 cudzych plik\xF3w w tym zakresie. Nie jest to wy\u0142\u0105cznie dodawanie nowych.",
        ),
      removal &&
        h(
          "p",
          { class: "notice warn" },
          type === "grant.revoke"
            ? "Potomkowie utrac\u0105 podstaw\u0119 tej delegacji. Odczyt i dotychczasowe materia\u0142y pozostaj\u0105 dost\u0119pne."
            : "To nie jest fizyczne wymazanie historii ani bajt\xF3w ze wszystkich kopii.",
        ),
      h(
        "details",
        {},
        h("summary", {}, "Szczeg\xF3\u0142y techniczne"),
        h(
          "p",
          { class: "hint" },
          "Zamiar operacji przed zamian\u0105 tekst\xF3w na referencje SHA-256. To nie jest jeszcze podpisana koperta.",
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
        "Historia operacji pozostaje publiczna. Tre\u015Bci profilu i metadanych s\u0105 powi\u0105zane ze skr\xF3tami; odczyt nie wymaga kluczy.",
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
          "Wr\xF3\u0107 do szkicu",
        ),
      ),
    ]);
  });
}
function ask(title, message, label = "Potwierd\u017A") {
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
export {
  $,
  ACTION_LABELS,
  actionLabel,
  ask,
  changeSummary,
  confirmSign,
  download,
  field,
  h,
  modal,
  mount,
  notice,
};
