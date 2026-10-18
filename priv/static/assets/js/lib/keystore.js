// Skarbiec kluczy prywatnych w przeglądarce: IndexedDB + szyfrowanie hasłem
// (PBKDF2-SHA256 -> AES-256-GCM). Hasło nie opuszcza przeglądarki; klucze leżą w bazie
// wyłącznie zaszyfrowane. Ta sama zaszyfrowana postać jest kopią zapasową do pobrania.
import { b64u, unb64u, enc, dec } from "./bytes.js";

import { publicFromPrivate } from "./crypto.js";

const DB = "oktavarium";
const STORE = "vault";
const SLOT = "vault";
const ITERATIONS = 600_000;

export const MIN_PASSPHRASE = 10;

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function tx(mode, fn) {
  const db = await openDb();
  try {
    return await new Promise((resolve, reject) => {
      const t = db.transaction(STORE, mode);
      const req = fn(t.objectStore(STORE));
      t.oncomplete = () => resolve(req.result);
      t.onerror = () => reject(t.error);
      t.onabort = () => reject(t.error);
    });
  } finally {
    db.close();
  }
}

export const loadBlob = () => tx("readonly", (s) => s.get(SLOT));
export const saveBlob = (blob) => tx("readwrite", (s) => s.put(blob, SLOT));
export const clearBlob = () => tx("readwrite", (s) => s.delete(SLOT));
export const hasVault = async () => Boolean(await loadBlob());

async function deriveKey(passphrase, salt, iterations) {
  const base = await crypto.subtle.importKey(
    "raw",
    enc.encode(passphrase),
    "PBKDF2",
    false,
    ["deriveKey"],
  );
  return crypto.subtle.deriveKey(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

/** Szyfruje dane (obiekt JSON) hasłem. Każdy zapis ma świeże sól i IV. */
export async function seal(data, passphrase) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(passphrase, salt, ITERATIONS);
  const ct = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv },
      key,
      enc.encode(JSON.stringify(data)),
    ),
  );
  return {
    v: 1,
    kdf: "pbkdf2-sha256",
    iterations: ITERATIONS,
    salt: b64u(salt),
    iv: b64u(iv),
    ct: b64u(ct),
  };
}

export class WrongPassphrase extends Error {
  constructor() {
    super("Nieprawidłowe hasło albo uszkodzony skarbiec.");
  }
}

export async function unseal(blob, passphrase) {
  if (!blob || blob.v !== 1 || blob.kdf !== "pbkdf2-sha256")
    throw new Error("Nieznany format skarbca.");
  if (
    !Number.isInteger(blob.iterations) ||
    blob.iterations < 100_000 ||
    blob.iterations > 5_000_000
  ) {
    throw new Error("Nieprawidłowa liczba iteracji w skarbcu.");
  }
  try {
    const key = await deriveKey(passphrase, unb64u(blob.salt), blob.iterations);
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: unb64u(blob.iv) },
      key,
      unb64u(blob.ct),
    );
    return JSON.parse(dec.decode(plain));
  } catch {
    throw new WrongPassphrase();
  }
}

/** Odblokowany skarbiec w pamięci. Każda zmiana zapisuje się zaszyfrowana. */
export class Vault {
  constructor(data, passphrase) {
    this.data = data;
    this.passphrase = passphrase;
  }

  static empty(passphrase) {
    return new Vault({ v: 1, keys: [] }, passphrase);
  }

  static async unlock(passphrase) {
    const blob = await loadBlob();
    if (!blob) throw new Error("W tej przeglądarce nie ma skarbca kluczy.");
    return new Vault(
      await validateVault(await unseal(blob, passphrase)),
      passphrase,
    );
  }

  get keys() {
    return this.data.keys;
  }

  get(id) {
    return this.data.keys.find((k) => k.id === id) || null;
  }

  ofKind(kind) {
    return this.data.keys.filter((k) => k.kind === kind);
  }

  add(key) {
    if (!this.get(key.id)) this.data.keys.push(key);
  }

  update(id, changes) {
    Object.assign(this.get(id) || {}, changes);
  }

  async save() {
    await saveBlob(await seal(this.data, this.passphrase));
  }

  /** Plik kopii zapasowej (zaszyfrowany tym samym hasłem). */
  async backupFile() {
    const vault = await seal(this.data, this.passphrase);
    return {
      oktavarium: "vault-backup",
      v: 1,
      created: new Date().toISOString(),
      vault,
    };
  }
}

/** Przywraca skarbiec z pliku kopii. Zwraca odblokowany `Vault` (jeszcze niezapisany). */
export async function restoreBackup(file, passphrase) {
  if (file?.oktavarium !== "vault-backup" || file.v !== 1)
    throw new Error("To nie jest kopia zapasowa skarbca Oktavarium.");
  return new Vault(
    await validateVault(await unseal(file.vault, passphrase)),
    passphrase,
  );
}

/** Plik klucza w formacie CLI (`mix oktavarium.key.gen`): jawny, tylko na własną odpowiedzialność. */
export async function cliKeyfile(key, publicId) {
  return {
    v: 1,
    kind: key.kind,
    algo: "ed25519",
    public: publicId ?? key.id,
    private: key.private,
  };
}

/** Validate decrypted imports before replacing IndexedDB. Labels are not identities. */
export async function validateVault(data) {
  if (data?.v !== 1 || !Array.isArray(data.keys) || data.keys.length > 1000)
    throw new Error("Nieprawidłowa zawartość skarbca.");
  const ids = new Set();
  for (const key of data.keys) {
    if (
      !key ||
      !["signing", "auth"].includes(key.kind) ||
      !/^[A-Za-z0-9_-]{43}$/.test(key.id) ||
      !/^[A-Za-z0-9_-]{43}$/.test(key.private) ||
      ids.has(key.id) ||
      (await publicFromPrivate(key.private)) !== key.id
    ) {
      throw new Error("Kopia zawiera nieprawidłowy lub powtórzony klucz.");
    }
    ids.add(key.id);
  }
  return data;
}
