export function getPublicKeyAsync(privateKey: Uint8Array): Promise<Uint8Array>;
export function signAsync(
  message: Uint8Array,
  privateKey: Uint8Array,
): Promise<Uint8Array>;
export function verifyAsync(
  signature: Uint8Array,
  message: Uint8Array,
  publicKey: Uint8Array,
): Promise<boolean>;
