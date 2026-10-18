import test from "node:test";
import assert from "node:assert/strict";
import { AVATAR_PATH, avatarMediaType } from "../../priv/static/assets/js/lib/avatar.js";
import { abbreviate } from "../../priv/static/assets/js/lib/copy-id.js";

test("profile photo uses one stable root path, valid for both PNG and JPEG", () => {
  assert.equal(AVATAR_PATH, "images/avatar");
  assert.equal(avatarMediaType({ name: "me.png", type: "image/png", size: 1024 }), "image/png");
  assert.equal(avatarMediaType({ name: "me.jpg", type: "image/jpeg", size: 1024 }), "image/jpeg");
  assert.equal(avatarMediaType({ name: "me.webp", type: "image/webp", size: 1024 }), "image/webp");
});

test("profile photo rejects executable images, MIME mismatches, zero bytes and oversize", () => {
  for (const f of [
    { name: "face.svg", type: "image/svg+xml", size: 123 },
    { name: "face.png", type: "text/html", size: 123 },
    { name: "face.gif", type: "image/gif", size: 123 },
    { name: "face.png", type: "image/png", size: 0 },
    { name: "face.png", type: "image/png", size: 11 * 1024 * 1024 },
  ]) assert.throws(() => avatarMediaType(f));
});

test("copy label abbreviates long keys and hashes without mutating the copied value", () => {
  const key = "A".repeat(43);
  const sha = "f".repeat(64);
  assert.equal(abbreviate(key), "AAAAAA…AAAA");
  assert.equal(abbreviate(sha), "ffffff…ffff");
  assert.equal(abbreviate("short"), "short");
});
