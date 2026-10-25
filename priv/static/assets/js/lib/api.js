import { buildEnvelope } from "./envelope.js";
import {
  directoryResponse,
  identityResponse,
  accessResponse,
  historyResponse,
} from "./models.js";
class ApiError extends Error {
  status;
  code;
  detail;
  constructor(status, error = {}) {
    super(describe(status, error));
    this.status = status;
    this.code = error?.code || "http_" + status;
    this.detail = error || {};
  }
}
const MESSAGES = {
  project_not_empty: "Najpierw usu\u0144 lub przenie\u015B pliki projektu.",
  project_slug_taken: "Projekt o tym slugu ju\u017C istnieje.",
  resource_path_taken: "W tym miejscu istnieje ju\u017C inny plik.",
  unknown_project: "Nie ma takiego projektu w tej to\u017Csamo\u015Bci.",
  unknown_resource:
    "Zas\xF3b zosta\u0142 usuni\u0119ty albo nale\u017Cy do innej to\u017Csamo\u015Bci.",
  not_covered: "Przekazywany zakres wykracza poza grant nadrz\u0119dny.",
  window_exceeds_parent: "Termin uprawnienia wykracza poza termin rodzica.",
  parent_not_delegable: "Ten grant nie pozwala na dalsze przekazywanie.",
  grant_inactive: "Grant nadrz\u0119dny nie jest ju\u017C aktywny.",
  broken_chain: "\u0141a\u0144cuch uprawnie\u0144 jest przerwany.",
  bad_prev:
    "Dziennik zmieni\u0142 si\u0119. Odczytaj nowszy stan i ponownie sprawd\u017A zamiar.",
  bad_seq:
    "Dziennik zmieni\u0142 si\u0119 w mi\u0119dzyczasie. Od\u015Bwie\u017C dane i ponownie sprawd\u017A zmian\u0119 przed podpisaniem.",
  not_authorized: "Ten klucz nie ma do tego uprawnienia.",
  unauthenticated:
    "Do wys\u0142ania pliku potrzebna jest sesja autoryzacji. Odczyt pozostaje otwarty.",
  invalid_csrf:
    "Sesja przesy\u0142ania wygas\u0142a. Potwierd\u017A ponowne uwierzytelnienie uploadu.",
  registration_closed:
    "Rejestracja jest zamkni\u0119ta. Potrzebujesz zaproszenia.",
  invalid_invite:
    "Zaproszenie jest niewa\u017Cne albo zosta\u0142o ju\u017C wykorzystane.",
  handle_taken: "Ten uchwyt jest ju\u017C zaj\u0119ty.",
  blob_not_found: "Serwer nie ma jeszcze tego pliku.",
  media_type_mismatch: "Zawarto\u015B\u0107 pliku nie pasuje do jego typu.",
  unsupported_media_type: "Ten typ pliku nie jest obs\u0142ugiwany.",
  too_large: "Plik jest za du\u017Cy.",
  already_member: "Ten klucz ju\u017C jest dopisany.",
  already_revoked: "To uprawnienie zosta\u0142o ju\u017C cofni\u0119te.",
  last_auth_key: "Nie mo\u017Cna cofn\u0105\u0107 ostatniego klucza logowania.",
  cannot_revoke_founding_key:
    "Klucza za\u0142o\u017Cycielskiego nie mo\u017Cna cofn\u0105\u0107.",
  invalid_body: "Serwer odrzuci\u0142 jedno z p\xF3l.",
};
function describe(status, error) {
  const base =
    (error?.code && MESSAGES[error.code]) ||
    (error?.code
      ? `B\u0142\u0105d: ${error.code}`
      : `B\u0142\u0105d HTTP ${status}`);
  return error?.field ? `${base} (${error.field})` : base;
}
let csrf = null;
const setCsrf = (token) => (csrf = token);
async function api(
  method,
  path,
  { json, raw, type, headers = {}, timeout = 3e4 } = {},
) {
  const h = { accept: "application/json", ...headers };
  if (csrf && method !== "GET") h["x-csrf-token"] = csrf;
  let body;
  if (json !== void 0) {
    h["content-type"] = "application/json";
    body = JSON.stringify(json);
  } else if (raw !== void 0) {
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
  let data = null;
  try {
    data = await res.json();
  } catch {}
  if (!res.ok) {
    const problem =
      typeof data === "object" && data !== null && "error" in data
        ? data.error
        : void 0;
    throw new ApiError(
      res.status,
      typeof problem === "object" && problem !== null ? problem : {},
    );
  }
  return data;
}
const me = () => api("GET", "/api/me");
const identities = async () =>
  directoryResponse(await api("GET", "/api/identities", { timeout: 1e4 }));
const identity = async (ref) =>
  identityResponse(
    await api("GET", "/api/identities/" + encodeURIComponent(ref), {
      timeout: 15e3,
    }),
  );
const access = async (ref, key) =>
  accessResponse(
    await api(
      "GET",
      `/api/identities/${encodeURIComponent(ref)}/access/${encodeURIComponent(key)}`,
      { timeout: 12e3 },
    ),
  );
const projects = (ref) =>
  api("GET", `/api/identities/${encodeURIComponent(ref)}/projects`);
const project = (ref, id) =>
  api(
    "GET",
    `/api/identities/${encodeURIComponent(ref)}/projects/${encodeURIComponent(id)}`,
  );
const history = async (id) =>
  historyResponse(
    await api("GET", `/api/identities/${encodeURIComponent(id)}/events`),
  );
async function login(key, signLogin) {
  const c = await api("POST", "/api/session/challenge");
  const signature = await signLogin(c.message, key.private);
  const out = await api("POST", "/api/session", {
    json: { nonce: c.nonce, key: key.id, signature },
  });
  setCsrf(out.csrf);
  return out;
}
async function logout() {
  await api("DELETE", "/api/session");
  setCsrf(null);
}
const uploadBlob = (bytes, type) =>
  api("POST", "/api/blobs", { raw: new Uint8Array(bytes), type });
const attempts = /* @__PURE__ */ new Map();
const pendingFor = (identity2) => attempts.get(identity2 || "") || null;
const hasPending = () => attempts.size > 0;
class UnknownOutcome extends Error {
  code = "unknown_outcome";
  attempt;
  constructor(attempt, cause) {
    super(
      "Nie otrzymano potwierdzenia zapisu. Najpierw sprawd\u017A t\u0119 sam\u0105 pr\xF3b\u0119 w dzienniku.",
    );
    this.attempt = attempt;
    this.cause = cause;
  }
}
async function submitAttempt(attempt, retry = false) {
  if (attempt.sending)
    throw new Error("Ta pr\xF3ba jest ju\u017C wysy\u0142ana.");
  attempt.sending = true;
  try {
    const result = await api("POST", "/api/events", {
      json: attempt.envelope,
      headers: attempt.headers,
    });
    if (!result?.id) throw new Error("Niepe\u0142na odpowied\u017A serwera.");
    if (result.id !== attempt.id)
      throw new Error("Potwierdzenie dotyczy innego zdarzenia.");
    attempts.delete(attempt.identity);
    return result;
  } catch (e) {
    if (e instanceof ApiError && e.code === "duplicate_event") {
      try {
        const receipt = await checkPending(attempt.identity);
        if (receipt) return receipt;
      } catch {}
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
async function checkPending(identity2) {
  const p = pendingFor(identity2);
  if (!p) return null;
  let receipt;
  try {
    receipt = await api(
      "GET",
      `/api/identities/${encodeURIComponent(identity2)}/events/${encodeURIComponent(p.id)}`,
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
  attempts.delete(identity2);
  return receipt;
}
async function retryPending(identity2) {
  const p = pendingFor(identity2);
  if (!p) throw new Error("Nie ma nierozstrzygni\u0119tej pr\xF3by.");
  return submitAttempt(p, true);
}
async function publish({
  signer,
  identity: identityId,
  type,
  body,
  confirm,
  head,
}) {
  if (pendingFor(identityId))
    throw new Error(
      "Najpierw rozstrzygnij poprzedni\u0105 pr\xF3b\u0119 zapisu.",
    );
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
async function genesis({ founder, body, invite }) {
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
export {
  ApiError,
  UnknownOutcome,
  access,
  api,
  checkPending,
  genesis,
  hasPending,
  history,
  identities,
  identity,
  login,
  logout,
  me,
  pendingFor,
  project,
  projects,
  publish,
  retryPending,
  setCsrf,
  uploadBlob,
};
