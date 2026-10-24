import test from "node:test";
import assert from "node:assert/strict";
import { generateKey, eventId } from "../../priv/static/assets/js/lib/crypto.js";
import { publish, access, project, setCsrf } from "../../priv/static/assets/js/lib/api.js";

const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

test("public reads require neither login nor a CSRF token", async (t) => {
  const calls = [];
  t.mock.method(globalThis, "fetch", async (path, options) => {
    calls.push({ path, options });
    return json(path.includes("/access/")
      ? { identity: "person", key: "key", signing_key: false, founder: false, grants: [], checked_at: "2026-10-24T00:00:00Z" }
      : { identity: "person", project: { id: "project", slug: "project", meta: {}, meta_refs: {}, site_url: null }, resources: [] });
  });
  setCsrf(null);
  await access("person", "key");
  await project("person", "project");
  assert.equal(calls.length, 2);
  for (const { options } of calls) {
    assert.equal(options.method, "GET");
    assert(!("x-csrf-token" in options.headers));
  }
});

test("cancelled signing makes no HTTP request", async (t) => {
  const calls = [];
  t.mock.method(globalThis, "fetch", async (...args) => { calls.push(args); return json({}); });
  await assert.rejects(() => publish({ signer: {}, identity: "I", type: "project.delete", body: {}, confirm: async () => false }), e => e.cancelled);
  assert.equal(calls.length, 0);
});

test("a sequence conflict is surfaced instead of re-signing silently", async (t) => {
  const calls = [];
  const signer = await generateKey("signing", "test");
  const identity = "A".repeat(43);
  t.mock.method(globalThis, "fetch", async (path, options) => {
    calls.push({ path, options });
    return options.method === "GET" ? json({ seq: 2, id: identity }) : json({ error: { code: "bad_seq", expected_seq: 4 } }, 409);
  });
  await assert.rejects(() => publish({ signer, identity, type: "project.delete", body: { id: identity } }), e => e.code === "bad_seq");
  assert.equal(calls.filter(c => c.options.method === "POST").length, 1);
  assert.equal(calls.length, 2);
});

test("v2 project signatures include detached text attachments", async (t) => {
  const signer = await generateKey("signing", "test");
  const identity = "A".repeat(43);
  let sent;
  t.mock.method(globalThis, "fetch", async (_path, options) => {
    if (options.method === "GET") return json({ seq: 0, id: identity });
    sent = JSON.parse(options.body);
    return json({ id: await eventId(new Uint8Array(Buffer.from(sent.payload, "base64url"))), seq: 1 }, 201);
  });
  await publish({ signer, identity, type: "project.create", body: { slug: "atlas", meta: { title: "Atlas" } } });
  const payload = JSON.parse(Buffer.from(sent.payload, "base64url").toString("utf8"));
  assert.equal(payload.v, 2);
  const hash = payload.body.meta.title.sha256;
  assert.equal(hash.length, 64);
  assert(!JSON.stringify(payload).includes('"title":"Atlas"'));
  assert.equal(sent.attachments[hash], "Atlas");
});
