import type { Vault } from "./keystore.js";

let unlocked: Vault | null = null;
export const localVault = () => unlocked;
export function rememberVault(vault: Vault) {
  unlocked = vault;
}
export function lockVault() {
  if (unlocked) {
    unlocked.passphrase = "";
    unlocked.data = { v: 1, keys: [] };
  }
  unlocked = null;
}
export async function enterStudio(vault: Vault, ref: string | null = null) {
  rememberVault(vault);
  const root = document.getElementById("app");
  if (!root) throw new Error("Brak kontenera aplikacji.");
  root.dataset.page = "studio";
  root.classList.remove("auth-app");
  const q = new URLSearchParams();
  if (ref) q.set("ref", ref);
  history.replaceState(null, "", "/studio" + (q.size ? "?" + q : ""));
  const studio = await import("../pages/studio.js");
  await studio.start();
}
