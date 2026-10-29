// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";

// Suppress Phoenix channel timeout rejections during normal disconnect/reconnect cycles.
// These are expected behavior (long-poll reconnects, WebSocket drops) and not real errors.
window.addEventListener('unhandledrejection', (event) => {
  if (event.reason && event.reason.timeout === true) {
    event.preventDefault();
  }
});

// App version for cache debugging
const APP_VERSION = "2025.12.21.2";
console.log(`🔧 Bacon8 v${APP_VERSION}`);

// Phoenix LiveView - import but DON'T connect until hooks are ready
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

// CSRF token - get it early
const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || "";

// Topbar for progress indicators
import topbar from "./topbar";

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Import lightweight TypeScript hooks (non-blocking)
import { TerminalTypewriter } from "./terminal_typewriter";
import { IntroReveal, IntroTagline } from "./intro_reveal";
import { FileDragDrop, FileUpload } from "./file_drag_drop";
import { DeviceFingerprintHook } from "./device_fingerprint";
import { GlassTheme } from "./glass_theme";
import { BackgroundUpdater } from "./background_updater";
import { GlobalHooks } from "./global_hooks";
import { ProfileSettings } from "./profile_settings";
import { ColorPicker, OpacitySlider } from "./color_picker";
import { AudioHook } from "./audio";
import { GameCard } from "./game_card";
// <b8-gem>: the Bacon8 Gem (the currency and shop icon), a custom element.
import "./fire_gem";
// <b8-bacon>: two strips of bacon, the site icon (Start button, the navbar's Games link).
import "./sizzle_bacon";
// LiveView hooks from installed plugins (generated before each build; BACON8.md §9).
import { PluginHooks } from "./plugins.generated";

// Import Desktop hooks
import "./desktop";

// Global LiveSocket reference
let liveSocket: LiveSocket | null = null;

// Defer heavy Three.js and Quill imports - load them BEFORE socket connects
// This prevents double-mount issues
let RichEditor: any = null;
let BlogAutosave: any = null;
let QuillEditorHook: any = null;
let CollaborativeQuillHook: any = null;
let BlockEditorHook: any = null;
let AutoGrowHook: any = null;

// Heavy module loading function (called after inline hooks are defined)
async function loadHeavyModulesAndConnect() {
  try {
    console.log('📦 Loading essential modules first (BlockEditor, Quill)...');
    const startTime = performance.now();
    
    // PHASE 1: Load essential page hooks FIRST (BlockEditor, Quill, etc.)
    // These are needed for page functionality - load them before connecting
    const [richEditorMod, blogAutosaveMod, quillMod, collabQuillMod, blockEditorMod] = await Promise.all([
      import("./rich_editor"),
      import("./blog_autosave_hook"),
      import("./quill_editor_hook"),
      import("./collaborative_quill_hook"),
      import("./page_builder/hook") // the page builder (2026-10-28); replaced block_editor_hook.ts
    ]);
    
    RichEditor = richEditorMod.RichEditor;
    BlogAutosave = blogAutosaveMod.BlogAutosave;
    QuillEditorHook = quillMod.default;
    CollaborativeQuillHook = collabQuillMod.default;
    BlockEditorHook = blockEditorMod.default;
    AutoGrowHook = blockEditorMod.AutoGrow;
    
    const essentialLoadTime = performance.now() - startTime;
    console.log(`✅ Essential modules loaded in ${essentialLoadTime.toFixed(0)}ms`);
    
    // Build Hooks object with essential hooks + placeholders for Three.js
    const Hooks: Record<string, any> = {
      // Essential page hooks (loaded)
      RichEditor,
      BlogAutosave,
      QuillEditor: QuillEditorHook,
      CollaborativeQuill: CollaborativeQuillHook,
      BlockEditor: BlockEditorHook,
      AutoGrow: AutoGrowHook,
      // Lightweight hooks (imported synchronously at top)
      TerminalTypewriter,
      IntroReveal,
      IntroTagline,
      FileDragDrop,
      FileUpload,
      DeviceFingerprint: DeviceFingerprintHook,
      GlassTheme,
      BackgroundUpdater,
      ...GlobalHooks,
      ProfileSettings,
      ColorPicker,
      OpacitySlider,
      AudioHook,
      GameCard,
      // Copies the text of the element named by data-target (admin log panes).
      CopyText: {
        mounted(this: any) {
          this.el.addEventListener("click", () => {
            const target = document.getElementById(this.el.dataset.target);
            if (!target) return;
            navigator.clipboard.writeText(target.innerText).then(() => {
              const label = this.el.textContent;
              this.el.textContent = "Copied";
              setTimeout(() => { this.el.textContent = label; }, 1500);
            });
          });
        },
      },
      // Inline hooks (defined below in this file)
      AutoDismissFlash: (window as any)._AutoDismissFlash,
      DesktopWindow: (window as any).DesktopWindow,
      ResizeHandle: (window as any).ResizeHandle,
      ReloadPage: (window as any)._ReloadPage,
      FullscreenContainer: (window as any)._FullscreenContainer,
      AdminSidebarResizer: (window as any)._AdminSidebarResizer,
      ...PluginHooks
    };
    
    // Create and connect LiveSocket NOW - essential hooks ready
    liveSocket = new LiveSocket("/live", Socket, {
      // timezone: lets server-rendered pages show local times (store dates).
      params: { _csrf_token: csrfToken, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone },
      hooks: Hooks,
      timeout: 30000, // 30 second timeout for slower connections
    });
    
    // Expose liveSocket globally
    (window as any).liveSocket = liveSocket;
    
    // Connect NOW - page is usable immediately
    liveSocket.connect();
    console.log('🚀 Phoenix LiveSocket connected (essential hooks ready)');
    
  } catch (error) {
    console.error('❌ Failed to load essential modules:', error);
    
    // Fallback: Connect without heavy hooks so page is still usable
    const fallbackHooks: Record<string, any> = {
      TerminalTypewriter,
      IntroReveal,
      IntroTagline,
      FileDragDrop,
      FileUpload,
      DeviceFingerprint: DeviceFingerprintHook,
      GlassTheme,
      BackgroundUpdater,
      ...GlobalHooks,
      ProfileSettings,
      ColorPicker,
      OpacitySlider,
      AudioHook,
      GameCard,
      AutoDismissFlash: (window as any)._AutoDismissFlash,
      DesktopWindow: (window as any).DesktopWindow,
      ResizeHandle: (window as any).ResizeHandle,
      ReloadPage: (window as any)._ReloadPage,
      FullscreenContainer: (window as any)._FullscreenContainer,
      AdminSidebarResizer: (window as any)._AdminSidebarResizer,
      ...PluginHooks
    };
    
    liveSocket = new LiveSocket("/live", Socket, {
      // timezone: lets server-rendered pages show local times (store dates).
      params: { _csrf_token: csrfToken, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone },
      hooks: fallbackHooks,
      timeout: 30000, // 30 second timeout for slower connections
    });
    
    (window as any).liveSocket = liveSocket;
    liveSocket.connect();
    console.log('🚀 Phoenix LiveSocket connected (fallback, without heavy hooks)');
  }
}

// Auto-dismiss flash notifications - DISABLED to let AutoDismissFlash hook handle it
// document.addEventListener('DOMContentLoaded', () => {
//   // Schedule removal of any existing flash messages after initial join
//   const scheduleDismiss = () => {
//     document.querySelectorAll('[data-auto-dismiss]').forEach((el: Element) => {
//       const h = el as HTMLElement;
//       if (!h.dataset.dismissScheduled) {
//         h.dataset.dismissScheduled = 'true';
//         const delay = parseInt(h.dataset.autoDismiss || '4000');
//         setTimeout(() => {
//           h.style.opacity = '0';
//           setTimeout(() => h.remove(), 300);
//         }, delay);
//       }
//     });
//   };

//   // Run once on DOMContentLoaded, and again after LiveView page loading stops
//   scheduleDismiss();
//   window.addEventListener('phx:page-loading-stop', () => setTimeout(scheduleDismiss, 250));
// });

// AutoDismissFlash Hook for individual flash management
const AutoDismissFlash = {
  mounted(this: { el: HTMLElement, pushEvent: (event: string, payload: any) => void }) {
    const el = this.el;
    const delay = parseInt(el.dataset.autoDismiss || '3000');
    
    console.log('🔔 AutoDismissFlash mounted, will dismiss in', delay, 'ms');
    
    // Clear any existing timeout
    if (el.dataset.dismissTimeout) {
      clearTimeout(parseInt(el.dataset.dismissTimeout));
    }
    
    // Set new timeout
    const timeoutId = setTimeout(() => {
      console.log('🔔 AutoDismissFlash: Dismissing flash notification');
      // Fade out
      el.style.opacity = '0';
      setTimeout(() => {
        // Push event to server to clear flash from assigns
        if (el.dataset.key) {
          this.pushEvent("lv:clear-flash", { key: el.dataset.key });
        }
        // Remove from DOM
        el.remove();
      }, 300);
    }, delay);
    
    el.dataset.dismissTimeout = timeoutId.toString();
  },
  
  updated(this: { el: HTMLElement, pushEvent: (event: string, payload: any) => void }) {
    // Reset timeout when flash content changes
    const el = this.el;
    const delay = parseInt(el.dataset.autoDismiss || '3000');
    
    // Clear any existing timeout
    if (el.dataset.dismissTimeout) {
      clearTimeout(parseInt(el.dataset.dismissTimeout));
    }
    
    // Set new timeout
    const timeoutId = setTimeout(() => {
      // Trigger the same dismiss animation as clicking
      el.style.transform = 'translateX(120%)';
      el.style.opacity = '0';
      setTimeout(() => {
        // Push event to server to clear flash from assigns
        if (el.dataset.key) {
          this.pushEvent("lv:clear-flash", { key: el.dataset.key });
        }
        // Remove from DOM
        el.remove();
      }, 300);
    }, delay);
    
    el.dataset.dismissTimeout = timeoutId.toString();
  },
  
  destroyed(this: { el: HTMLElement }) {
    // Clear timeout when element is removed
    const el = this.el;
    if (el.dataset.dismissTimeout) {
      clearTimeout(parseInt(el.dataset.dismissTimeout));
    }
  }
};

// Message Reactions Hook (simplified)


// Desktop Window Hook - now imported from ./desktop
// (removed placeholder that was overriding the real hook)


// Reload Page Hook - Used for applying background changes
const ReloadPage = {
  mounted(this: any) {
    this.handleEvent("reload_page", ({delay}: {delay: number}) => {
      setTimeout(() => {
        window.location.reload();
      }, delay || 1000);
    });
  }
};

// FullscreenContainer hook - prevents body scrolling on fullscreen pages
const FullscreenContainer = {
  mounted() {
    // Immediately add no-scroll to prevent any page scrolling
    document.documentElement.classList.add('no-scroll');
    document.body.classList.add('no-scroll');
    
    // Between the navbar and the taskbar, or the whole window while they are hidden: CSS
    // (.fullscreen-shell, html.chrome-hidden in app.css) follows the toggle.
    this.el.classList.add('fullscreen-shell');
    this.el.style.top = '';
    this.el.style.bottom = '';
  },
  destroyed() {
    document.documentElement.classList.remove('no-scroll');
    document.body.classList.remove('no-scroll');
  }
};


// Admin Sidebar Resizer Hook - similar to forum sidebar but with different storage keys
const AdminSidebarResizer = {
  mounted() {
    const el = this.el as HTMLElement;
    const handle = el.querySelector('.resize-handle') as HTMLElement;
    const content = el.querySelector('.sidebar-content') as HTMLElement;
    const collapsedHandle = document.getElementById('admin-sidebar-collapsed-handle');
    
    if (!handle) return;

    let isResizing = false;
    let startX = 0;
    let startWidth = 0;
    const DEFAULT_WIDTH = 240;
    const MIN_WIDTH = 60; // Minimum width to show icons
    const MAX_WIDTH = 400;
    const COLLAPSE_THRESHOLD = 100; // Below this, collapse to icon-only
    const ICON_ONLY_WIDTH = 60;
    const clickThreshold = 5;
    // On a phone the sidebar is a drawer over the page (assets/css/mobile.css), opened by the
    // Menu button at the top of the page (#admin-menu-toggle) and closed by a link or a tap outside.
    const phone = () => window.matchMedia('(max-width: 767px)').matches;

    // Hide labels when collapsed, show icons
    const updateLabelsVisibility = (width: number) => {
      const labels = el.querySelectorAll('.sidebar-label');
      const sectionHeaders = el.querySelectorAll('.sidebar-section-header');
      const links = el.querySelectorAll('.sidebar-link');
      
      if (width <= COLLAPSE_THRESHOLD) {
        labels.forEach((label: Element) => (label as HTMLElement).style.display = 'none');
        sectionHeaders.forEach((header: Element) => (header as HTMLElement).style.display = 'none');
        links.forEach((link: Element) => {
          (link as HTMLElement).style.justifyContent = 'center';
          (link as HTMLElement).style.paddingLeft = '0';
          (link as HTMLElement).style.paddingRight = '0';
        });
        el.querySelectorAll('.sidebar-icon').forEach((icon: Element) => {
          (icon as HTMLElement).style.marginRight = '0';
        });
      } else {
        labels.forEach((label: Element) => (label as HTMLElement).style.display = 'block');
        sectionHeaders.forEach((header: Element) => (header as HTMLElement).style.display = 'block');
        links.forEach((link: Element) => {
          (link as HTMLElement).style.justifyContent = 'flex-start';
          (link as HTMLElement).style.paddingLeft = '0.75rem';
          (link as HTMLElement).style.paddingRight = '0.75rem';
        });
        el.querySelectorAll('.sidebar-icon').forEach((icon: Element) => {
          (icon as HTMLElement).style.marginRight = '0.75rem';
        });
      }
    };

    // Initialize sidebar state from localStorage
    const initSidebar = () => {
      const savedWidth = localStorage.getItem('admin_sidebar_width');
      const savedCollapsed = localStorage.getItem('admin_sidebar_collapsed');
      
      if (savedCollapsed === 'true') {
        // Start in icon-only mode
        el.style.width = `${ICON_ONLY_WIDTH}px`;
        updateLabelsVisibility(ICON_ONLY_WIDTH);
        if (collapsedHandle) collapsedHandle.classList.add('hidden');
      } else {
        const width = savedWidth ? parseInt(savedWidth) : DEFAULT_WIDTH;
        el.style.width = `${width}px`;
        updateLabelsVisibility(width);
        if (collapsedHandle) collapsedHandle.classList.add('hidden');
      }
    };

    initSidebar();
    if (phone()) updateLabelsVisibility(DEFAULT_WIDTH);

    const setOpen = (open: boolean) => {
      el.classList.toggle('is-open', open);
      document.getElementById('admin-menu-toggle')?.setAttribute('aria-expanded', String(open));
    };
    (this as any).onDocClick = (e: Event) => {
      if (!phone()) return;
      const t = e.target as HTMLElement;
      if (t.closest('#admin-menu-toggle')) return setOpen(!el.classList.contains('is-open'));
      if (el.classList.contains('is-open') && (!el.contains(t) || t.closest('a'))) setOpen(false);
    };
    document.addEventListener('click', (this as any).onDocClick);

    const collapse = () => {
      el.style.width = `${ICON_ONLY_WIDTH}px`;
      updateLabelsVisibility(ICON_ONLY_WIDTH);
      localStorage.setItem('admin_sidebar_collapsed', 'true');
    };

    const expand = (width?: number) => {
      const savedWidth = localStorage.getItem('admin_sidebar_width');
      const targetWidth = width || (savedWidth ? parseInt(savedWidth) : DEFAULT_WIDTH);
      el.style.width = `${targetWidth}px`;
      updateLabelsVisibility(targetWidth);
      localStorage.setItem('admin_sidebar_collapsed', 'false');
      if (width && width > COLLAPSE_THRESHOLD) {
        localStorage.setItem('admin_sidebar_width', width.toString());
      }
    };

    const onMouseDown = (e: MouseEvent) => {
      isResizing = true;
      startX = e.clientX;
      startWidth = el.offsetWidth;
      
      document.addEventListener('mousemove', onMouseMove);
      document.addEventListener('mouseup', onMouseUp);
      
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'col-resize';
      e.preventDefault();
    };

    const onMouseMove = (e: MouseEvent) => {
      if (!isResizing) return;
      
      const dx = e.clientX - startX;
      let newWidth = startWidth + dx;
      
      if (newWidth < MIN_WIDTH) newWidth = MIN_WIDTH;
      if (newWidth > MAX_WIDTH) newWidth = MAX_WIDTH;
      
      el.style.width = `${newWidth}px`;
      updateLabelsVisibility(newWidth);
    };

    const onMouseUp = (e: MouseEvent) => {
      if (!isResizing) return;
      
      const dx = Math.abs(e.clientX - startX);
      isResizing = false;
      
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
      document.body.style.userSelect = '';
      document.body.style.cursor = '';

      if (dx < clickThreshold) {
        // Toggle on click
        const isCollapsed = localStorage.getItem('admin_sidebar_collapsed') === 'true';
        if (isCollapsed) {
          expand();
        } else {
          collapse();
        }
      } else {
        // It was a drag
        const currentWidth = el.offsetWidth;
        if (currentWidth <= COLLAPSE_THRESHOLD) {
          collapse();
        } else {
          expand(currentWidth);
        }
      }
    };

    if (collapsedHandle) {
      collapsedHandle.addEventListener('click', () => {
        expand();
      });
    }

    handle.addEventListener('mousedown', onMouseDown);
  },
  destroyed() {
    document.removeEventListener('click', (this as any).onDocClick);
  }
};

// Register inline hooks on window so they can be accessed by loadHeavyModulesAndConnect
(window as any)._AutoDismissFlash = AutoDismissFlash;
(window as any)._ReloadPage = ReloadPage;
(window as any)._FullscreenContainer = FullscreenContainer;
(window as any)._AdminSidebarResizer = AdminSidebarResizer;

// NOW that all hooks are defined, load heavy modules and connect LiveSocket
console.log('⏳ Starting heavy module loading and LiveSocket connection...');
loadHeavyModulesAndConnect();

console.log('✅ Phoenix LiveView hooks initialization started');
// (2026-10-28) The three.js background scenes, their static-scene initializer and the two
// MutationObservers that watched the whole document for them are gone: the backgrounds are
// SVG and CSS now (Bacon8Web.Components.Cosmos), and those observers ran on every change to
// every page.

// Global error diagnostics: capture unhandled errors and list phx-hook elements
window.addEventListener('error', (event) => {
  try {
    console.error('Global error captured:', event.message, event.error);
    const hookEls = Array.from(document.querySelectorAll('[data-phx-hook], [phx-hook]'));
    console.group('PHX HOOK ELEMENTS SNAPSHOT');
    console.log('Total phx-hook elements found:', hookEls.length);
    hookEls.forEach((el, idx) => {
      try {
        const ds = (el as HTMLElement).dataset;
        console.log(idx, el.tagName, 'id=', el.id || '(no id)', 'phx-hook=', el.getAttribute('phx-hook') || el.getAttribute('data-phx-hook'), 'dataset=', ds);
      } catch (e) {
        console.log(idx, 'error reading element', e);
      }
    });
    console.groupEnd();
  } catch (e) {
    console.error('Failed to capture phx-hook snapshot', e);
  }
});

window.addEventListener('unhandledrejection', (ev) => {
  console.error('Unhandled promise rejection:', ev.reason);
});

// Debug helper: log forms with phx-submit to track client-side submits
document.addEventListener('submit', (ev) => {
  try {
    const target = ev.target as HTMLElement | null;
    if (!target) return;
    if (target instanceof HTMLFormElement && target.hasAttribute('phx-submit')) {
      console.log('\ud83d\udd14 phx-submit form submitted:', target.id || target.getAttribute('name') || '(unnamed)');
    }
  } catch {
    // ignore form submit logging errors
  }
}, true);

window.addEventListener("phx:open_url", (e: any) => {
  if (e.detail && e.detail.url) {
    window.open(e.detail.url, '_blank');
  }
});

// Gallery carousel functionality for rendered blog/page content
function initGalleryCarousels() {
  document.querySelectorAll('.gallery.gallery-carousel').forEach((gallery) => {
    const items = gallery.querySelectorAll('.gallery-item');
    const dots = gallery.querySelectorAll('.gallery-dot');
    const prevBtn = gallery.querySelector('.gallery-prev');
    const nextBtn = gallery.querySelector('.gallery-next');
    
    if (items.length <= 1) return;
    
    let currentIndex = 0;
    
    const showItem = (index: number) => {
      items.forEach((item, i) => {
        item.classList.toggle('active', i === index);
      });
      dots.forEach((dot, i) => {
        dot.classList.toggle('active', i === index);
      });
      currentIndex = index;
    };
    
    const nextItem = () => {
      showItem((currentIndex + 1) % items.length);
    };
    
    const prevItem = () => {
      showItem((currentIndex - 1 + items.length) % items.length);
    };
    
    prevBtn?.addEventListener('click', prevItem);
    nextBtn?.addEventListener('click', nextItem);
    
    dots.forEach((dot, i) => {
      dot.addEventListener('click', () => showItem(i));
    });
  });
}

// Initialize gallery carousels on page load and after LiveView navigation
window.addEventListener('phx:page-loading-stop', () => setTimeout(initGalleryCarousels, 100));
document.addEventListener('DOMContentLoaded', initGalleryCarousels);