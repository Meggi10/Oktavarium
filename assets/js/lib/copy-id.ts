import { failure } from "./failure.js";
// Public identifiers (signing keys, event IDs and SHA-256 hashes) can be copied
// without entering an edit session. No private keys or secrets are ever copied.
export function abbreviate(value: string | null | undefined) {
  if (typeof value !== "string") return "";
  return value.length > 14 ? value.slice(0, 6) + "…" + value.slice(-4) : value;
}

export function copyButton(
  value: string | null | undefined,
  { label = "pełny identyfikator" } = {},
) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "hash copy-id";
  button.title = value || "";
  button.dataset.copyValue = value || "";
  button.setAttribute("aria-label", `Skopiuj ${label}: ${value || ""}`);
  button.textContent = abbreviate(value);
  return button;
}

export async function copyText(value: string | null | undefined) {
  if (typeof value !== "string" || !value)
    throw new Error("Brak identyfikatora.");
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }
  // Fallback for non-secure dev origins. Fail visibly if copying is forbidden.
  const area = document.createElement("textarea");
  area.value = value;
  area.readOnly = true;
  area.style.cssText = "position:fixed;left:-9999px;top:0;opacity:0";
  document.body.append(area);
  area.select();
  try {
    if (!document.execCommand?.("copy"))
      throw new Error("Schowek jest niedostępny.");
  } finally {
    area.remove();
  }
}

let messageTimer: ReturnType<typeof setTimeout> | undefined;
function feedback(message: string) {
  let box = document.getElementById("copy-feedback");
  if (!box) {
    box = document.createElement("div");
    box.id = "copy-feedback";
    box.className = "copy-feedback";
    box.setAttribute("role", "status");
    box.setAttribute("aria-live", "polite");
    document.body.append(box);
  }
  box.textContent = message;
  box.hidden = false;
  if (messageTimer) clearTimeout(messageTimer);
  messageTimer = setTimeout(() => {
    box.hidden = true;
  }, 2500);
}

if (typeof document !== "undefined") {
  document.addEventListener("click", async (event) => {
    const button = (event.target as Element | null)?.closest<HTMLButtonElement>(
      "button[data-copy-value]",
    );
    if (!button || button.disabled) return;
    try {
      await copyText(button.dataset.copyValue);
      button.classList.add("copied");
      feedback("Skopiowano pełny identyfikator do schowka.");
      setTimeout(() => {
        if (button.isConnected) button.classList.remove("copied");
      }, 1500);
    } catch (error) {
      feedback("Nie można skopiować: " + failure(error).message);
    }
  });
}
