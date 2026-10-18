// Koperta v2: podpisujemy referencje SHA-256, nie tekst profilu i opisów.
// Tekst jedzie obok jako attachments; serwer weryfikuje jego skrót, po czym
// zapisuje go oddzielnie. Replikacja podpisanego dziennika nie zawiera tekstu.
import { b64u, enc, hex } from "./bytes.js";
import { sign, eventId, sha256 } from "./crypto.js";

async function detach(type, original) {
  const name =
    type === "profile.update"
      ? "fields"
      : ["resource.put", "project.create", "project.update"].includes(type)
        ? "meta"
        : null;

  if (
    !name ||
    !original ||
    typeof original[name] !== "object" ||
    original[name] === null ||
    Array.isArray(original[name])
  ) {
    return { body: original, attachments: {} };
  }

  const refs = {};
  const attachments = {};
  for (const [field, value] of Object.entries(original[name])) {
    if (typeof value === "string") {
      const digest = hex(await sha256(enc.encode(value)));
      refs[field] = { sha256: digest };
      attachments[digest] = value;
    } else {
      refs[field] = value;
    }
  }
  return { body: { ...original, [name]: refs }, attachments };
}

/** `{signer, identity, seq, prev, type, body, ts?}` -> `{envelope, id}`. */
export async function buildEnvelope({
  signer,
  identity = null,
  seq,
  prev = null,
  type,
  body,
  ts,
}) {
  const detached = await detach(type, body);
  const payload = enc.encode(
    JSON.stringify({
      v: 2,
      signer: signer.id,
      identity,
      seq,
      prev,
      type,
      body: detached.body,
      ts: ts ?? Math.floor(Date.now() / 1000),
    }),
  );

  const signature = await sign("event", payload, signer.private);
  return {
    id: await eventId(payload),
    envelope: {
      payload: b64u(payload),
      signer: signer.id,
      signature,
      ...(Object.keys(detached.attachments).length
        ? { attachments: detached.attachments }
        : {}),
    },
  };
}
