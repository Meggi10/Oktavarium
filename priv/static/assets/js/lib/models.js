function object(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function invalid() {
  throw new Error(
    "Nieprawid\u0142owa odpowied\u017A serwera. Spr\xF3buj ponownie.",
  );
}
const text = (value) => typeof value === "string";
const optionalText = (value) => value === null || text(value);
const recordOfText = (value) =>
  object(value) && Object.values(value).every(text);
const arrayOf = (value, check) => Array.isArray(value) && value.every(check);
const project = (value) =>
  object(value) &&
  text(value.id) &&
  text(value.slug) &&
  object(value.meta) &&
  recordOfText(value.meta) &&
  recordOfText(value.meta_refs) &&
  optionalText(value.site_url);
const resource = (value) =>
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
const key = (value) =>
  object(value) && text(value.key_id) && text(value.status);
const grant = (value) =>
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
function directoryResponse(value) {
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
  return value.identities;
}
function identityResponse(value) {
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
  return value;
}
function accessResponse(value) {
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
  return value;
}
function historyResponse(value) {
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
  return value.events;
}
export { accessResponse, directoryResponse, historyResponse, identityResponse };
