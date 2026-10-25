import { failure } from "../lib/failure.js";
import { h, field, notice, actionLabel } from "../lib/ui.js";
import { copyButton } from "../lib/copy-id.js";
import { dec, unb64u, short } from "../lib/bytes.js";
import * as api from "../lib/api.js";
import type { IdentityDetails } from "../lib/models.js";
import type { StudioState, StudioView } from "./studio-state.js";

export function createReadSections({
  state,
  label,
  go,
  url,
  button,
  endSession,
  say,
  render,
}: {
  state: StudioState;
  label: (identity: IdentityDetails) => string;
  go: (view: StudioView, scope?: string | null) => void;
  url: (view: StudioView, project?: string | null) => string;
  button: (text: string, action: () => unknown, cls?: string) => HTMLElement;
  endSession: () => Promise<void>;
  say: (message: string, kind?: string) => void;
  render: () => void;
}) {
  function countLabel(count: number, one: string, few: string, many: string) {
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
  function overview(d: IdentityDetails) {
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
        h("p", { class: "eyebrow" }, project ? "Projekt" : "Przestrzeń"),
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
            countLabel(d.projects.length, "projekt", "projekty", "projektów"),
          ),
          h("span", {}, countLabel(files.length, "plik", "pliki", "plików")),
          h("span", {}, "Dziennik #", d.head.seq),
        ),
        h(
          "div",
          { class: "actions" },
          button("Przeglądaj zasoby", () => go("resources")),
          button("Sprawdź dostęp", () => go("collaboration")),
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
                "plików",
              ),
            ),
          ),
        ),
      ),
      !d.projects.length &&
        h(
          "div",
          { class: "feed-empty" },
          h("h2", {}, "Nie ma jeszcze projektów"),
          button("Przejdź do projektów", () => go("projects")),
        ),
    );
  }
  function readKeys(d: IdentityDetails) {
    return h(
      "section",
      { class: "panel" },
      h("h2", {}, "Klucze publiczne"),
      h("p", {}, "Założycielski: ", copyButton(d.founding_key)),
      h("h3", {}, "Sygnowanie"),
      h(
        "ul",
        { class: "res-list" },
        d.members.map((k) =>
          h("li", {}, copyButton(k.key_id), " · ", k.status),
        ),
      ),
      h("h3", {}, "Autoryzacja przesyłania"),
      h(
        "ul",
        { class: "res-list" },
        d.auth_keys.map((k) =>
          h("li", {}, copyButton(k.key_id), " · ", k.status),
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
        "Klucze prywatne są lokalne. Nie należą do publicznych danych platformy.",
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
          ? "Sesja przesyłania aktywna w tej karcie."
          : "Nie sprawdzamy sesji przy odczycie. Zostanie sprawdzona dopiero przed uploadem.",
      ),
      button("Zakończ sesję przesyłania", endSession),
      h(
        "a",
        { class: "btn", href: "/login?restore=1" },
        "Przywróć kopię skarbca",
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
  function historyView(d: IdentityDetails) {
    return h(
      "section",
      { class: "panel" },
      h(
        "p",
        { class: "hint" },
        "Ocena serwera: " +
          (d.integrity === "ok"
            ? "podpisy i łańcuch zweryfikowane"
            : "niepotwierdzona integralność") +
          ". Brak bajtów historycznej treści nie oznacza uszkodzenia podpisu.",
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
                  h("h3", {}, "#" + e.seq + " · " + actionLabel(e.type)),
                  h(
                    "p",
                    { class: "hint" },
                    new Date(e.ts * 1000).toLocaleString("pl-PL"),
                    " · klucz ",
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
                  notice("Nie można odczytać koperty.", "bad"),
                );
              }
            }),
          )
        : h("p", {}, "Odczyt dziennika…"),
    );
  }

  return { overview, readKeys, localKeys, loadHistory, historyView };
}
