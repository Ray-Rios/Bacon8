// Suggestions & Bugs' LiveView hooks (BACON8.md §9; assets/scripts/gen-plugin-hooks.js merges
// them into the LiveSocket).

// FeedbackPaste: while the element is on the page, pictures pasted anywhere (Ctrl+V of a
// screenshot) are added to the LiveView upload named in `data-upload`. Pasted text is left alone.
const FeedbackPaste = {
  mounted(this: any) {
    this.onPaste = (e: ClipboardEvent) => {
      const items = Array.from(e.clipboardData?.items ?? []);
      const files = items
        .filter((it) => it.kind === "file" && it.type.startsWith("image/"))
        .map((it) => it.getAsFile())
        .filter((f): f is File => !!f)
        .map((f, i) => {
          // Clipboard pictures are all called "image.png": give each its own name.
          const ext = (f.type.split("/")[1] || "png").replace("jpeg", "jpg");
          const stamp = new Date().toISOString().replace(/[:.]/g, "-");
          return new File([f], `pasted-${stamp}-${i + 1}.${ext}`, { type: f.type });
        });
      if (files.length === 0) return;
      e.preventDefault();
      this.upload(this.el.dataset.upload || "shots", files);
    };
    window.addEventListener("paste", this.onPaste);
  },
  destroyed(this: any) {
    window.removeEventListener("paste", this.onPaste);
  },
};

export const hooks = { FeedbackPaste };
