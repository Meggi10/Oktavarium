import test from "node:test";
import assert from "node:assert/strict";
import { generateKey, eventId } from "../../priv/static/assets/js/lib/crypto.js";
import { unb64u } from "../../priv/static/assets/js/lib/bytes.js";
import * as api from "../../priv/static/assets/js/lib/api.js";
import { validateVault, restoreBackup, Vault } from "../../priv/static/assets/js/lib/keystore.js";
import { validateFile } from "../../priv/static/assets/js/pages/studio-resources.js";
import { changeSummary } from "../../priv/static/assets/js/lib/ui.js";
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
const I = "A".repeat(43);
const body = { slug: "atlas", meta: { title: "Atlas" } };
const make = async () => ({ signer: await generateKey("signing", "Test"), identity: I, type: "project.create", body, head: { id: I, seq: 1 } });
const receipt = async envelope => ({ id: await eventId(unb64u(envelope.payload)), identity: I, seq: 2, envelope });

test("explicit form snapshot is used; no fresh head is silently substituted", async t => {
  let sent; const opts = await make();
  t.mock.method(globalThis, "fetch", async (path, req) => { assert.equal(req.method, "POST"); sent = JSON.parse(req.body); return json(await receipt(sent), 201); });
  await api.publish(opts); const payload = JSON.parse(Buffer.from(sent.payload, "base64url"));
  assert.equal(payload.seq, 2); assert.equal(payload.prev, I); assert.equal(api.pendingFor(I), null);
});
test("lost response retains the exact envelope; lookup resolves without a new POST", async t => {
  let sent, posts = 0; const opts = await make();
  t.mock.method(globalThis, "fetch", async (path, req) => {
    if (req.method === "POST") { posts++; sent = JSON.parse(req.body); throw new TypeError("offline"); }
    assert(path.includes("/events/")); return json(await receipt(sent));
  });
  await assert.rejects(api.publish(opts), e => e.code === "unknown_outcome");
  assert(api.pendingFor(I)); const out = await api.checkPending(I); assert.equal(out.id, await eventId(unb64u(sent.payload)));
  assert.equal(posts, 1); assert.equal(api.pendingFor(I), null);
});
test("404 lookup is not rejection; retry sends identical bytes and signature", async t => {
  const sent = []; const opts = await make(); let missing = true;
  t.mock.method(globalThis, "fetch", async (path, req) => {
    if (req.method === "GET") return missing ? json({ error: { code: "event_not_found" } }, 404) : json(await receipt(JSON.parse(sent[0])));
    sent.push(req.body); if (sent.length === 1) throw new TypeError("offline"); return json(await receipt(JSON.parse(req.body)), 201);
  });
  await assert.rejects(api.publish(opts), e => e.code === "unknown_outcome");
  assert.equal(await api.checkPending(I), null); assert(api.pendingFor(I));
  await assert.rejects(api.publish(opts), /poprzed/);
  await api.retryPending(I); assert.equal(sent.length, 2); assert.equal(sent[0], sent[1]); assert.equal(api.pendingFor(I), null);
});
test("duplicate retry is reconciled against the signed event receipt", async t => {
  let sent, n = 0; const opts = await make();
  t.mock.method(globalThis, "fetch", async (path, req) => {
    if (req.method === "GET") return json(await receipt(sent));
    n++; sent = JSON.parse(req.body); if (n === 1) throw new TypeError("lost"); return json({ error: { code: "duplicate_event" } }, 409);
  });
  await assert.rejects(api.publish(opts), e => e.code === "unknown_outcome"); await api.retryPending(I); assert.equal(n, 2); assert.equal(api.pendingFor(I), null);
});
test("wrong receipt cannot falsely resolve a pending write", async t => {
  let sent, correct = false; const opts = await make();
  t.mock.method(globalThis, "fetch", async (path, req) => {
    if (req.method === "POST") { sent = JSON.parse(req.body); throw new TypeError("lost"); }
    const r = await receipt(sent); if (!correct) r.envelope = { ...sent, signature: "wrong" }; return json(r);
  });
  await assert.rejects(api.publish(opts), e => e.code === "unknown_outcome");
  await assert.rejects(api.checkPending(I), /kopercie/); assert(api.pendingFor(I));
  correct = true; await api.checkPending(I);
});
test("known authorization failure does not create an unresolved write or retry", async t => {
  let n = 0; t.mock.method(globalThis, "fetch", async () => { n++; return json({ error: { code: "not_authorized" } }, 403); });
  await assert.rejects(api.publish(await make()), e => e.code === "not_authorized"); assert.equal(n, 1); assert.equal(api.pendingFor(I), null);
});
test("HTTP 500 remains uncertain until read-back, even if the body looks like an error", async t => {
  let sent; t.mock.method(globalThis, "fetch", async (path, req) => { if (req.method === "GET") return json(await receipt(sent)); sent = JSON.parse(req.body); return json({ error: { code: "internal_error" } }, 500); });
  await assert.rejects(api.publish(await make()), e => e.code === "unknown_outcome"); await api.checkPending(I);
});
test("genesis never requests a server session", async t => {
  const calls = []; t.mock.method(globalThis, "fetch", async (path, req) => { calls.push(path); const e = JSON.parse(req.body); const id = await eventId(unb64u(e.payload)); return json({ id, identity: id, seq: 0 }, 201); });
  await api.genesis({ founder: await generateKey("signing", "Founder"), body: { kind: "person", auth_keys: [] } });
  assert.deepEqual(calls, ["/api/events"]);
});
test("real encrypted backup round trip preserves public/private key pairing", async () => {
  const key = await generateKey("signing", "Backup"); const vault = Vault.empty("long-test-passphrase"); vault.add(key);
  const backup = await vault.backupFile(); const restored = await restoreBackup(backup, "long-test-passphrase");
  assert.deepEqual(restored.keys, [key]); assert(!JSON.stringify(backup).includes(key.private));
});
test("wrong password and unsupported backup version fail without saving", async () => {
  const vault = Vault.empty("long-test-passphrase"); vault.add(await generateKey("auth", "Auth")); const backup = await vault.backupFile();
  await assert.rejects(restoreBackup(backup, "wrong")); await assert.rejects(restoreBackup({ ...backup, v: 99 }, "long-test-passphrase"));
});
test("invalid decrypted key, duplicate ID, and unsupported vault schema are rejected", async () => {
  const a = await generateKey("signing", "A"), b = await generateKey("signing", "B");
  await assert.rejects(validateVault({ v: 1, keys: [a, a] }));
  await assert.rejects(validateVault({ v: 1, keys: [{ ...a, private: b.private }] }));
  await assert.rejects(validateVault({ v: 2, keys: [] })); await assert.rejects(validateVault({ v: 1, keys: "not-a-list" }));
});
test("file validation runs on supported types and size before upload", () => {
  assert.doesNotThrow(() => validateFile({ size: 10 }, "images/a.png", "image/png"));
  assert.throws(() => validateFile({ size: 10 }, "images/a.svg", "image/svg+xml"));
  assert.doesNotThrow(() => validateFile({ size: 10 }, "site/a.svg", "image/svg+xml"));
  assert.throws(() => validateFile({ size: 11 * 1024 * 1024 }, "images/a.png", "image/png"));
  assert.throws(() => validateFile({ size: 0 }, "images/a.png", "image/png"));
});
test("signature summary includes changed fields and the full recipient key", () => {
  const rows = changeSummary("profile.update", { fields: { bio: "New" } }, { data: { profile: { bio: "Old" } } });
  assert(rows.some(([, v]) => v.includes("Old") && v.includes("New")));
  const grant = changeSummary("grant.create", { subject: I, action: "resource.put", resource: I + "/projects/P/*", delegable: false });
  assert(grant.some(([, v]) => v === I)); assert(grant.some(([, v]) => v.includes("projects/P")));
});
