// UI guidance only. Every signed write is authorized again by the server.
function validPattern(value, sep) {
  if (typeof value !== "string" || !value) return false;
  const parts = value.split(sep);
  return parts.every(
    (s, i) => s && (!s.includes("*") || (s === "*" && i === parts.length - 1)),
  );
}

export function covers(parent, child) {
  if (
    !validPattern(parent?.action, ".") ||
    !validPattern(child?.action, ".") ||
    !validPattern(parent?.resource, "/") ||
    !validPattern(child?.resource, "/")
  )
    return false;
  const a = parent.action;
  const action =
    a === "*" ||
    a === child.action ||
    (a.endsWith(".*") && child.action.startsWith(a.slice(0, -1)));
  const p = parent.resource.split("/"),
    c = child.resource.split("/");
  const resource =
    p.every((part, i) => part === "*" || part === c[i]) &&
    (p.at(-1) === "*" || p.length === c.length);
  return action && resource;
}

export function active(grant, now = Date.now()) {
  return (
    (!grant.not_before || Date.parse(grant.not_before) <= now) &&
    (!grant.expires_at || Date.parse(grant.expires_at) > now) &&
    (!grant.revoked_at || Date.parse(grant.revoked_at) > now)
  );
}

export function permits(access, action, resource) {
  if (!access?.signing_key) return false;
  return (
    access.founder ||
    access.grants.some((g) => active(g) && covers(g, { action, resource }))
  );
}

export const projectResource = (identity, project) =>
  `${identity}/projects/${project}`;
export const fileResource = (identity, path, project = null) =>
  (project ? projectResource(identity, project) : identity) + "/" + path;

// Inherit a parent's time window, unless a narrower one was requested explicitly.
export function delegatedBody(body, access, parentId, now = Date.now()) {
  if (!access?.signing_key)
    throw new Error("Wybierz aktywny klucz sygnowania.");
  if (access.founder) {
    if (parentId)
      throw new Error(
        "Klucz za\u0142o\u017cycielski nie wskazuje grantu nadrz\u0119dnego.",
      );
    return { ...body };
  }
  const parent = access.grants.find(
    (g) => g.id === parentId && g.delegable && active(g, now),
  );
  if (!parent)
    throw new Error(
      "Wybierz aktywny grant, kt\u00f3ry pozwala przekazywa\u0107 uprawnienia dalej.",
    );
  if (!covers(parent, body))
    throw new Error("Zakres lub akcja wykracza poza grant nadrz\u0119dny.");
  const child = { ...body, parent_grant: parent.id };
  for (const field of ["not_before", "expires_at"]) {
    if (parent[field] && child[field] == null)
      child[field] = Math.floor(Date.parse(parent[field]) / 1000);
  }
  if (
    (parent.not_before &&
      child.not_before < Date.parse(parent.not_before) / 1000) ||
    (parent.expires_at &&
      child.expires_at > Date.parse(parent.expires_at) / 1000)
  ) {
    throw new Error(
      "Okno czasowe nie mo\u017ce wykracza\u0107 poza grant nadrz\u0119dny.",
    );
  }
  if (
    child.expires_at != null &&
    child.expires_at <= (child.not_before ?? Math.floor(now / 1000))
  ) {
    throw new Error(
      "Termin wyga\u015bni\u0119cia musi by\u0107 p\u00f3\u017aniejszy ni\u017c pocz\u0105tek dost\u0119pu.",
    );
  }
  return child;
}
