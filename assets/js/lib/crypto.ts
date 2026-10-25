// Ed25519 w przeglądarce i separacja domen identyczna jak w Oktavarium.Crypto.
import * as ed from "../vendor/noble-ed25519.js";
import { b64u, unb64u, concat, enc } from "./bytes.js";
import type { VaultKey } from "./keystore.js";

const DOMAIN = {
  event: "oktavarium/event/v1\0",
  login: "oktavarium/login/v1\0",
  eventId: "oktavarium/event-id/v1\0",
};

/** Nowa para kluczy: `{id, kind, private, created}` (id = klucz publiczny, base64url). */
export async function generateKey(
  kind: VaultKey["kind"],
  label?: string,
): Promise<VaultKey> {
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

/** Podpis `message` (bajty) w domenie; zwraca base64url. */
export async function sign(
  domain: "event" | "login",
  message: Uint8Array,
  privateB64: string,
): Promise<string> {
  const sig = await ed.signAsync(
    concat(enc.encode(DOMAIN[domain]), message),
    unb64u(privateB64),
  );
  return b64u(sig);
}

export async function verify(
  domain: "event" | "login",
  message: Uint8Array,
  signatureB64: string,
  keyId: string,
): Promise<boolean> {
  return ed.verifyAsync(
    unb64u(signatureB64),
    concat(enc.encode(DOMAIN[domain]), message),
    unb64u(keyId),
  );
}

export async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
  );
}

/** Identyfikator zdarzenia = skrót ładunku w domenie `event-id`. */
export async function eventId(payload: Uint8Array): Promise<string> {
  return b64u(await sha256(concat(enc.encode(DOMAIN.eventId), payload)));
}

export async function publicFromPrivate(privateB64: string): Promise<string> {
  return b64u(await ed.getPublicKeyAsync(unb64u(privateB64)));
}
