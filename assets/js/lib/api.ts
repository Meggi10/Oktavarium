// Klient API serwera. Sesja to ciasteczko HttpOnly; token CSRF dostajemy przy
// logowaniu i odsyłamy nagłówkiem przy żądaniach zmieniających stan.
import { buildEnvelope } from "./envelope.js";
import {
  directoryResponse,
  identityResponse,
  accessResponse,
  historyResponse,
} from "./models.js";
import type {
  AccessSnapshot,
  IdentityDetails,
  Project,
  Receipt,
  SignedEnvelope,
  UploadSession,
} from "./models.js";
import type { VaultKey } from "./keystore.js";

export class ApiError extends Error {
  status: number;
  code: string;
  detail: ApiProblem;
  constructor(status: number, error: ApiProblem = {}) {
    super(describe(status, error));
    this.status = status;
    this.code = error?.code || "http_" + status;
    this.detail = error || {};
  }
}

type ApiProblem = { code?: string; field?: string; [key: string]: unknown };
type ApiOptions = {
  json?: unknown;
  raw?: BodyInit;
  type?: string;
  headers?: Record<string, string>;
  timeout?: number;
};
type Attempt = {
  id: string;
  identity: string;
  envelope: { payload: string; signature: string; signer: string };
  headers: Record<string, string>;
  sending: boolean;
  unknown?: boolean;
};

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

function describe(status: number, error: ApiProblem) {
  const base =
    (error?.code && MESSAGES[error.code as keyof typeof MESSAGES]) ||
    (error?.code ? `Błąd: ${error.code}` : `Błąd HTTP ${status}`);
  return error?.field ? `${base} (${error.field})` : base;
}

let csrf: string | null = null;
export const setCsrf = (token: string | null) => (csrf = token);

export async function api<T = unknown>(
  method: "GET" | "POST" | "DELETE",
  path: string,
  { json, raw, type, headers = {}, timeout = 30_000 }: ApiOptions = {},
): Promise<T> {
  const h: Record<string, string> = { accept: "application/json", ...headers };
  if (csrf && method !== "GET") h["x-csrf-token"] = csrf;

  let body;
  if (json !== undefined) {
    h["content-type"] = "application/json";
    body = JSON.stringify(json);
  } else if (raw !== undefined) {
    h["content-type"] = type || "application/octet-stream";
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
  let data: unknown = null;
  try {
    data = await res.json();
  } catch {
    /* pusta odpowiedź */
  }
  if (!res.ok) {
    const problem =
      typeof data === "object" && data !== null && "error" in data
        ? data.error
        : undefined;
    throw new ApiError(
      res.status,
      typeof problem === "object" && problem !== null
        ? (problem as ApiProblem)
        : {},
    );
  }
  return data as T;
}

export const me = () => api<UploadSession>("GET", "/api/me");
export const identities = async () =>
  directoryResponse(await api("GET", "/api/identities", { timeout: 10_000 }));
export const identity = async (ref: string): Promise<IdentityDetails> =>
  identityResponse(
    await api("GET", "/api/identities/" + encodeURIComponent(ref), {
      timeout: 15_000,
    }),
  );

export const access = async (
  ref: string,
  key: string,
): Promise<AccessSnapshot> =>
  accessResponse(
    await api(
      "GET",
      `/api/identities/${encodeURIComponent(ref)}/access/${encodeURIComponent(key)}`,
      { timeout: 12_000 },
    ),
  );
export const projects = (ref: string) =>
  api<{ identity: string; projects: Project[] }>(
    "GET",
    `/api/identities/${encodeURIComponent(ref)}/projects`,
  );
export const project = (ref: string, id: string) =>
  api<{ identity: string; project: Project }>(
    "GET",
    `/api/identities/${encodeURIComponent(ref)}/projects/${encodeURIComponent(id)}`,
  );
export const history = async (id: string): Promise<SignedEnvelope[]> =>
  historyResponse(
    await api("GET", `/api/identities/${encodeURIComponent(id)}/events`),
  );

/** Logowanie podpisem klucza autoryzacji (`key` ze skarbca). */
export async function login(
  key: VaultKey,
  signLogin: (message: string, privateKey: string) => Promise<string>,
): Promise<UploadSession> {
  const c = await api<{ nonce: string; message: string }>(
    "POST",
    "/api/session/challenge",
  );
  const signature = await signLogin(c.message, key.private);
  const out = await api<UploadSession>("POST", "/api/session", {
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
export const uploadBlob = (bytes: Uint8Array, type: string) =>
  api<{ hash: string; size: number; media_type: string }>(
    "POST",
    "/api/blobs",
    { raw: new Uint8Array(bytes), type },
  );

// Only in memory: signed attempts never contain private keys or passphrases.
// Keeping the exact envelope makes retries idempotent by event ID. Reloading the
// page loses this queue; the UI warns before leaving while an outcome is unknown.
const attempts = new Map<string, Attempt>();
export const pendingFor = (identity: string | null) =>
  attempts.get(identity || "") || null;
export const hasPending = () => attempts.size > 0;

export class UnknownOutcome extends Error {
  code = "unknown_outcome";
  attempt: Attempt;
  constructor(attempt: Attempt, cause: unknown) {
    super(
      "Nie otrzymano potwierdzenia zapisu. Najpierw sprawdź tę samą próbę w dzienniku.",
    );
    this.attempt = attempt;
    this.cause = cause;
  }
}

async function submitAttempt(attempt: Attempt, retry = false) {
  if (attempt.sending) throw new Error("Ta próba jest już wysyłana.");
  attempt.sending = true;
  try {
    const result = await api<Receipt>("POST", "/api/events", {
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
    if (e instanceof ApiError && e.code === "duplicate_event") {
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

export async function checkPending(identity: string) {
  const p = pendingFor(identity);
  if (!p) return null;
  let receipt;
  try {
    receipt = await api<Receipt>(
      "GET",
      `/api/identities/${encodeURIComponent(identity)}/events/${encodeURIComponent(p.id)}`,
    );
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) return null;
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

export async function retryPending(identity: string) {
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
}: {
  signer: { id: string; private: string };
  identity: string;
  type: string;
  body: Record<string, any>;
  confirm?: (details: any) => Promise<boolean>;
  head?: { seq: number; id: string };
}) {
  if (pendingFor(identityId))
    throw new Error("Najpierw rozstrzygnij poprzednią próbę zapisu.");
  if (
    confirm &&
    !(await confirm({ type, body, signer, identity: identityId }))
  ) {
    const e = new Error("Anulowano.") as Error & { cancelled: boolean };
    e.cancelled = true;
    throw e;
  }
  const base =
    head ||
    (await api<{ seq: number; id: string }>(
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
export async function genesis({
  founder,
  body,
  invite,
}: {
  founder: VaultKey;
  body: Record<string, unknown>;
  invite?: string;
}) {
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
    headers: invite
      ? { "x-oktavarium-invite": invite }
      : ({} as Record<string, string>),
    sending: false,
  };
  if (hasPending())
    throw new Error("Najpierw rozstrzygnij poprzedni zapis w tej karcie.");
  attempts.set(built.id, attempt);
  return submitAttempt(attempt);
}
