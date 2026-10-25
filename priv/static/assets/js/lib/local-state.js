let unlocked = null;
const localVault = () => unlocked;
function rememberVault(vault) {
  unlocked = vault;
}
function lockVault() {
  if (unlocked) {
    unlocked.passphrase = "";
    unlocked.data = { v: 1, keys: [] };
  }
  unlocked = null;
}
async function enterStudio(vault, ref = null) {
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
export { enterStudio, localVault, lockVault, rememberVault };
