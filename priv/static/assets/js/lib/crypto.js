import * as ed from "../vendor/noble-ed25519.js";
import { b64u, unb64u, concat, enc } from "./bytes.js";
const DOMAIN = {
  event: "oktavarium/event/v1\0",
  login: "oktavarium/login/v1\0",
  eventId: "oktavarium/event-id/v1\0",
};
async function generateKey(kind, label) {
  const priv = crypto.getRandomValues(new Uint8Array(32));
  const pub = await ed.getPublicKeyAsync(priv);
  return {
    id: b64u(pub),
    kind,
    private: b64u(priv),
    label: label || null,
    created: Date.now(),
  };
}
async function sign(domain, message, privateB64) {
  const sig = await ed.signAsync(
    concat(enc.encode(DOMAIN[domain]), message),
    unb64u(privateB64),
  );
  return b64u(sig);
}
async function verify(domain, message, signatureB64, keyId) {
  return ed.verifyAsync(
    unb64u(signatureB64),
    concat(enc.encode(DOMAIN[domain]), message),
    unb64u(keyId),
  );
}
async function sha256(bytes) {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
  );
}
async function eventId(payload) {
  return b64u(await sha256(concat(enc.encode(DOMAIN.eventId), payload)));
}
async function publicFromPrivate(privateB64) {
  return b64u(await ed.getPublicKeyAsync(unb64u(privateB64)));
}
export { eventId, generateKey, publicFromPrivate, sha256, sign, verify };
