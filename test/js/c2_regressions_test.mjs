import test from "node:test";
import assert from "node:assert/strict";
import * as api from "../../priv/static/assets/js/lib/api.js";
import { changeSummary } from "../../priv/static/assets/js/lib/ui.js";

const id = "A".repeat(43);
const response = (body) => new Response(JSON.stringify(body), {
  status: 200,
  headers: { "content-type": "application/json" },
});
const identityDetails = {
  id, handle: null, kind: "person", visibility: "public",
  profile: {}, profile_refs: {}, avatar_url: null, founding_key: id,
  auth_keys: [], members: [], grants: [], resources: [], projects: [],
  site_url: null, integrity: "ok", head: { seq: 0, id },
};
const accessSnapshot = {
  identity: id, key: id, signing_key: false, founder: false,
  grants: [], checked_at: "2026-10-24T00:00:00Z",
};

test("public requests respect their own timeouts rather than always waiting 30 seconds", async (t) => {
  const seen = [];
  const controller = new AbortController();
  t.mock.method(AbortSignal, "timeout", (ms) => {
    seen.push(ms);
    return controller.signal;
  });
  t.mock.method(globalThis, "fetch", async (path) => {
    if (path === "/api/identities") return response({ identities: [] });
    return response(path.includes("/access/") ? accessSnapshot : identityDetails);
  });
  assert.deepEqual(await api.identities(), []);
  await api.identity(id);
  await api.access(id, id);
  assert.deepEqual(seen, [10_000, 15_000, 12_000]);
});

test("display name has an independent human-readable signed profile field", () => {
  const original = { handle: "przesmyk", profile: {} };
  assert.deepEqual(
    changeSummary("profile.update", { fields: { display_name: "Pracownia Północ" } }, { data: original }),
    [["Nazwa wyświetlana", "(brak) → Pracownia Północ"]],
  );
});
