import test from "node:test";
import assert from "node:assert/strict";
import { covers, permits, delegatedBody, projectResource, fileResource } from "../../priv/static/assets/js/lib/permissions.js";
import { buildPath } from "../../priv/static/assets/js/pages/studio-resources.js";

const now = Date.parse("2026-10-11T12:00:00Z");
const parent = { id: "grant-1", action: "resource.*", resource: "I/projects/P/*", delegable: true,
  not_before: "2026-01-01T00:00:00Z", expires_at: "2099-01-01T00:00:00Z", revoked_at: null };
const access = { signing_key: true, founder: false, grants: [parent] };
const body = { subject: "recipient", action: "resource.put", resource: "I/projects/P/images/*" };

test("project metadata and files use stable ID namespaces", () => {
  assert.equal(projectResource("I", "P"), "I/projects/P");
  assert.equal(fileResource("I", "images/a.png", "P"), "I/projects/P/images/a.png");
  assert.equal(fileResource("I", "images/a.png", null), "I/images/a.png");
});
test("wildcard project grant includes the project node, not a sibling", () => {
  assert(covers({ action: "*", resource: "I/projects/P/*" }, { action: "project.update", resource: "I/projects/P" }));
  assert(!covers(parent, { action: "resource.put", resource: "I/projects/P2/images/a.png" }));
  assert(!covers(parent, { action: "resource.put", resource: "I/images/a.png" }));
});
test("action wildcard respects segment boundaries", () => {
  assert(covers(parent, body));
  assert(!covers(parent, { ...body, action: "resources.put" }));
  assert(!covers(parent, { ...body, action: "resource" }));
  assert(!covers(parent, { ...body, action: "*" }));
});
test("malformed patterns never grant access", () => {
  for (const resource of ["", "I//P", "I/*/P", "I/P*", null]) assert(!covers({ ...parent, resource }, body));
});
test("an unknown or auth-only key is not a writer even if marked founder", () => {
  assert(!permits({ signing_key: false, founder: true, grants: [] }, "project.update", "I/projects/P"));
});
test("a founder can write while an unprivileged key cannot", () => {
  assert(permits({ signing_key: true, founder: true, grants: [] }, "project.update", "I/projects/P"));
  assert(!permits({ signing_key: true, founder: false, grants: [] }, "project.update", "I/projects/P"));
});
test("child inherits both time boundaries and parent ID", () => {
  const child = delegatedBody(body, access, parent.id, now);
  assert.equal(child.parent_grant, parent.id);
  assert.equal(child.not_before, Date.parse(parent.not_before) / 1000);
  assert.equal(child.expires_at, Date.parse(parent.expires_at) / 1000);
});
test("delegation cannot widen action, project, or expiry", () => {
  assert.throws(() => delegatedBody({ ...body, action: "*" }, access, parent.id, now));
  assert.throws(() => delegatedBody({ ...body, resource: "I/projects/Q/*" }, access, parent.id, now));
  assert.throws(() => delegatedBody({ ...body, expires_at: Date.parse(parent.expires_at) / 1000 + 1 }, access, parent.id, now));
});
test("delegation refuses missing, expired, or non-delegable parents", () => {
  assert.throws(() => delegatedBody(body, access, null, now));
  for (const override of [{ delegable: false }, { revoked_at: "2026-01-01T00:00:00Z" }, { expires_at: "2026-01-01T00:00:00Z" }]) {
    assert.throws(() => delegatedBody(body, { ...access, grants: [{ ...parent, ...override }] }, parent.id, now));
  }
});
test("a founder issues a root grant without falsely naming a parent", () => {
  assert.deepEqual(delegatedBody(body, { signing_key: true, founder: true, grants: [] }, null, now), body);
  assert.throws(() => delegatedBody(body, { signing_key: true, founder: true, grants: [] }, parent.id, now));
});
test("a site path cannot traverse directories or exceed backend nesting", () => {
  assert.equal(buildPath("site", "css/app.css"), "site/css/app.css");
  assert.equal(buildPath("site", "../app.js"), null);
  assert.equal(buildPath("site", "a/b/c/d/e/f/g/h.js"), null);
  assert.equal(buildPath("site", "a/b/c/d/e/f/g.js"), "site/a/b/c/d/e/f/g.js");
  assert.equal(buildPath("site", "a".repeat(79) + "/" + "b".repeat(79) + "/" + "c".repeat(79)), null);
});
