import { failure } from "../lib/failure.js";
import { h, field, notice, actionLabel } from "../lib/ui.js";
import { copyButton } from "../lib/copy-id.js";
import { dec, unb64u, short } from "../lib/bytes.js";
import * as api from "../lib/api.js";
function createReadSections({
  state,
  label,
  go,
  url,
  button,
  endSession,
  say,
  render,
}) {
  function countLabel(count, one, few, many) {
    const mod10 = count % 10;
    const mod100 = count % 100;
    const form =
      count === 1
        ? one
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
          ? few
          : many;
    return `${count} ${form}`;
  }
  function overview(d) {
    const project = d.projects.find((p) => p.id === state.projectId);
    const files = d.resources.filter(
      (r) =>
        state.projectId === "all" || (r.project_id || null) === state.projectId,
    );
    return h(
      "div",
      { class: "stack" },
      h(
        "section",
        { class: "panel" },
        h("p", { class: "eyebrow" }, project ? "Projekt" : "Przestrze\u0144"),
        h("h2", {}, project?.meta.title || label(d)),
        h(
          "p",
          {},
          project?.meta.description || d.profile.bio || "Nie ma jeszcze opisu.",
        ),
        h(
          "div",
          { class: "quick-summary" },
          h(
            "span",
            {},
            countLabel(
              d.projects.length,
              "projekt",
              "projekty",
              "projekt\xF3w",
            ),
          ),
          h("span", {}, countLabel(files.length, "plik", "pliki", "plik\xF3w")),
          h("span", {}, "Dziennik #", d.head.seq),
        ),
        h(
          "div",
          { class: "actions" },
          button("Przegl\u0105daj zasoby", () => go("resources")),
          button("Sprawd\u017A dost\u0119p", () => go("collaboration")),
          h(
            "a",
            { class: "btn", href: "/join?kind=collective" },
            "Nowy kolektyw",
          ),
        ),
      ),
      h(
        "div",
        { class: "project-grid" },
        d.projects.map((p) =>
          h(
            "a",
            {
              class: "project-card",
              href: url("resources", p.id),
              onclick: (e) => {
                e.preventDefault();
                go("resources", p.id);
              },
            },
            h("p", { class: "eyebrow" }, "Projekt"),
            h("h2", {}, p.meta.title || p.slug),
            h("p", {}, p.meta.description || "Brak opisu."),
            h(
              "span",
              { class: "hint" },
              countLabel(
                d.resources.filter((r) => r.project_id === p.id).length,
                "plik",
                "pliki",
                "plik\xF3w",
              ),
            ),
          ),
        ),
      ),
      !d.projects.length &&
        h(
          "div",
          { class: "feed-empty" },
          h("h2", {}, "Nie ma jeszcze projekt\xF3w"),
          button("Przejd\u017A do projekt\xF3w", () => go("projects")),
        ),
    );
  }
  function readKeys(d) {
    return h(
      "section",
      { class: "panel" },
      h("h2", {}, "Klucze publiczne"),
      h("p", {}, "Za\u0142o\u017Cycielski: ", copyButton(d.founding_key)),
      h("h3", {}, "Sygnowanie"),
      h(
        "ul",
        { class: "res-list" },
        d.members.map((k) =>
          h("li", {}, copyButton(k.key_id), " \xB7 ", k.status),
        ),
      ),
      h("h3", {}, "Autoryzacja przesy\u0142ania"),
      h(
        "ul",
        { class: "res-list" },
        d.auth_keys.map((k) =>
          h("li", {}, copyButton(k.key_id), " \xB7 ", k.status),
        ),
      ),
    );
  }
  function localKeys() {
    return h(
      "section",
      { class: "panel local-vault", "data-local-only": "true" },
      h("h2", {}, "Lokalny skarbiec i sesja"),
      h(
        "p",
        {},
        "Klucze prywatne s\u0105 lokalne. Nie nale\u017C\u0105 do publicznych danych platformy.",
      ),
      state.vault &&
        field(
          "Klucz autoryzacji uploadu",
          h(
            "select",
            {
              id: "upload-auth",
              onchange: (e) => {
                state.authId = e.target.value;
              },
            },
            h("option", { value: "" }, "Wybierz klucz"),
            state.vault
              .ofKind("auth")
              .map((k) =>
                h(
                  "option",
                  { value: k.id, selected: k.id === state.authId },
                  k.label || short(k.id),
                ),
              ),
          ),
        ),
      h(
        "p",
        { class: "hint" },
        state.me
          ? "Sesja przesy\u0142ania aktywna w tej karcie."
          : "Nie sprawdzamy sesji przy odczycie. Zostanie sprawdzona dopiero przed uploadem.",
      ),
      button("Zako\u0144cz sesj\u0119 przesy\u0142ania", endSession),
      h(
        "a",
        { class: "btn", href: "/login?restore=1" },
        "Przywr\xF3\u0107 kopi\u0119 skarbca",
      ),
    );
  }
  async function loadHistory() {
    const id = state.current;
    if (!id) return;
    try {
      const events = await api.history(id);
      if (id !== state.current) return;
      state.events = events;
      if (state.view === "history") render();
    } catch (e) {
      say(failure(e).message, "bad");
    }
  }
  function historyView(d) {
    return h(
      "section",
      { class: "panel" },
      h(
        "p",
        { class: "hint" },
        "Ocena serwera: " +
          (d.integrity === "ok"
            ? "podpisy i \u0142a\u0144cuch zweryfikowane"
            : "niepotwierdzona integralno\u015B\u0107") +
          ". Brak bajt\xF3w historycznej tre\u015Bci nie oznacza uszkodzenia podpisu.",
      ),
      state.events
        ? h(
            "ol",
            { class: "history-list" },
            [...state.events].reverse().map((envelope) => {
              try {
                const e = JSON.parse(dec.decode(unb64u(envelope.payload)));
                return h(
                  "li",
                  {},
                  h("h3", {}, "#" + e.seq + " \xB7 " + actionLabel(e.type)),
                  h(
                    "p",
                    { class: "hint" },
                    new Date(e.ts * 1e3).toLocaleString("pl-PL"),
                    " \xB7 klucz ",
                    copyButton(e.signer),
                  ),
                  h(
                    "details",
                    {},
                    h("summary", {}, "Podpisana operacja"),
                    h("pre", { class: "code" }, JSON.stringify(e, null, 2)),
                  ),
                );
              } catch {
                return h(
                  "li",
                  {},
                  notice("Nie mo\u017Cna odczyta\u0107 koperty.", "bad"),
                );
              }
            }),
          )
        : h("p", {}, "Odczyt dziennika\u2026"),
    );
  }
  return { overview, readKeys, localKeys, loadHistory, historyView };
}
export { createReadSections };
