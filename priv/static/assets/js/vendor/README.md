# Biblioteki zewnętrzne

`noble-ed25519.js` — @noble/ed25519 2.2.3 (Paul Miller, licencja MIT, zob.
`noble-ed25519.LICENSE`), plik `index.js` z tagu `2.2.3`
(https://github.com/paulmillr/noble-ed25519) bez zmian. Podpisy Ed25519 w przeglądarce;
hash SHA-512 liczy `crypto.subtle`, więc używamy wyłącznie wariantów `*Async`.
Weryfikacja zgodności z serwerem: `test/js/noble_interop.test.mjs` i testy e2e.
