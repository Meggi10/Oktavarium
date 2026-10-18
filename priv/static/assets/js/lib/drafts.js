export class Drafts {
  constructor() {
    this.entries = new Map();
  }
  capture(key, root) {
    const fields = [];
    for (const el of root.querySelectorAll(
      "form input[id], form select[id], form textarea[id]",
    )) {
      if (
        el.type === "password" ||
        el.type === "hidden" ||
        el.dataset.ephemeral
      )
        continue;
      fields.push({
        id: el.id,
        value: el.value,
        checked: el.checked,
        files: el.type === "file" ? [...el.files] : null,
      });
    }
    this.entries.set(key, fields);
  }
  restore(key, root) {
    for (const f of this.entries.get(key) || []) {
      const el = [...root.querySelectorAll("[id]")].find((n) => n.id === f.id);
      if (!el) continue;
      if (f.files) {
        const transfer = new DataTransfer();
        f.files.forEach((file) => transfer.items.add(file));
        el.files = transfer.files;
      } else el.value = f.value;
      if (typeof f.checked === "boolean") el.checked = f.checked;
    }
  }
  clear(key) {
    this.entries.delete(key);
  }
}
