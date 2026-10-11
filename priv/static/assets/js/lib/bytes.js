// Pomocnicze funkcje na bajtach i base64url (bez paddingu), jak w Oktavarium.Crypto.

export const enc = new TextEncoder();
export const dec = new TextDecoder();

export function b64u(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function unb64u(text) {
  const pad = "=".repeat((4 - (text.length % 4)) % 4);
  const bin = atob(text.replaceAll("-", "+").replaceAll("_", "/") + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

export function hex(bytes) {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const short = (id) => (id && id.length > 14 ? id.slice(0, 6) + "…" + id.slice(-5) : id || "");
