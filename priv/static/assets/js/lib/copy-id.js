import { failure } from "./failure.js";
function abbreviate(value) {
  if (typeof value !== "string") return "";
  return value.length > 14
    ? value.slice(0, 6) + "\u2026" + value.slice(-4)
    : value;
}
function copyButton(value, { label = "pe\u0142ny identyfikator" } = {}) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "hash copy-id";
  button.title = value || "";
  button.dataset.copyValue = value || "";
  button.setAttribute("aria-label", `Skopiuj ${label}: ${value || ""}`);
  button.textContent = abbreviate(value);
  return button;
}
async function copyText(value) {
  if (typeof value !== "string" || !value)
    throw new Error("Brak identyfikatora.");
  if (typeof navigator !== "undefined" && navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }
  const area = document.createElement("textarea");
  area.value = value;
  area.readOnly = true;
  area.style.cssText = "position:fixed;left:-9999px;top:0;opacity:0";
  document.body.append(area);
  area.select();
  try {
    if (!document.execCommand?.("copy"))
      throw new Error("Schowek jest niedost\u0119pny.");
  } finally {
    area.remove();
  }
}
let messageTimer;
function feedback(message) {
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
    const button = event.target?.closest("button[data-copy-value]");
    if (!button || button.disabled) return;
    try {
      await copyText(button.dataset.copyValue);
      button.classList.add("copied");
      feedback("Skopiowano pe\u0142ny identyfikator do schowka.");
      setTimeout(() => {
        if (button.isConnected) button.classList.remove("copied");
      }, 1500);
    } catch (error) {
      feedback("Nie mo\u017Cna skopiowa\u0107: " + failure(error).message);
    }
  });
}
export { abbreviate, copyButton, copyText };
