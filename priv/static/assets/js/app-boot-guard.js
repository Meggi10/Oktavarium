(() => {
  const app = document.getElementById("app");
  if (!app) return;
  const page = app.dataset.page || "aplikacji";
  let moduleFailure = false;

  function failed() {
    const loading = app.querySelector("#app-loading");
    if (!loading) return; // The real application already took over.
    const panel = document.createElement("section");
    panel.className = "panel stack";
    panel.setAttribute("role", "alert");
    const title = document.createElement("h2");
    title.textContent = "Nie udało się uruchomić interfejsu";
    const explanation = document.createElement("p");
    explanation.textContent = moduleFailure
      ? "Przeglądarka nie wczytała modułu JavaScript. Odśwież stronę; jeśli problem wróci, sprawdź kartę Konsola i Sieć (F12)."
      : "Przygotowanie interfejsu trwa zbyt długo. Odśwież stronę; jeśli problem wróci, sprawdź kartę Konsola i Sieć (F12).";
    const retry = document.createElement("a");
    retry.className = "btn primary";
    retry.href = location.href;
    retry.textContent = "Spróbuj ponownie";
    const publicLink = document.createElement("a");
    publicLink.href = "/";
    publicLink.textContent = "Wróć do Odkrywaj";
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
  setTimeout(failed, 12000);
})();
