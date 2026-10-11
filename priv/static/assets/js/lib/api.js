// Klient API serwera. Sesja to ciasteczko HttpOnly; token CSRF dostajemy przy
// logowaniu i odsyłamy nagłówkiem przy żądaniach zmieniających stan.
import { buildEnvelope } from "./envelope.js";

export class ApiError extends Error {
  constructor(status, error) {
    super(describe(status, error));
    this.status = status;
    this.code = error?.code || "http_" + status;
    this.detail = error || {};
  }
}

const MESSAGES = {
  bad_seq: "Dziennik zmienił się w międzyczasie. Spróbuj jeszcze raz.",
  not_authorized: "Ten klucz nie ma do tego uprawnienia.",
  unauthenticated: "Nie jesteś zalogowany.",
  invalid_csrf: "Sesja wygasła. Zaloguj się ponownie.",
  registration_closed: "Rejestracja jest zamknięta. Potrzebujesz zaproszenia.",
  invalid_invite: "Zaproszenie jest nieważne albo zostało już wykorzystane.",
  handle_taken: "Ten uchwyt jest już zajęty.",
  blob_not_found: "Serwer nie ma jeszcze tego pliku.",
  media_type_mismatch: "Zawartość pliku nie pasuje do jego typu.",
  unsupported_media_type: "Ten typ pliku nie jest obsługiwany.",
  too_large: "Plik jest za duży.",
  already_member: "Ten klucz już jest dopisany.",
  already_revoked: "To uprawnienie zostało już cofnięte.",
  last_auth_key: "Nie można cofnąć ostatniego klucza logowania.",
  cannot_revoke_founding_key: "Klucza założycielskiego nie można cofnąć.",
  invalid_body: "Serwer odrzucił jedno z pól.",
};

function describe(status, error) {
  const base = MESSAGES[error?.code] || (error?.code ? `Błąd: ${error.code}` : `Błąd HTTP ${status}`);
  return error?.field ? `${base} (${error.field})` : base;
}

let csrf = null;
export const setCsrf = (token) => (csrf = token);

export async function api(method, path, { json, raw, type, headers = {} } = {}) {
  const h = { accept: "application/json", ...headers };
  if (csrf && method !== "GET") h["x-csrf-token"] = csrf;

  let body;
  if (json !== undefined) {
    h["content-type"] = "application/json";
    body = JSON.stringify(json);
  } else if (raw !== undefined) {
    h["content-type"] = type;
    body = raw;
  }

  const res = await fetch(path, { method, headers: h, body, credentials: "same-origin" });
  let data = null;
  try {
    data = await res.json();
  } catch {
    /* pusta odpowiedź */
  }
  if (!res.ok) throw new ApiError(res.status, data?.error);
  return data;
}

export const me = () => api("GET", "/api/me");
export const identities = async () => (await api("GET", "/api/identities")).identities;
export const identity = (ref) => api("GET", "/api/identities/" + encodeURIComponent(ref));

/** Logowanie podpisem klucza autoryzacji (`key` ze skarbca). */
export async function login(key, signLogin) {
  const c = await api("POST", "/api/session/challenge");
  const signature = await signLogin(c.message, key.private);
  const out = await api("POST", "/api/session", { json: { nonce: c.nonce, key: key.id, signature } });
  setCsrf(out.csrf);
  return out;
}

export async function logout() {
  await api("DELETE", "/api/session");
  setCsrf(null);
}

/** Wysyła blob (surowe bajty) i zwraca `{hash, size, media_type}`. */
export const uploadBlob = (bytes, type) => api("POST", "/api/blobs", { raw: bytes, type });

/** Podpisuje i wysyła zdarzenie do dziennika `identity`. `confirm` (opcjonalnie) dostaje
 *  to, co zostanie podpisane, i może odmówić. Przy `bad_seq` pobiera świeżą głowę
 *  i próbuje ponownie (maks. 3 razy): zdarzenie jest to samo, zmienia się tylko numer. */
export async function publish({ signer, identity: id, type, body, confirm }) {
  if (confirm && !(await confirm({ type, body, signer, identity: id }))) {
    const e = new Error("Anulowano.");
    e.cancelled = true;
    throw e;
  }
  for (let attempt = 0; ; attempt++) {
    const head = await api("GET", `/api/identities/${encodeURIComponent(id)}/head`);
    const { envelope } = await buildEnvelope({ signer, identity: id, seq: head.seq + 1, prev: head.id, type, body });
    try {
      return await api("POST", "/api/events", { json: envelope });
    } catch (e) {
      if (e.code !== "bad_seq" || attempt >= 2) throw e;
    }
  }
}

/** Zakłada tożsamość: podpisuje genesis kluczem założycielskim. */
export async function genesis({ founder, body, invite }) {
  const { envelope } = await buildEnvelope({ signer: founder, type: "identity.genesis", seq: 0, body });
  return api("POST", "/api/events", { json: envelope, headers: invite ? { "x-oktavarium-invite": invite } : {} });
}
