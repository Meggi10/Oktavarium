"""B4+B5+C2 integration flow against a running DEV server with open registration.

Creates one unlisted test collective (unique handle); does not reset any database.
Setup uses the real browser signing/API modules; project, file and grant operations
then use Studio forms. Public reads are also checked in a fresh browser context.

python3 test/e2e/projects_flow.py http://localhost:4000 /tmp/oktavarium-b45
Optional: BROWSER_EXECUTABLE=/usr/bin/chromium
Requires: pip install playwright && playwright install chromium
"""
import argparse
import json
import os
from pathlib import Path
import uuid

from playwright.sync_api import expect, sync_playwright

PASS = "oktavarium test vault 2026"
SETUP = """async ({pass, handle}) => {
  const {generateKey} = await import('/assets/js/lib/crypto.js');
  const {Vault} = await import('/assets/js/lib/keystore.js');
  const api = await import('/assets/js/lib/api.js');
  const founder = await generateKey('signing', 'founder');
  const auth = await generateKey('auth', 'upload');
  const helper = await generateKey('signing', 'helper');
  const leaf = await generateKey('signing', 'leaf');
  const created = await api.genesis({founder, body: {
    kind: 'collective', visibility: 'unlisted', handle, auth_keys: [auth.id]
  }});
  founder.identity = created.identity;
  const vault = Vault.empty(pass);
  for (const key of [founder, auth, helper, leaf]) vault.add(key);
  await vault.save();
  for (const key of [helper, leaf]) await api.publish({
    signer: founder, identity: created.identity, type: 'key.add', body: {key: key.id, label: key.label}
  });
  return {identity: created.identity, founder: founder.id, helper: helper.id, leaf: leaf.id};
}"""


def run(base: str, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as pw:
        launch = {"headless": True}
        if os.environ.get("BROWSER_EXECUTABLE"):
            launch["executable_path"] = os.environ["BROWSER_EXECUTABLE"]
        browser = pw.chromium.launch(**launch)
        ctx = browser.new_context(accept_downloads=True)
        page = ctx.new_page()
        page.set_default_timeout(15000)
        errors, requests, checked = [], [], []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("request", lambda req: requests.append((req.method, req.url)))
        page.goto(base + "/studio")
        expect(page.locator("#studio-ref")).to_be_attached()
        info = page.evaluate(SETUP, {"pass": PASS, "handle": "b45-" + uuid.uuid4().hex[:12]})
        identity = info["identity"]

        def data():
            response = page.request.get(f"{base}/api/identities/{identity}")
            assert response.status == 200, response.text()
            return response.json()

        def nav(view):
            page.locator(f'.desktop-studio-nav a[href*="view={view}"]').click()

        def confirm(kind: str, accept: bool = True):
            dialog = page.locator("dialog.sign-dialog")
            expect(dialog).to_be_visible()
            assert kind in dialog.text_content()
            page.locator("#confirm-sign" if accept else "#cancel-sign").click()
            expect(dialog).to_have_count(0)
            if accept:
                expect(page.locator("#msg .notice.ok")).to_contain_text("Zdarzenie przyj")

        def edit_details(form_id):
            page.locator(f"#{form_id}").locator("..").locator("summary").click()

        def create_project(slug):
            edit_details("project-create")
            page.fill("#project-title", slug.title())
            page.fill("#project-slug", slug)
            page.fill("#project-description", "Unicode: Za\u017c\u00f3\u0142\u0107")
            page.click("#create-project")
            confirm("project.create")
            return next(p["id"] for p in data()["projects"] if p["slug"] == slug)

        def upload_site(name, body, accept=True):
            nav("resources")
            if page.locator(".upload-section").get_attribute("open") is None:
                page.locator(".upload-section > summary").click()
            page.select_option("#r-kind", "site")
            page.set_input_files("#r-file", {"name": name, "mimeType": "text/html" if name.endswith("html") else "text/plain", "buffer": body})
            page.fill("#r-name", name)
            page.click("#upload")
            confirm("resource.put", accept)

        # No /api/me, login or key unlock is needed to browse the unlisted identity.
        start = len(requests)
        page.goto(f"{base}/studio?ref={identity}")
        expect(page.locator("#studio-content h1")).to_be_visible()
        assert page.locator("#signer").count() == 0
        page.get_by_role("button", name="Odblokuj klucze", exact=True).click()
        page.fill("#unlock-pass", PASS)
        page.get_by_role("button", name="Odblokuj", exact=True).click()
        expect(page.locator("#identity")).to_be_visible()
        assert not any("/api/me" in url or "/api/session" in url for _, url in requests[start:])
        assert not ctx.cookies()
        checked.append("public read and local vault unlock without a server session")

        nav("projects")
        one, two = create_project("atlas"), create_project("notes")
        page.select_option("#project-filter", one)
        html = b'<!doctype html><link rel="stylesheet" href="/theme.css"><h1 id="site-title">Project website</h1><script src="/app.js"></script>'
        before = len(requests)
        upload_site("index.html", html, accept=False)
        assert not data()["resources"]
        assert not any(method == "POST" for method, _ in requests[before:])
        checked.append("cancelling publication does not upload bytes or publish an event")
        upload_site("index.html", html)
        entry = data()["resources"][0]
        resource_id = entry["id"]
        assert entry["project_id"] == one
        download = page.request.get(f"{base}/api/identities/{identity}/resources/{resource_id}/download")
        assert download.body() == html
        assert download.headers["content-disposition"].startswith("attachment;")
        checked.append("confirmed upload, signed publication and safe source download")

        # Moving always identifies the file by ID, not by a destination path.
        row = page.locator(f'li[data-resource-id="{resource_id}"]')
        row.locator("summary").click()
        page.select_option(f'[id="move-{resource_id}"]', two)
        row.get_by_role("button", name="Podpisz zmiany pliku", exact=True).click()
        confirm("resource.put")
        assert data()["resources"][0]["id"] == resource_id
        assert data()["resources"][0]["project_id"] == two
        page.select_option("#project-filter", two)
        old_url = next(p["site_url"] for p in data()["projects"] if p["id"] == two)
        nav("projects")
        edit_details("project-edit")
        page.fill("#project-edit-slug", "renamed-notes")
        page.click("#save-project")
        confirm("project.update")
        assert next(p["site_url"] for p in data()["projects"] if p["id"] == two) == old_url
        upload_site("theme.css", b"#site-title { color: rgb(1, 2, 3); }")
        upload_site("app.js", b"document.getElementById('site-title').dataset.executed='yes';")
        checked.append("stable file ID after moving; stable site origin after project rename")

        # Founder gives helper a bounded, delegable project grant.
        nav("collaboration")
        page.fill("#g-other", info["helper"])
        page.select_option("#g-project", two)
        page.select_option("#g-action", "resource.*")
        page.fill("#g-resource", "*")
        page.fill("#g-days", "2")
        page.check("#g-delegable")
        page.check("#g-verified")
        page.click("#grant")
        confirm("grant.create")
        parent = next(g for g in data()["grants"] if g["subject_key_id"] == info["helper"])
        page.select_option("#signer", info["helper"])
        nav("projects")
        expect(page.locator("#create-project")).to_be_disabled()
        nav("collaboration")
        expect(page.locator("#g-parent")).to_be_enabled()
        page.fill("#g-other", info["leaf"])
        page.select_option("#g-action", "resource.put")
        page.fill("#g-resource", "site/*")
        page.select_option("#g-parent", parent["id"])
        page.check("#g-verified")
        page.click("#grant")
        confirm("grant.create")
        child = next(g for g in data()["grants"] if g["subject_key_id"] == info["leaf"])
        assert child["parent_grant_id"] == parent["id"]
        assert child["expires_at"] == parent["expires_at"]
        checked.append("scoped delegation through an explicit parent; inherited expiry")

        page.select_option("#signer", info["leaf"])
        expect(page.locator("#grant")).to_be_disabled()
        nav("resources")
        row = page.locator(f'li[data-resource-id="{resource_id}"]')
        row.locator("summary").click()
        page.fill(f'[id="edit-{resource_id}-title"]', "Edited by a delegate")
        row.get_by_role("button", name="Podpisz zmiany pliku", exact=True).click()
        confirm("resource.put")
        row = page.locator(f'li[data-resource-id="{resource_id}"]')
        row.locator("summary").click()
        page.fill(f'[id="path-{resource_id}"]', "site/moved.html")
        row.get_by_role("button", name="Podpisz zmiany pliku", exact=True).click()
        expect(page.locator("#msg .notice.bad")).to_contain_text("resource.delete")
        assert page.locator("dialog").count() == 0
        checked.append("file edits allowed; rename rejected without source delete permission")

        page.select_option("#signer", info["founder"])
        nav("collaboration")
        expect(page.locator("#g-parent")).to_be_disabled()
        page.locator(f'tr[data-grant-id="{parent["id"]}"]').get_by_role("button", name="Cofnij", exact=True).click()
        confirm("grant.revoke")
        assert next(g["status"] for g in data()["grants"] if g["id"] == child["id"]) == "broken"
        # Independently submit a signed write, not relying on disabled UI controls.
        status = page.evaluate("""async ({identity, leaf, id, pass}) => {
          const {Vault} = await import('/assets/js/lib/keystore.js');
          const api = await import('/assets/js/lib/api.js');
          const vault = await Vault.unlock(pass);
          const file = (await api.identity(identity)).resources.find(r => r.id === id);
          try { await api.publish({signer: vault.get(leaf), identity, type: 'resource.put', body: {
            id, path: file.path, project_id: file.project_id, hash: file.hash,
            size: file.size, media_type: file.media_type, meta: {title: 'Must be rejected'}
          }}); return 201; } catch (error) { return error.status; }
        }""", {"identity": identity, "leaf": info["leaf"], "id": resource_id, "pass": PASS})
        assert status == 403, status
        checked.append("revoking an ancestor blocks descendant writes at the server")

        public = browser.new_context()
        reader = public.new_page()
        reader.on("pageerror", lambda error: errors.append(str(error)))
        reader.goto(f"{base}/studio?ref={identity}&project={two}&view=resources")
        expect(reader.locator("#res-h")).to_be_visible()
        assert reader.locator("#signer").count() == 0
        assert public.cookies() == []
        if old_url:
            # Use the SAME context that has the app vault and session: another
            # fresh context would not prove origin isolation.
            assert page.evaluate("async () => (await indexedDB.databases()).some(d => d.name === 'oktavarium')")
            site = ctx.new_page()
            site.on("pageerror", lambda error: errors.append(str(error)))
            site.goto(old_url)
            expect(site.locator("#site-title")).to_have_attribute("data-executed", "yes")
            assert site.locator("#site-title").evaluate("e => getComputedStyle(e).color") == "rgb(1, 2, 3)"
            assert site.evaluate("fetch('/api/me').then(r => r.status)") == 404
            assert site.evaluate("document.cookie") == ""
            assert site.evaluate("async () => {const m = indexedDB.databases ? await indexedDB.databases() : []; return !m.some(d => d.name === 'oktavarium');}")
            checked.append("project HTML/CSS/JS runs on a separate origin without application API or vault")
        else:
            checked.append("site-origin check SKIPPED: configure sites_domain to enable project websites")
        public.close()
        page.get_by_role("button", name="Zablokuj klucze", exact=True).click()
        expect(page.locator("#signer")).to_have_count(0)
        assert "/studio" in page.url
        checked.append("locking returns to public Studio without a login redirect")
        page.screenshot(path=str(out / "public-studio.png"), full_page=True)
        assert not errors, errors
        report = {"identity": identity, "projects": [one, two], "checks": checked, "page_errors": errors}
        (out / "projects-flow.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False, indent=2))
        browser.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", nargs="?", default="http://localhost:4000")
    parser.add_argument("out", nargs="?", type=Path, default=Path("/tmp/oktavarium-b45"))
    args = parser.parse_args()
    run(args.base.rstrip("/"), args.out)
