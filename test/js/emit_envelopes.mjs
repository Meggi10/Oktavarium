// Pomocnik testu zgodności: te same moduły, które ładuje przeglądarka, budują i
// podpisują koperty, a serwer (Elixir) je weryfikuje. Wypisuje JSON na stdout.
import { generateKey, sign, eventId } from "../../priv/static/assets/js/lib/crypto.js";
import { buildEnvelope } from "../../priv/static/assets/js/lib/envelope.js";
import { enc, b64u } from "../../priv/static/assets/js/lib/bytes.js";

const founder = await generateKey("signing");
const auth = await generateKey("auth");

const g = await buildEnvelope({
  signer: founder,
  type: "identity.genesis",
  seq: 0,
  body: { kind: "user", handle: "z-przegladarki", auth_keys: [auth.id] },
});

const u = await buildEnvelope({
  signer: founder,
  identity: g.id,
  seq: 1,
  prev: g.id,
  type: "profile.update",
  body: { fields: { bio: "Zażółć gęślą jaźń! - podpisane w JS mlem miau" } },
});

const message = process.argv[2] ?? "host\nnonce";
const loginSig = await sign("login", enc.encode(message), auth.private);
const asEvent = await sign("event", enc.encode(message), auth.private);

console.log(
  JSON.stringify({
    founder: founder.id,
    auth: auth.id,
    genesis: g.envelope,
    genesisId: g.id,
    update: u.envelope,
    message,
    loginSig,
    eventSig: asEvent,
    idCheck: await eventId(enc.encode("x")),
  }),
);
