import { validateFile } from "../pages/studio-resources.js";
const AVATAR_PATH = "images/avatar";
function avatarMediaType(file) {
  const ext = (file?.name || "").toLowerCase().split(".").pop();
  const byExt = {
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    webp: "image/webp",
  };
  const type = ext && Object.hasOwn(byExt, ext) ? byExt[ext] : null;
  if (!type || (file.type && file.type !== type))
    throw new Error("Zdj\u0119cie musi by\u0107 plikiem PNG, JPEG albo WebP.");
  validateFile(file, AVATAR_PATH, type);
  return type;
}
export { AVATAR_PATH, avatarMediaType };
