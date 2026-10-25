const enc = new TextEncoder();
const dec = new TextDecoder();
function b64u(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 32768) {
    s += String.fromCharCode(...bytes.subarray(i, i + 32768));
  }
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
function unb64u(text) {
  const pad = "=".repeat((4 - (text.length % 4)) % 4);
  const bin = atob(text.replaceAll("-", "+").replaceAll("_", "/") + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}
function hex(bytes) {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const short = (id) =>
  id && id.length > 14 ? id.slice(0, 6) + "\u2026" + id.slice(-5) : id || "";
export { b64u, concat, dec, enc, hex, short, unb64u };
