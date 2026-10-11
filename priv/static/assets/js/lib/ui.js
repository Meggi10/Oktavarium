// Minimalne pomocniki DOM. Cała treść trafia przez `textContent`, nigdy `innerHTML`,
// więc dane z serwera i od innych użytkowników nie mogą wstrzyknąć znaczników.

export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === false || v == null) continue;
    if (k === "class") el.className = [v].flat().filter(Boolean).join(" ");
    else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2), v);
    else if (k === "value" || k === "checked" || k === "disabled" || k === "hidden") el[k] = v;
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

export function mount(root, ...children) {
  root.replaceChildren();
  append(root, children);
}

export const $ = (sel, root = document) => root.querySelector(sel);

/** Pole formularza z etykietą. */
export function field(label, input, hint) {
  return h("label", { class: "field" }, h("span", { class: "field-label" }, label), input, hint && h("span", { class: "hint" }, hint));
}

export function notice(text, kind = "info") {
  return h("p", { class: "notice " + kind, role: kind === "bad" ? "alert" : "status" }, text);
}

/** Pobranie pliku wygenerowanego w przeglądarce. */
export function download(name, content, type = "application/json") {
  const blob = new Blob([typeof content === "string" ? content : JSON.stringify(content, null, 2)], { type });
  const url = URL.createObjectURL(blob);
  const a = h("a", { href: url, download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

/**
 * Okno „Co podpisujesz": pokazuje typ, tożsamość, klucz i pełną treść zdarzenia.
 * Zwraca obietnicę `true` (podpisz) albo `false` (anuluj).
 */
export function confirmSign({ type, body, signer, identity }) {
  return new Promise((resolve) => {
    const dialog = h("dialog", { class: "sign-dialog", "aria-labelledby": "sign-h" });
    const done = (value) => {
      dialog.close();
      dialog.remove();
      resolve(value);
    };
    dialog.append(
      h("h2", { id: "sign-h" }, "Co podpisujesz"),
      h(
        "dl",
        { class: "sign-meta" },
        h("div", {}, h("dt", {}, "Typ zdarzenia"), h("dd", {}, h("code", {}, type))),
        h("div", {}, h("dt", {}, "Tożsamość"), h("dd", {}, h("code", {}, identity))),
        h("div", {}, h("dt", {}, "Podpisze kluczem"), h("dd", {}, h("code", {}, signer.id))),
      ),
      h("pre", { class: "code" }, JSON.stringify(body, null, 2)),
      h(
        "p",
        { class: "muted" },
        "Zdarzenie trafi do publicznego, podpisanego dziennika tej tożsamości. Nie da się go potem usunąć, tylko zastąpić kolejnym.",
      ),
      h(
        "div",
        { class: "actions" },
        h("button", { type: "button", class: "btn primary", onclick: () => done(true) }, "Podpisz"),
        h("button", { type: "button", class: "btn", onclick: () => done(false) }, "Anuluj"),
      ),
    );
    dialog.addEventListener("cancel", (e) => {
      e.preventDefault();
      done(false);
    });
    document.body.append(dialog);
    dialog.showModal();
  });
}
