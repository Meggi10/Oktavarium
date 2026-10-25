(() => {
  const app = document.getElementById("app");
  if (!app) return;
  const mountedApp = app;
  const page = app.dataset.page || "aplikacji";
  let moduleFailure = false;
  function failed() {
    const loading = mountedApp.querySelector("#app-loading");
    if (!loading) return;
    const panel = document.createElement("section");
    panel.className = "panel stack";
    panel.setAttribute("role", "alert");
    const title = document.createElement("h2");
    title.textContent = "Nie uda\u0142o si\u0119 uruchomi\u0107 interfejsu";
    const explanation = document.createElement("p");
    explanation.textContent = moduleFailure
      ? "Przegl\u0105darka nie wczyta\u0142a modu\u0142u JavaScript. Od\u015Bwie\u017C stron\u0119; je\u015Bli problem wr\xF3ci, sprawd\u017A kart\u0119 Konsola i Sie\u0107 (F12)."
      : "Przygotowanie interfejsu trwa zbyt d\u0142ugo. Od\u015Bwie\u017C stron\u0119; je\u015Bli problem wr\xF3ci, sprawd\u017A kart\u0119 Konsola i Sie\u0107 (F12).";
    const retry = document.createElement("a");
    retry.className = "btn primary";
    retry.href = location.href;
    retry.textContent = "Spr\xF3buj ponownie";
    const publicLink = document.createElement("a");
    publicLink.href = "/";
    publicLink.textContent = "Wr\xF3\u0107 do Odkrywaj";
    panel.append(title, explanation, retry, publicLink);
    loading.replaceWith(panel);
    console.error(
      `Oktavarium: ${page} did not complete bootstrap. Check module loading and API requests.`,
    );
  }
  window.addEventListener(
    "error",
    (event) => {
      if (
        event.target instanceof HTMLScriptElement &&
        event.target.type === "module"
      ) {
        moduleFailure = true;
        failed();
      }
    },
    true,
  );
  setTimeout(failed, 12e3);
})();
