// Public JSON contracts consumed by Studio. These are projections, not signed payloads.
export type DirectoryEntry = {
  id: string;
  handle: string | null;
  kind: "person" | "collective";
  display_name: string | null;
  avatar_url: string | null;
};

export type Head = { seq: number; id: string };
export type Project = {
  id: string;
  slug: string;
  meta: { title?: string; description?: string };
  meta_refs: Record<string, string>;
  site_url: string | null;
  scope?: string;
};
export type Resource = {
  id: string;
  project_id: string | null;
  path: string;
  kind: "image" | "audio" | "site";
  available: boolean;
  hash: string;
  size: number;
  media_type: string;
  meta: Record<string, string>;
  meta_refs: Record<string, string>;
};
export type Grant = {
  id: string;
  action: string;
  resource: string;
  delegable: boolean;
  issuer_key_id: string;
  subject_key_id: string;
  parent_grant_id: string | null;
  status: string;
  not_before: string | null;
  expires_at: string | null;
  revoked_at: string | null;
};
export type IdentityDetails = {
  id: string;
  handle: string | null;
  kind: "person" | "collective";
  visibility: "public" | "unlisted";
  profile: Record<string, string>;
  profile_refs: Record<string, string>;
  avatar_url: string | null;
  founding_key: string;
  auth_keys: Array<{ key_id: string; status: string }>;
  members: Array<{ key_id: string; label: string | null; status: string }>;
  grants: Grant[];
  resources: Resource[];
  projects: Project[];
  site_url: string | null;
  integrity: "ok" | "error";
  head: Head;
};
export type AccessSnapshot = {
  identity: string;
  key: string;
  signing_key: boolean;
  founder: boolean;
  grants: Grant[];
  checked_at: string;
};
export type SignedEnvelope = {
  payload: string;
  signer: string;
  signature: string;
};
export type Receipt = {
  id: string;
  identity: string;
  seq: number;
  type: string;
  envelope?: SignedEnvelope;
};
export type UploadSession = { key: string; csrf: string; identities: string[] };

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function invalid(): never {
  throw new Error("Nieprawidłowa odpowiedź serwera. Spróbuj ponownie.");
}

const text = (value: unknown): value is string => typeof value === "string";
const optionalText = (value: unknown): value is string | null =>
  value === null || text(value);
const recordOfText = (value: unknown): value is Record<string, string> =>
  object(value) && Object.values(value).every(text);
const arrayOf = (value: unknown, check: (item: unknown) => boolean): boolean =>
  Array.isArray(value) && value.every(check);
const project = (value: unknown): boolean =>
  object(value) &&
  text(value.id) &&
  text(value.slug) &&
  object(value.meta) &&
  recordOfText(value.meta) &&
  recordOfText(value.meta_refs) &&
  optionalText(value.site_url);
const resource = (value: unknown): boolean =>
  object(value) &&
  text(value.id) &&
  text(value.path) &&
  optionalText(value.project_id) &&
  ["image", "audio", "site"].includes(String(value.kind)) &&
  typeof value.available === "boolean" &&
  text(value.hash) &&
  typeof value.size === "number" &&
  text(value.media_type) &&
  recordOfText(value.meta) &&
  recordOfText(value.meta_refs);
const key = (value: unknown): boolean =>
  object(value) && text(value.key_id) && text(value.status);
const grant = (value: unknown): boolean =>
  object(value) &&
  text(value.id) &&
  text(value.action) &&
  text(value.resource) &&
  typeof value.delegable === "boolean" &&
  text(value.status) &&
  text(value.issuer_key_id) &&
  text(value.subject_key_id) &&
  optionalText(value.parent_grant_id) &&
  optionalText(value.not_before) &&
  optionalText(value.expires_at) &&
  optionalText(value.revoked_at);

// Check the fields used for navigation and permissions before showing a response.
// Detailed validation of individual metadata values remains server-owned.
export function directoryResponse(value: unknown): DirectoryEntry[] {
  if (!object(value) || !Array.isArray(value.identities)) return invalid();
  if (
    !value.identities.every(
      (entry) =>
        object(entry) &&
        text(entry.id) &&
        optionalText(entry.handle) &&
        optionalText(entry.display_name) &&
        optionalText(entry.avatar_url) &&
        ["person", "collective"].includes(String(entry.kind)),
    )
  )
    return invalid();
  return value.identities as DirectoryEntry[];
}

export function identityResponse(value: unknown): IdentityDetails {
  if (
    !object(value) ||
    !text(value.id) ||
    !optionalText(value.handle) ||
    !["person", "collective"].includes(String(value.kind)) ||
    !["public", "unlisted"].includes(String(value.visibility)) ||
    !recordOfText(value.profile) ||
    !recordOfText(value.profile_refs) ||
    !optionalText(value.avatar_url) ||
    !text(value.founding_key) ||
    !arrayOf(value.projects, project) ||
    !arrayOf(value.resources, resource) ||
    !arrayOf(value.grants, grant) ||
    !arrayOf(value.auth_keys, key) ||
    !arrayOf(
      value.members,
      (m) => key(m) && object(m) && optionalText(m.label),
    ) ||
    !optionalText(value.site_url) ||
    !["ok", "error"].includes(String(value.integrity)) ||
    !object(value.head) ||
    !Number.isInteger(value.head.seq) ||
    !text(value.head.id)
  )
    return invalid();
  return value as IdentityDetails;
}

export function accessResponse(value: unknown): AccessSnapshot {
  if (
    !object(value) ||
    !text(value.identity) ||
    !text(value.key) ||
    typeof value.signing_key !== "boolean" ||
    typeof value.founder !== "boolean" ||
    !arrayOf(value.grants, grant) ||
    !text(value.checked_at)
  )
    return invalid();
  return value as AccessSnapshot;
}

export function historyResponse(value: unknown): SignedEnvelope[] {
  if (
    !object(value) ||
    !Array.isArray(value.events) ||
    !value.events.every(
      (e) =>
        object(e) &&
        typeof e.payload === "string" &&
        typeof e.signer === "string" &&
        typeof e.signature === "string",
    )
  )
    return invalid();
  return value.events as SignedEnvelope[];
}
