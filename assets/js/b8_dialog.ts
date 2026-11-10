// The site's own confirm / alert / prompt (owner, 2026-11-09: "change the default error/warning
// message pop-up for browsers"). The browser's boxes ("bacon8.net says ...") are replaced by one
// glass dialog that eases in, centred, in the upper third of the window, and takes the profile's
// glass colour, opacity and blur (.glass-menu and --glass-* from glass_theme.ts and the root layout).
//
//   await b8Confirm("Delete this page?")            -> true / false
//   await b8Alert("That file is too large.")        -> resolves when dismissed
//   await b8Prompt("Folder name", { value: "" })    -> string, or null when cancelled
//
// Every `data-confirm` on the site goes through it too (see interceptDataConfirm below), so
// templates need no change. Plugins import it the way they import the vendor shims:
//   import { b8Confirm } from "../../../../assets/js/b8_dialog";
// and it is on window.B8Dialog for code that can't import.

export type DialogTone = "default" | "danger" | "warning" | "info";

export interface DialogOptions {
  title?: string;
  okLabel?: string;
  cancelLabel?: string;
  tone?: DialogTone;
}

export interface PromptOptions extends DialogOptions {
  value?: string;
  placeholder?: string;
}

type Kind = "confirm" | "alert" | "prompt";

interface Request {
  kind: Kind;
  message: string;
  opts: PromptOptions;
  resolve: (v: any) => void;
}

const ICONS: Record<DialogTone, string> = {
  default: "?",
  danger: "!",
  warning: "!",
  info: "i",
};

const queue: Request[] = [];
let showing = false;

// Words that make a confirmation destructive, so its OK button is red.
const DANGER = /\b(delete|destroy|remove|discard|throw away|reset|revoke|ban|purge|erase|wipe|replace|yank|cancel subscription)\b/i;

function guessTone(kind: Kind, message: string): DialogTone {
  if (kind === "alert") return /error|fail|couldn'?t|can'?t|not supported|too large/i.test(message) ? "warning" : "info";
  if (kind === "confirm" && DANGER.test(message)) return "danger";
  return "default";
}

function defaultTitle(kind: Kind, tone: DialogTone): string {
  if (kind === "prompt") return "Just a moment";
  if (kind === "alert") return tone === "warning" ? "Heads up" : "Note";
  return tone === "danger" ? "Are you sure?" : "Please confirm";
}

function enqueue(kind: Kind, message: string, opts: PromptOptions = {}): Promise<any> {
  return new Promise((resolve) => {
    queue.push({ kind, message: String(message ?? ""), opts, resolve });
    if (!showing) next();
  });
}

function next() {
  const req = queue.shift();
  if (!req) {
    showing = false;
    return;
  }
  showing = true;
  open(req);
}

function el<K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string, text?: string): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function open(req: Request) {
  const { kind, message, opts } = req;
  const tone = opts.tone || guessTone(kind, message);
  const previousFocus = document.activeElement as HTMLElement | null;

  const overlay = el("div", "b8-dialog-overlay");
  overlay.dataset.tone = tone;

  const box = el("div", "b8-dialog glass-menu");
  box.setAttribute("role", kind === "prompt" ? "dialog" : "alertdialog");
  box.setAttribute("aria-modal", "true");
  const titleId = `b8-dialog-title-${Date.now()}`;
  const msgId = `${titleId}-msg`;
  box.setAttribute("aria-labelledby", titleId);
  box.setAttribute("aria-describedby", msgId);

  const head = el("div", "b8-dialog-head");
  const icon = el("span", "b8-dialog-icon", ICONS[tone]);
  icon.setAttribute("aria-hidden", "true");
  const title = el("h2", "b8-dialog-title", opts.title || defaultTitle(kind, tone));
  title.id = titleId;
  head.append(icon, title);

  const msg = el("p", "b8-dialog-message", message);
  msg.id = msgId;

  let input: HTMLInputElement | null = null;
  if (kind === "prompt") {
    input = el("input", "b8-dialog-input");
    input.type = "text";
    input.value = opts.value ?? "";
    if (opts.placeholder) input.placeholder = opts.placeholder;
    input.setAttribute("aria-labelledby", msgId);
  }

  const actions = el("div", "b8-dialog-actions");
  const ok = el("button", `b8-dialog-btn b8-dialog-ok${tone === "danger" ? " is-danger" : ""}`,
    opts.okLabel || (kind === "alert" ? "OK" : tone === "danger" ? "Yes, do it" : "OK"));
  ok.type = "button";
  let cancel: HTMLButtonElement | null = null;
  if (kind !== "alert") {
    cancel = el("button", "b8-dialog-btn b8-dialog-cancel", opts.cancelLabel || "Cancel");
    cancel.type = "button";
    actions.append(cancel);
  }
  actions.append(ok);

  box.append(head, msg);
  if (input) box.append(input);
  box.append(actions);
  overlay.append(box);
  document.body.append(overlay);

  // Next frame, so the opening transition runs.
  requestAnimationFrame(() => requestAnimationFrame(() => overlay.classList.add("is-open")));

  // A destructive confirm starts on Cancel, so a stray Enter doesn't delete anything.
  const firstFocus = input || (tone === "danger" && cancel ? cancel : ok);
  setTimeout(() => {
    firstFocus.focus();
    if (input) input.select();
  }, 30);

  let done = false;
  const finish = (result: any) => {
    if (done) return;
    done = true;
    window.removeEventListener("keydown", onKey, true);
    window.removeEventListener("keyup", swallow, true);
    window.removeEventListener("keypress", swallow, true);
    overlay.classList.remove("is-open");
    overlay.classList.add("is-closing");
    const remove = () => {
      overlay.remove();
      try { previousFocus?.focus?.({ preventScroll: true }); } catch { /* element gone */ }
      req.resolve(result);
      next();
    };
    const reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    setTimeout(remove, reduced ? 0 : 180);
  };

  const accept = () => finish(kind === "confirm" ? true : kind === "prompt" ? (input?.value ?? "") : undefined);
  const dismiss = () => finish(kind === "confirm" ? false : kind === "prompt" ? null : undefined);

  ok.addEventListener("click", accept);
  cancel?.addEventListener("click", dismiss);
  // A click on the dimmed page outside the box: cancel (an alert just closes).
  overlay.addEventListener("mousedown", (e) => {
    if (e.target === overlay) {
      box.classList.remove("is-nudged");
      void box.offsetWidth;
      if (kind === "alert") dismiss(); else box.classList.add("is-nudged");
    }
  });

  // The dialog owns the keyboard while it is open: games and pages underneath don't see keys.
  const focusables = () => Array.from(box.querySelectorAll<HTMLElement>("button, input"));
  function onKey(e: KeyboardEvent) {
    e.stopImmediatePropagation();
    if (e.key === "Escape") {
      e.preventDefault();
      dismiss();
    } else if (e.key === "Enter") {
      // Enter on a focused button presses that button; anywhere else it accepts.
      const active = document.activeElement;
      if (active === cancel) { e.preventDefault(); dismiss(); }
      else { e.preventDefault(); accept(); }
    } else if (e.key === "Tab") {
      const list = focusables();
      const i = list.indexOf(document.activeElement as HTMLElement);
      e.preventDefault();
      const n = list.length;
      list[(i + (e.shiftKey ? n - 1 : 1) + n) % n]?.focus();
    }
  }
  function swallow(e: KeyboardEvent) {
    e.stopImmediatePropagation();
  }
  window.addEventListener("keydown", onKey, true);
  window.addEventListener("keyup", swallow, true);
  window.addEventListener("keypress", swallow, true);

  // A game holding the pointer lets it go, so the dialog can be clicked.
  if (document.pointerLockElement) {
    try { document.exitPointerLock(); } catch { /* not locked */ }
  }
}

export function b8Confirm(message: string, opts: DialogOptions = {}): Promise<boolean> {
  return enqueue("confirm", message, opts);
}

export function b8Alert(message: string, opts: DialogOptions = {}): Promise<void> {
  return enqueue("alert", message, opts);
}

export function b8Prompt(message: string, opts: PromptOptions = {}): Promise<string | null> {
  return enqueue("prompt", message, opts);
}

// ---------------------------------------------------------------------------------------------
// data-confirm. phoenix_html (which LiveView relies on for data-confirm) asks window.confirm in a
// bubbling click listener on window and stops the click when it is refused. This listener runs
// first (capture phase, registered when this module loads, before phoenix_html's), holds the
// click, asks with the dialog, and on OK clicks the element again with data-confirm lifted for
// that one click, so phoenix_html, LiveView (phx-click), links and form buttons all carry on as
// they would have.
let replaying = false;

function interceptDataConfirm(e: MouseEvent) {
  if (replaying || e.button !== 0) return;
  const target = e.target as Element | null;
  const holder = target?.closest?.("[data-confirm]") as HTMLElement | null;
  if (!holder) return;
  const message = holder.getAttribute("data-confirm");
  if (!message) return;

  e.preventDefault();
  e.stopImmediatePropagation();

  const tone = (holder.dataset.confirmTone as DialogTone | undefined) || undefined;
  b8Confirm(message, {
    tone,
    title: holder.dataset.confirmTitle,
    okLabel: holder.dataset.confirmOk,
    cancelLabel: holder.dataset.confirmCancel,
  }).then((yes) => {
    if (!yes || !holder.isConnected) return;
    replaying = true;
    holder.removeAttribute("data-confirm");
    try {
      holder.click();
    } finally {
      holder.setAttribute("data-confirm", message);
      replaying = false;
    }
  });
}

if (typeof window !== "undefined" && typeof document !== "undefined" && typeof window.addEventListener === "function") {
  window.addEventListener("click", interceptDataConfirm, true);

  // Anything still calling alert() gets the dialog instead (alert returns nothing, so this is
  // safe; confirm and prompt must be awaited, so their callers use b8Confirm / b8Prompt).
  const nativeAlert = typeof window.alert === "function" ? window.alert.bind(window) : () => {};
  window.alert = (message?: any) => {
    if (!document.body) return nativeAlert(message);
    void b8Alert(message === undefined ? "" : String(message));
  };

  (window as any).B8Dialog = { confirm: b8Confirm, alert: b8Alert, prompt: b8Prompt };
}
