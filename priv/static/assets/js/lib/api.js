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
  project_not_empty: "Najpierw usuń lub przenieś pliki projektu.",
  project_slug_taken: "Projekt o tym slugu już istnieje.",
  resource_path_taken: "W tym miejscu istnieje już inny plik.",
  unknown_project: "Nie ma takiego projektu w tej tożsamości.",
  unknown_resource: "Zasób został usunięty albo należy do innej tożsamości.",
  not_covered: "Przekazywany zakres wykracza poza grant nadrzędny.",
  window_exceeds_parent: "Termin uprawnienia wykracza poza termin rodzica.",
  parent_not_delegable: "Ten grant nie pozwala na dalsze przekazywanie.",
  grant_inactive: "Grant nadrzędny nie jest już aktywny.",
  broken_chain: "Łańcuch uprawnień jest przerwany.",
  bad_prev:
    "Dziennik zmienił się. Odczytaj nowszy stan i ponownie sprawdź zamiar.",
  bad_seq:
    "Dziennik zmienił się w międzyczasie. Odśwież dane i ponownie sprawdź zmianę przed podpisaniem.",
  not_authorized: "Ten klucz nie ma do tego uprawnienia.",
  unauthenticated:
    "Do wysłania pliku potrzebna jest sesja autoryzacji. Odczyt pozostaje otwarty.",
  invalid_csrf:
    "Sesja przesyłania wygasła. Potwierdź ponowne uwierzytelnienie uploadu.",
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
  const base =
    MESSAGES[error?.code] ||
    (error?.code ? `Błąd: ${error.code}` : `Błąd HTTP ${status}`);
  return error?.field ? `${base} (${error.field})` : base;
}

let csrf = null;
export const setCsrf = (token) => (csrf = token);

export async function api(
  method,
  path,
  { json, raw, type, headers = {}, timeout = 30_000 } = {},
) {
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

  const res = await fetch(path, {
    method,
    headers: h,
    body,
    credentials: "same-origin",
    cache: "no-store",
    signal: AbortSignal.timeout(timeout),
  });
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
export const identities = async () =>
  (await api("GET", "/api/identities", { timeout: 10_000 })).identities;
export const identity = (ref) =>
  api("GET", "/api/identities/" + encodeURIComponent(ref), { timeout: 15_000 });

export const access = (ref, key) =>
  api(
    "GET",
    `/api/identities/${encodeURIComponent(ref)}/access/${encodeURIComponent(key)}`,
    { timeout: 12_000 },
  );
export const projects = (ref) =>
  api("GET", `/api/identities/${encodeURIComponent(ref)}/projects`);
export const project = (ref, id) =>
  api(
    "GET",
    `/api/identities/${encodeURIComponent(ref)}/projects/${encodeURIComponent(id)}`,
  );

/** Logowanie podpisem klucza autoryzacji (`key` ze skarbca). */
export async function login(key, signLogin) {
  const c = await api("POST", "/api/session/challenge");
  const signature = await signLogin(c.message, key.private);
  const out = await api("POST", "/api/session", {
    json: { nonce: c.nonce, key: key.id, signature },
  });
  setCsrf(out.csrf);
  return out;
}

export async function logout() {
  await api("DELETE", "/api/session");
  setCsrf(null);
}

/** Wysyła blob (surowe bajty) i zwraca `{hash, size, media_type}`. */
export const uploadBlob = (bytes, type) =>
  api("POST", "/api/blobs", { raw: bytes, type });

// Only in memory: signed attempts never contain private keys or passphrases.
// Keeping the exact envelope makes retries idempotent by event ID. Reloading the
// page loses this queue; the UI warns before leaving while an outcome is unknown.
const attempts = new Map();
export const pendingFor = (identity) => attempts.get(identity) || null;
export const hasPending = () => attempts.size > 0;

export class UnknownOutcome extends Error {
  constructor(attempt, cause) {
    super(
      "Nie otrzymano potwierdzenia zapisu. Najpierw sprawdź tę samą próbę w dzienniku.",
    );
    this.code = "unknown_outcome";
    this.attempt = attempt;
    this.cause = cause;
  }
}

async function submitAttempt(attempt, retry = false) {
  if (attempt.sending) throw new Error("Ta próba jest już wysyłana.");
  attempt.sending = true;
  try {
    const result = await api("POST", "/api/events", {
      json: attempt.envelope,
      headers: attempt.headers,
    });
    if (!result?.id) throw new Error("Niepełna odpowiedź serwera.");
    // Never report success for a receipt identifying another event.
    if (result.id !== attempt.id)
      throw new Error("Potwierdzenie dotyczy innego zdarzenia.");
    attempts.delete(attempt.identity);
    return result;
  } catch (e) {
    if (e.code === "duplicate_event") {
      try {
        const receipt = await checkPending(attempt.identity);
        if (receipt) return receipt;
      } catch {
        /* still indeterminate */
      }
    }
    if (
      !retry &&
      e instanceof ApiError &&
      e.status >= 400 &&
      e.status < 500 &&
      e.code !== "duplicate_event"
    ) {
      attempts.delete(attempt.identity);
      throw e;
    }
    attempt.unknown = true;
    throw new UnknownOutcome(attempt, e);
  } finally {
    attempt.sending = false;
  }
}

export async function checkPending(identity) {
  const p = pendingFor(identity);
  if (!p) return null;
  let receipt;
  try {
    receipt = await api(
      "GET",
      `/api/identities/${encodeURIComponent(identity)}/events/${encodeURIComponent(p.id)}`,
    );
  } catch (e) {
    if (e.status === 404) return null;
    throw e;
  }
  if (
    receipt?.id !== p.id ||
    receipt.identity !== p.identity ||
    receipt.envelope?.payload !== p.envelope.payload ||
    receipt.envelope?.signature !== p.envelope.signature ||
    receipt.envelope?.signer !== p.envelope.signer
  ) {
    throw new Error(
      "Odczytane potwierdzenie nie odpowiada podpisanej kopercie. Nie ponawiaj automatycznie.",
    );
  }
  attempts.delete(identity);
  return receipt;
}

export async function retryPending(identity) {
  const p = pendingFor(identity);
  if (!p) throw new Error("Nie ma nierozstrzygniętej próby.");
  return submitAttempt(p, true);
}

/** Confirm once. An explicit head is the snapshot the form was edited against. */
export async function publish({
  signer,
  identity: identityId,
  type,
  body,
  confirm,
  head,
}) {
  if (pendingFor(identityId))
    throw new Error("Najpierw rozstrzygnij poprzednią próbę zapisu.");
  if (
    confirm &&
    !(await confirm({ type, body, signer, identity: identityId }))
  ) {
    const e = new Error("Anulowano.");
    e.cancelled = true;
    throw e;
  }
  const base =
    head ||
    (await api(
      "GET",
      `/api/identities/${encodeURIComponent(identityId)}/head`,
    ));
  const built = await buildEnvelope({
    signer,
    identity: identityId,
    seq: base.seq + 1,
    prev: base.id,
    type,
    body,
  });
  const attempt = {
    ...built,
    identity: identityId,
    type,
    envelope: structuredClone(built.envelope),
    headers: {},
    sending: false,
  };
  attempts.set(identityId, attempt);
  return submitAttempt(attempt);
}

/** Genesis uses the same receipt/retry mechanism, and never creates a session. */
export async function genesis({ founder, body, invite }) {
  const built = await buildEnvelope({
    signer: founder,
    type: "identity.genesis",
    seq: 0,
    body,
  });
  const attempt = {
    ...built,
    identity: built.id,
    type: "identity.genesis",
    headers: invite ? { "x-oktavarium-invite": invite } : {},
    sending: false,
  };
  if (hasPending())
    throw new Error("Najpierw rozstrzygnij poprzedni zapis w tej karcie.");
  attempts.set(built.id, attempt);
  return submitAttempt(attempt);
}
