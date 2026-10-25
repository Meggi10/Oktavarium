class Drafts {
  entries;
  constructor() {
    this.entries = /* @__PURE__ */ new Map();
  }
  capture(key, root) {
    const fields = [];
    for (const el of root.querySelectorAll(
      "form input[id], form select[id], form textarea[id]",
    )) {
      const input = el instanceof HTMLInputElement ? el : null;
      if (
        input?.type === "password" ||
        input?.type === "hidden" ||
        el.dataset.ephemeral
      )
        continue;
      fields.push({
        id: el.id,
        value: el.value,
        checked: input?.checked,
        files: input?.type === "file" ? [...(input.files || [])] : null,
      });
    }
    this.entries.set(key, fields);
  }
  restore(key, root) {
    for (const f of this.entries.get(key) || []) {
      const el = [
        ...root.querySelectorAll("input[id],select[id],textarea[id]"),
      ].find((n) => n.id === f.id);
      if (!el) continue;
      if (f.files) {
        const transfer = new DataTransfer();
        f.files.forEach((file) => transfer.items.add(file));
        if (el instanceof HTMLInputElement) el.files = transfer.files;
      } else el.value = f.value;
      if (typeof f.checked === "boolean" && el instanceof HTMLInputElement)
        el.checked = f.checked;
    }
  }
  clear(key) {
    this.entries.delete(key);
  }
}
export { Drafts };
