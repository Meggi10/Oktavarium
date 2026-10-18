let unlocked = null;
export const localVault = () => unlocked;
export function rememberVault(vault) {
  unlocked = vault;
}
export function lockVault() {
  if (unlocked) {
    unlocked.passphrase = "";
    unlocked.data = { v: 1, keys: [] };
  }
  unlocked = null;
}
export async function enterStudio(vault, ref = null) {
  rememberVault(vault);
  const root = document.getElementById("app");
  root.dataset.page = "studio";
  root.classList.remove("auth-app");
  const q = new URLSearchParams();
  if (ref) q.set("ref", ref);
  history.replaceState(null, "", "/studio" + (q.size ? "?" + q : ""));
  const studio = await import("../pages/studio.js");
  await studio.start();
}
