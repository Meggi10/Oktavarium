// A profile photo is a normal signed image resource in the root namespace.
// No new database column or event type is needed.
import { validateFile } from "../pages/studio-resources.js";

export const AVATAR_PATH = "images/avatar";

export function avatarMediaType(file) {
  const ext = (file?.name || "").toLowerCase().split(".").pop();
  const byExt = {
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    webp: "image/webp",
  };
  const type = Object.hasOwn(byExt, ext) ? byExt[ext] : null;
  if (!type || (file.type && file.type !== type))
    throw new Error("Zdjęcie musi być plikiem PNG, JPEG albo WebP.");
  validateFile(file, AVATAR_PATH, type);
  return type;
}
