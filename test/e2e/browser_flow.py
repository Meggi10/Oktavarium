"""Test end-to-end klienta w przeglądarce (Playwright + Chromium).

Wymaga działającego serwera dev z pustą bazą 
(`mix ecto.setup && mix phx.server`, `config :oktavarium, sites_domain: "localhost"`). 

Użycie:
    python3 test/e2e/browser_flow.py http://localhost:4000 /tmp/e2e-out
"""
import io, os, struct, sys, wave, zlib
from playwright.sync_api import sync_playwright, expect

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:4000"
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/e2e-out"
os.makedirs(OUT, exist_ok=True)
PASS = "gekon z cyckami"

def png(w=64, h=64, rgb=(200, 80, 40)):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")

def wav():
    buf = io.BytesIO()
    with wave.open(buf, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(8000)
        f.writeframes(b"\x00\x10" * 8000)
    return buf.getvalue()

files = {
    "kot.png": png(),
    "demo.wav": wav(),
    "index.html": b"<!doctype html><meta charset=utf-8><link rel=stylesheet href=/css/a.css><h1 id=t>Strona Pelagii</h1><script src=/app.js></script>",
    "a.css": b"#t{color:rgb(1,2,3)}",
    "app.js": b"document.getElementById('t').dataset.js='ok'",
}
for name, data in files.items():
    open(os.path.join(OUT, name), "wb").write(data)

def sign_dialog(page, expect_type):
    dlg = page.locator("dialog.sign-dialog")
    dlg.wait_for()
    assert expect_type in dlg.inner_text(), dlg.inner_text()
    dlg.get_by_role("button", name="Podpisz", exact=True).click()
    dlg.wait_for(state="detached")

def saved(page):
    expect(page.locator(".notice.ok")).to_contain_text("Zapisano", timeout=15000)

with sync_playwright() as p:
    browser = p.chromium.launch()
    ctx = browser.new_context(viewport={"width": 1100, "height": 900}, accept_downloads=True)
    page = ctx.new_page()
    problems = []
    page.on("console", lambda m: problems.append(m.text) if m.type in ("error", "warning") else None)
    page.on("pageerror", lambda e: problems.append(str(e)))

    # odczyt pracowni jest możliwy zanim powstaną sesje i klucze
    page.goto(BASE + "/studio")
    expect(page.locator("#studio-ref")).to_be_visible()
    expect(page.locator("body")).to_contain_text("Przeglądaj profile")
    assert page.locator("#pass").count() == 0

    # join + genesis w przeglądarce
    page.goto(BASE + "/join")
    page.fill("#handle", "pelagia")
    page.fill("#pass", PASS)
    page.fill("#pass2", PASS)
    page.get_by_role("button", name="Wygeneruj klucze").click()
    expect(page.locator("#create")).to_be_disabled()
    assert page.locator("#backed").is_disabled()
    with page.expect_download() as dl:
        page.get_by_role("button", name="Pobierz zaszyfrowaną kopię zapasową").click()
    backup_path = os.path.join(OUT, "backup.json")
    dl.value.save_as(backup_path)
    page.check("#backed")
    page.screenshot(path=f"{OUT}/1-join.png", full_page=True)
    page.click("#create")
    page.wait_for_url("**/studio")

    # studio: publiczny podgląd oraz jawne przejście do trybu edycji
    expect(page.locator("#read-keys-h")).to_be_visible()
    page.get_by_role("button", name="Odblokuj edycję").click()
    page.fill("#pass", PASS)
    page.get_by_role("button", name="Odblokuj").click()
    page.wait_for_selector("#p-display_name")
    page.fill("#p-display_name", "Pelagia Coda")
    page.fill("#p-bio", "Kompozytorka i programistka.")
    page.click("#save-profile")
    sign_dialog(page, "profile.update")
    saved(page)

    # zasoby: obraz, nagranie, strona
    def upload(kind, path, name, title=None, alt=None):
        page.select_option("#r-kind", kind)
        page.set_input_files("#r-file", path)
        page.fill("#r-name", name)
        if title: page.fill("#r-title", title)
        if alt: page.fill("#r-alt", alt)
        page.click("#upload")
        sign_dialog(page, "resource.put")
        saved(page)

    upload("image", f"{OUT}/kot.png", "kot.png", "Rudy kot", "Rudy kot na parapecie")
    upload("audio", f"{OUT}/demo.wav", "demo.wav", "Szkic")
    upload("site", f"{OUT}/index.html", "index.html")
    upload("site", f"{OUT}/a.css", "css/a.css")
    upload("site", f"{OUT}/app.js", "app.js")
    expect(page.locator("section[aria-labelledby=res-h] .res-list li")).to_have_count(5)

    # klucze: urządzenie + drugi klucz logowania + grant + cofnięcie
    page.fill("#k-label", "laptop")
    page.click("#add-device")
    sign_dialog(page, "key.add")
    saved(page)
    page.fill("#ak-label", "telefon")
    page.click("#add-auth")
    sign_dialog(page, "auth_key.add")
    saved(page)

    page.select_option("#g-action", "resource.put")
    page.fill("#g-resource", "/images/*")
    page.click("#grant")
    sign_dialog(page, "grant.create")
    saved(page)
    expect(page.locator("tr.grant.is-active")).to_have_count(1)
    page.get_by_role("button", name="Cofnij").first.click() if False else None
    page.locator("tr.grant").get_by_role("button", name="Cofnij").click()
    sign_dialog(page, "grant.revoke")
    saved(page)
    expect(page.locator("tr.grant.is-revoked")).to_have_count(1)
    page.screenshot(path=f"{OUT}/2-studio.png", full_page=True)

    # odmowa serwera przy braku uprawnień: podpis kluczem urządzenia
    signer = page.locator("#signer")
    device = [o for o in signer.locator("option").all() if "laptop" in o.inner_text()][0]
    signer.select_option(value=device.get_attribute("value"))
    page.fill("#p-bio", "zmiana bez prawa")
    page.click("#save-profile")
    sign_dialog(page, "profile.update")
    expect(page.locator(".notice.bad")).to_contain_text("uprawnienia", timeout=15000)

    # strona główna: galeria i nagranie
    page2 = ctx.new_page()
    page2.on("console", lambda m: problems.append(m.text) if m.type in ("error", "warning") else None)
    page2.goto(BASE + "/")
    img = page2.locator(".gallery img").first
    img.wait_for()
    assert img.evaluate("i => i.complete && i.naturalWidth") == 64
    assert page2.locator("audio").count() == 1
    expect(page2.locator(".gallery")).to_contain_text("Rudy kot")
    page2.screenshot(path=f"{OUT}/3-home.png", full_page=True)

    # strona tożsamości
    page2.goto(BASE + "/i/pelagia")
    expect(page2.locator("body")).to_contain_text("Cofnięto uprawnienie")
    expect(page2.locator("body")).to_contain_text("Klucze urządzeń")
    page2.screenshot(path=f"{OUT}/4-identity.png", full_page=True)

    # subdomena ze stroną
    port = BASE.split(":")[-1]
    site = ctx.new_page()
    site.on("console", lambda m: problems.append("SITE " + m.text) if m.type in ("error", "warning") else None)
    site.goto(f"http://pelagia.localhost:{port}/")
    expect(site.locator("#t")).to_have_text("Strona Pelagii")
    assert site.locator("#t").evaluate("e => getComputedStyle(e).color") == "rgb(1, 2, 3)"
    assert site.locator("#t").get_attribute("data-js") == "ok"
    # strona nie ma dostępu do sesji aplikacji: API na jej hoście nie istnieje
    status = site.evaluate("fetch('/api/me').then(r => r.status)")
    assert status == 404, status
    # ani cookie sesji aplikacji nie jest widoczne dla skryptów strony
    assert site.evaluate("document.cookie") == ""
    # a strona nie może odczytać API aplikacji (inny origin, brak CORS)
    blocked = site.evaluate(f"fetch('http://localhost:{port}/api/me', {{credentials: 'include'}}).then(() => 'read', () => 'blocked')")
    assert blocked == "blocked", blocked
    cookies = [c for c in ctx.cookies() if c["name"] == "oktavarium_session"]
    assert cookies and cookies[0]["httpOnly"] and cookies[0]["sameSite"] == "Strict"
    assert cookies[0]["domain"] in ("localhost",), cookies[0]
    site.screenshot(path=f"{OUT}/5-site.png")

    # wylogowanie i ponowne logowanie z tej samej przeglądarki
    page.get_by_role("button", name="wyloguj").click()
    page.wait_for_url("**/login")
    page.fill("#pass", "złe hasło złe hasło")
    page.get_by_role("button", name="Zaloguj", exact=True).click()
    expect(page.locator(".notice.bad")).to_contain_text("hasło")
    page.fill("#pass", PASS)
    page.get_by_role("button", name="Zaloguj", exact=True).click()
    try:
        page.wait_for_url("**/studio", timeout=15000)
    except Exception:
        print("RELOGIN STUCK:", page.url, page.inner_text("#app")[:400], problems)
        raise

    # nowa przeglądarka: przywrócenie z kopii zapasowej
    ctx2 = browser.new_context()
    fresh = ctx2.new_page()
    fresh.goto(BASE + "/login")
    fresh.set_input_files("#backup", backup_path)
    fresh.fill("#pass-restore", PASS)
    fresh.get_by_role("button", name="Przywróć i zaloguj").click()
    # kopia z kroku 1 zawiera klucz logowania założycielski -> serwer go zna
    fresh.wait_for_url("**/studio")

    browser.close()

# Oczekiwane "błędy" to sprawdzane celowo odmowy: 403 przy podpisie kluczem bez uprawnień, 
# 404 na /api/me z hosta strony i blokada CSP próby sięgnięcia przez stronę do API aplikacji.
EXPECTED = ("status of 403", "status of 404", "Content Security Policy")
real = [m for m in problems if "favicon" not in m and not any(e in m for e in EXPECTED)]
print("PROBLEMS:", real)
assert not real, real
print("E2E OK")
