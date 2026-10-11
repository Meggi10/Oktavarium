// Budowa i podpisywanie kopert zdarzeń. Ładunek to surowe bajty JSON; serwer
// weryfikuje dokładnie to, co podpisaliśmy, więc kolejność pól nie ma znaczenia.
import { b64u, enc } from "./bytes.js";
import { sign, eventId } from "./crypto.js";

/** `{signer, identity, seq, prev, type, body, ts?}` -> `{envelope, id}`.
 *  `signer` to wpis klucza ze skarbca (`{id, private}`); `identity` i `prev` są `null`
 *  w genesis (`type: "identity.genesis"`, `seq: 0`). */
export async function buildEnvelope({ signer, identity = null, seq, prev = null, type, body, ts }) {
  const payload = enc.encode(
    JSON.stringify({
      v: 1,
      signer: signer.id,
      identity,
      seq,
      prev,
      type,
      body,
      ts: ts ?? Math.floor(Date.now() / 1000),
    }),
  );

  const signature = await sign("event", payload, signer.private);
  return {
    id: await eventId(payload),
    envelope: { payload: b64u(payload), signer: signer.id, signature },
  };
}
