export class Drafts {
  entries: Map<
    string,
    Array<{
      id: string;
      value: string;
      checked?: boolean;
      files: File[] | null;
    }>
  >;
  constructor() {
    this.entries = new Map();
  }
  capture(key: string, root: HTMLElement) {
    const fields = [];
    for (const el of root.querySelectorAll<
      HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement
    >("form input[id], form select[id], form textarea[id]")) {
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
  restore(key: string, root: HTMLElement) {
    for (const f of this.entries.get(key) || []) {
      const el = [
        ...root.querySelectorAll<
          HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement
        >("input[id],select[id],textarea[id]"),
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
  clear(key: string) {
    this.entries.delete(key);
  }
}
