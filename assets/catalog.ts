import { Socket } from "phoenix";
import { LiveSocket, type Hook } from "phoenix_live_view";

// Po zmianie filtra LiveView podmienia aktywny link. Hook zachowuje punkt
// skupienia dla użytkownika klawiatury, bez ręcznego zarządzania listą kart.
type FocusState = { focusPending: boolean; abort: AbortController };

const CatalogFocus: Hook<FocusState> = {
  mounted() {
    this.focusPending = false;
    this.abort = new AbortController();
    this.el.addEventListener(
      "click",
      (event) => {
        const link = (event.target as Element).closest("a[data-phx-link]");
        if (
          link &&
          !event.metaKey &&
          !event.ctrlKey &&
          !event.shiftKey &&
          !event.altKey
        ) {
          this.focusPending = true;
        }
      },
      { signal: this.abort.signal },
    );
  },
  updated() {
    if (!this.focusPending) return;
    this.focusPending = false;
    this.el.querySelector<HTMLAnchorElement>('a[aria-current="page"]')?.focus();
  },
  destroyed() {
    this.abort.abort();
  },
};

if (document.querySelector("[data-phx-main]")) {
  const csrfToken = document.querySelector<HTMLMetaElement>(
    'meta[name="csrf-token"]',
  )?.content;
  if (csrfToken) {
    const liveSocket = new LiveSocket("/live", Socket, {
      params: { _csrf_token: csrfToken },
      hooks: { CatalogFocus },
    });
    liveSocket.connect();
  }
}
