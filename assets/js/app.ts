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
import { FileDragDrop, FileUpload } from "./file_drag_drop";
import { Sortable } from "./sortable_hook";
import { DeviceFingerprintHook } from "./device_fingerprint";
import { GlassTheme } from "./glass_theme";
import { BackgroundUpdater } from "./background_updater";
import { GlobalHooks } from "./global_hooks";
import { ProfileSettings } from "./profile_settings";
import { ColorPicker, OpacitySlider } from "./color_picker";
import { AudioHook } from "./audio";
// LiveView hooks from installed plugins (generated before each build; BACON8.md §9).
import { PluginHooks } from "./plugins.generated";

// Import Desktop hooks
import "./desktop";

// Global LiveSocket reference
let liveSocket: LiveSocket | null = null;

// Defer heavy Three.js and Quill imports - load them BEFORE socket connects
// This prevents double-mount issues
let HomeGalaxyScene: any = null;
let NebulaScene: any = null;
let StarfieldScene: any = null;
let VoidScene: any = null;
let GlobalCameraController: any = null;
let RichEditor: any = null;
let BlogAutosave: any = null;
let QuillEditorHook: any = null;
let CollaborativeQuillHook: any = null;
let BlockEditorHook: any = null;

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
      import("./block_editor_hook")
    ]);
    
    RichEditor = richEditorMod.RichEditor;
    BlogAutosave = blogAutosaveMod.BlogAutosave;
    QuillEditorHook = quillMod.default;
    CollaborativeQuillHook = collabQuillMod.default;
    BlockEditorHook = blockEditorMod.default;
    
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
      // Lightweight hooks (imported synchronously at top)
      TerminalTypewriter,
      FileDragDrop,
      FileUpload,
      Sortable,
      DeviceFingerprint: DeviceFingerprintHook,
      GlassTheme,
      BackgroundUpdater,
      ...GlobalHooks,
      ProfileSettings,
      ColorPicker,
      OpacitySlider,
      AudioHook,
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
      MessageReactions: (window as any)._MessageReactions,
      MessageList: (window as any)._MessageList,
      DesktopWindow: (window as any).DesktopWindow,
      ResizeHandle: (window as any).ResizeHandle,
      ChatInput: (window as any)._ChatInput,
      ReloadPage: (window as any)._ReloadPage,
      FullscreenContainer: (window as any)._FullscreenContainer,
      SidebarResizer: (window as any)._SidebarResizer,
      AdminSidebarResizer: (window as any)._AdminSidebarResizer,
      // Placeholder Three.js hooks - will be replaced when loaded
      HomeGalaxyScene: { mounted() { console.log('⏳ HomeGalaxyScene loading...'); } },
      NebulaScene: { mounted() { console.log('⏳ NebulaScene loading...'); } },
      StarfieldScene: { mounted() { console.log('⏳ StarfieldScene loading...'); } },
      VoidScene: { mounted() { console.log('⏳ VoidScene loading...'); } },
      GlobalCameraController: { mounted() { console.log('⏳ GlobalCameraController loading...'); } },
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
    
    // PHASE 2: Load Three.js modules in background (non-blocking)
    console.log('🎨 Loading Three.js scenes in background...');
    Promise.all([
      import("./threejs/galaxy-scene"),
      import("./threejs/scenes/nebula-scene"),
      import("./threejs/scenes/starfield-scene"),
      import("./threejs/scenes/void-scene"),
      import("./threejs/controls/global-camera-controller")
    ]).then(([galaxyMod, nebulaMod, starfieldMod, voidMod, cameraMod]) => {
      HomeGalaxyScene = galaxyMod.HomeGalaxyScene;
      NebulaScene = nebulaMod.NebulaScene;
      StarfieldScene = starfieldMod.StarfieldScene;
      VoidScene = voidMod.VoidScene;
      GlobalCameraController = cameraMod.GlobalCameraController;
      
      // Update hooks in the existing liveSocket
      Hooks.HomeGalaxyScene = HomeGalaxyScene;
      Hooks.NebulaScene = NebulaScene;
      Hooks.StarfieldScene = StarfieldScene;
      Hooks.VoidScene = VoidScene;
      Hooks.GlobalCameraController = GlobalCameraController;
      
      const totalLoadTime = performance.now() - startTime;
      console.log(`✅ Three.js scenes loaded in ${totalLoadTime.toFixed(0)}ms`);
      
      // Trigger scene initialization for any static scene containers
      window.dispatchEvent(new CustomEvent('heavy-modules-loaded'));
    }).catch(err => {
      console.warn('⚠️ Three.js scenes failed to load (non-critical):', err);
    });
    
  } catch (error) {
    console.error('❌ Failed to load essential modules:', error);
    
    // Fallback: Connect without heavy hooks so page is still usable
    const fallbackHooks: Record<string, any> = {
      TerminalTypewriter,
      FileDragDrop,
      FileUpload,
      Sortable,
      DeviceFingerprint: DeviceFingerprintHook,
      GlassTheme,
      BackgroundUpdater,
      ...GlobalHooks,
      ProfileSettings,
      ColorPicker,
      OpacitySlider,
      AudioHook,
      AutoDismissFlash: (window as any)._AutoDismissFlash,
      MessageReactions: (window as any)._MessageReactions,
      MessageList: (window as any)._MessageList,
      DesktopWindow: (window as any).DesktopWindow,
      ResizeHandle: (window as any).ResizeHandle,
      ChatInput: (window as any)._ChatInput,
      ReloadPage: (window as any)._ReloadPage,
      FullscreenContainer: (window as any)._FullscreenContainer,
      SidebarResizer: (window as any)._SidebarResizer,
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
const MessageReactions = {
  mounted() {
    console.log('Message Reactions mounted');
  },
  updated() {
    console.log('Message Reactions updated');
  }
};

// Message list hook: auto-scroll behavior
const MessageList = {
  autoScrollEnabled: false,

  mounted() {
    const el = this.el as HTMLElement;
    const THRESHOLD = 50; // pixels
    this.autoScrollEnabled = el.dataset.autoScroll === "true";
    console.log("MessageList mounted, autoScroll:", this.autoScrollEnabled);

    // Find existing elements
    const toggleBtn = document.getElementById('auto-scroll-toggle');
    const notifier = document.getElementById('new-messages-notifier');

    const scrollToBottom = () => {
      el.scrollTop = el.scrollHeight;
    };

    const updateButtonState = () => {
      if (!toggleBtn) return;
      
      // Base classes for dark-glass look
      const baseClasses = ['absolute', 'bottom-4', 'right-4', 'z-50', 'w-[30px]', 'h-[30px]', 'rounded-full', 'shadow-lg', 'transition-all', 'duration-300', 'flex', 'items-center', 'justify-center', 'bg-black/50', 'backdrop-blur-md', 'border', 'border-white/10', 'text-white', 'hover:bg-black/70'];
      
      // Reset classes
      toggleBtn.className = baseClasses.join(' ');

      if (this.autoScrollEnabled) {
        // Locked state - Lock icon
        toggleBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
        </svg>`;
        toggleBtn.title = "Auto-scroll ON (Locked to bottom)";
        // Add a subtle green glow or indicator if desired, but user asked for dark-glass lock
        toggleBtn.classList.add('text-green-400'); 
      } else {
        // Unlocked state - Down Arrow
        toggleBtn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 14l-7 7m0 0l-7-7m7 7V3" />
        </svg>`;
        toggleBtn.title = "Scroll to bottom";
        toggleBtn.classList.remove('text-green-400');
      }
    };

    // Initialize button state
    updateButtonState();

    if (toggleBtn) {
      // Remove old listeners to prevent duplicates if re-mounted (though mounted runs once per element)
      const newBtn = toggleBtn.cloneNode(true) as HTMLElement;
      toggleBtn.parentNode?.replaceChild(newBtn, toggleBtn);
      
      newBtn.addEventListener('click', () => {
        if (this.autoScrollEnabled) {
           // If locked, clicking unlocks it (and stays at current position)
           this.autoScrollEnabled = false;
           // Push event to server to update state
           this.pushEvent("toggle_auto_scroll", { enabled: false });
        } else {
           // If unlocked, clicking scrolls to bottom and locks it
           this.autoScrollEnabled = true;
           scrollToBottom();
           if (notifier) notifier.classList.add('hidden');
           // Push event to server to update state
           this.pushEvent("toggle_auto_scroll", { enabled: true });
        }
        updateButtonState();
      });
    }

    if (notifier) {
      notifier.addEventListener('click', () => {
        scrollToBottom();
        notifier.classList.add('hidden');
        // Mark read
        const lastMsg = el.querySelector(':scope > [id^="message-"]:last-child');
        if (lastMsg) {
           const id = lastMsg.id.replace('message-', '');
           this.pushEvent('messages_read', { last_read_id: id });
        }
      });
    }

    // Initial scroll-to-bottom when mounted
    // Use requestAnimationFrame to ensure layout is ready
    requestAnimationFrame(() => {
      if (this.autoScrollEnabled) {
        scrollToBottom();
      }
    });

    // Also try again after a short delay for images
    setTimeout(() => {
      if (this.autoScrollEnabled) {
        scrollToBottom();
      }
    }, 300);

    // Update relative time badges inside messages container
    const formatRelative = (d) => {
      const now = Date.now();
      const then = new Date(d).getTime();
      const diff = Math.floor((now - then) / 1000);
      if (diff < 5) return 'just now';
      if (diff < 60) return `${diff}s ago`;
      const mins = Math.floor(diff / 60);
      if (mins < 60) return `${mins}m ago`;
      const hours = Math.floor(mins / 60);
      if (hours < 24) return `${hours}h ago`;
      const days = Math.floor(hours / 24);
      return `${days}d ago`;
    };

    const updateTimes = () => {
      Array.from(el.querySelectorAll('time[datetime]') as HTMLElement[]).forEach((t) => {
        const dt = t.getAttribute('datetime');
        if (!dt) return;
        const rel = formatRelative(dt);
        t.textContent = rel;
        // Keep original hover text as full ISO timestamp
        t.title = new Date(dt).toLocaleString();
      });
    };

    updateTimes();
    const timeInterval = setInterval(updateTimes, 30_000);

    // Scroll listener to mark messages as read
    let scrollTimeout;
    el.addEventListener('scroll', () => {
      clearTimeout(scrollTimeout);
      scrollTimeout = setTimeout(() => {
        const atBottom = (el.scrollHeight - el.scrollTop - el.clientHeight) <= THRESHOLD;
        
        // If user scrolls up, disable auto-scroll
        if (!atBottom && this.autoScrollEnabled) {
          this.autoScrollEnabled = false;
          this.pushEvent("toggle_auto_scroll", { enabled: false });
          updateButtonState();
        }
        
        // If user scrolls to bottom, enable auto-scroll
        if (atBottom && !this.autoScrollEnabled) {
          this.autoScrollEnabled = true;
          this.pushEvent("toggle_auto_scroll", { enabled: true });
          updateButtonState();
          
          if (notifier) notifier.classList.add('hidden');
          const lastMsg = el.querySelector(':scope > [id^="message-"]:last-child');
          if (lastMsg) {
             const id = lastMsg.id.replace('message-', '');
             this.pushEvent('messages_read', { last_read_id: id });
          }
        }
      }, 200);
    });

    // MutationObserver to detect appended messages and auto-scroll
    const mo = new MutationObserver((mutations) => {
      // Only auto-scroll if a new MESSAGE was added, not just a status update
      const hasNewMessages = mutations.some(m => {
        return Array.from(m.addedNodes).some((n: any) => {
             return n.nodeType === 1 && n.id && n.id.startsWith('message-');
        });
      });

      if (hasNewMessages) {
        if (this.autoScrollEnabled) {
          scrollToBottom();
        } else {
           if (notifier) notifier.classList.remove('hidden');
        }
      }
    });

    mo.observe(el, { childList: true, subtree: true });

    // Top sentinel for loading older messages
    const topSentinel = document.createElement('div');
    topSentinel.style.width = '100%';
    topSentinel.style.height = '1px';
    topSentinel.id = 'load-older-sentinel';
    if (el.firstChild) el.insertBefore(topSentinel, el.firstChild);

    let loadingOlder = false;
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting && !loadingOlder) {
          const firstMsg = el.querySelector(':scope > [id^="message-"]');
          if (!firstMsg) return;
          const id = firstMsg.id.replace('message-', '');
          loadingOlder = true;
          this.pushEvent('load_older', { before_id: id });
          setTimeout(() => (loadingOlder = false), 800);
        }
      });
    }, { root: el, threshold: 0.1 });

    io.observe(topSentinel);

    // Cleanup
    this.destroyed = () => {
      mo.disconnect();
      io.disconnect && io.disconnect();
      clearInterval(timeInterval);
    };
  },
  updated() {
    // No-op
  }
};

// Desktop Window Hook - now imported from ./desktop
// (removed placeholder that was overriding the real hook)

// ChatInput Hook - Handle Enter key to submit, Shift+Enter for newline
const ChatInput = {
  mounted(this: any) {
    // Handle Enter key
    this.el.addEventListener('keydown', (e: KeyboardEvent) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        const form = this.el.closest('form');
        if (form) {
          form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
        }
      }
    });

    // Handle custom insert-text event (for emoji picker)
    this.el.addEventListener('insert-text', (e: CustomEvent) => {
      const text = e.detail.text;
      if (!text) return;
      
      const start = this.el.selectionStart;
      const end = this.el.selectionEnd;
      const value = this.el.value;
      
      this.el.value = value.substring(0, start) + text + value.substring(end);
      this.el.selectionStart = this.el.selectionEnd = start + text.length;
      this.el.focus();
      
      // Trigger input event for LiveView binding
      this.el.dispatchEvent(new Event('input', { bubbles: true }));
    });

    this.handleEvent("clear_input", (payload: any) => {
      if (this.el.id === payload.id) {
        this.el.value = "";
        this.el.dispatchEvent(new Event('input', { bubbles: true }));
      }
    });
  },
  updated() {},
  destroyed() {}
};

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
    
    // Ensure proper positioning based on navbar/taskbar state
    const navbar = document.getElementById('main-navbar');
    const isHidden = navbar?.style.transform === 'translateY(-100%)';
    
    if (isHidden) {
      this.el.style.top = '0';
      this.el.style.bottom = '0';
    } else {
      this.el.style.top = '30px';
      this.el.style.bottom = '35px';
    }
  },
  destroyed() {
    document.documentElement.classList.remove('no-scroll');
    document.body.classList.remove('no-scroll');
  }
};

// Sidebar Resizer Hook
const SidebarResizer = {
  mounted() {
    const el = this.el as HTMLElement;
    const handle = el.querySelector('.resize-handle') as HTMLElement;
    const content = el.querySelector('.sidebar-content') as HTMLElement;
    const collapsedHandle = document.getElementById('sidebar-collapsed-handle');
    
    if (!handle) return;

    let isResizing = false;
    let startX = 0;
    let startWidth = 0;
    const DEFAULT_WIDTH = 220;
    const MIN_WIDTH = 50; // Minimum visible width
    const MAX_WIDTH = 500;
    const COLLAPSE_THRESHOLD = 80; // Below this, collapse completely
    const clickThreshold = 5; // Pixels to distinguish click from drag

    // Initialize sidebar state from localStorage
    const initSidebar = () => {
      const savedWidth = localStorage.getItem('forum_sidebar_width');
      const savedCollapsed = localStorage.getItem('forum_sidebar_collapsed');
      
      if (savedCollapsed === 'true') {
        // Start collapsed
        el.style.width = '0px';
        el.style.display = 'none';
        if (content) content.style.display = 'none';
        if (collapsedHandle) collapsedHandle.classList.remove('hidden');
      } else {
        // Start open with saved or default width
        const width = savedWidth ? parseInt(savedWidth) : DEFAULT_WIDTH;
        el.style.width = `${width}px`;
        el.style.display = 'flex';
        if (content) content.style.display = 'block';
        if (collapsedHandle) collapsedHandle.classList.add('hidden');
      }
    };

    // Apply initial state
    initSidebar();

    const collapse = () => {
      el.style.width = '0px';
      el.style.display = 'none';
      if (content) content.style.display = 'none';
      if (collapsedHandle) collapsedHandle.classList.remove('hidden');
      localStorage.setItem('forum_sidebar_collapsed', 'true');
    };

    const expand = (width?: number) => {
      const savedWidth = localStorage.getItem('forum_sidebar_width');
      const targetWidth = width || (savedWidth ? parseInt(savedWidth) : DEFAULT_WIDTH);
      el.style.width = `${targetWidth}px`;
      el.style.display = 'flex';
      if (content) content.style.display = 'block';
      if (collapsedHandle) collapsedHandle.classList.add('hidden');
      localStorage.setItem('forum_sidebar_collapsed', 'false');
      if (width) {
        localStorage.setItem('forum_sidebar_width', width.toString());
      }
    };

    // Re-apply state on updates (since phx-update="ignore" might be removed)
    this.updated = () => {
      const savedCollapsed = localStorage.getItem('forum_sidebar_collapsed');
      if (savedCollapsed === 'true') {
        el.style.width = '0px';
        el.style.display = 'none';
        if (content) content.style.display = 'none';
        if (collapsedHandle) collapsedHandle.classList.remove('hidden');
      } else {
        const savedWidth = localStorage.getItem('forum_sidebar_width');
        const width = savedWidth ? parseInt(savedWidth) : DEFAULT_WIDTH;
        el.style.width = `${width}px`;
        el.style.display = 'flex';
        if (content) content.style.display = 'block';
        if (collapsedHandle) collapsedHandle.classList.add('hidden');
      }
    };

    const onMouseDown = (e: MouseEvent) => {
      isResizing = true;
      startX = e.clientX;
      startWidth = el.offsetWidth;
      
      document.addEventListener('mousemove', onMouseMove);
      document.addEventListener('mouseup', onMouseUp);
      
      // Prevent text selection during drag
      document.body.style.userSelect = 'none';
      document.body.style.cursor = 'col-resize';
      e.preventDefault();
    };

    const onMouseMove = (e: MouseEvent) => {
      if (!isResizing) return;
      
      const dx = e.clientX - startX;
      let newWidth = startWidth + dx;
      
      // Clamp to valid range, allow dragging to near-zero for collapse gesture
      if (newWidth < MIN_WIDTH) newWidth = Math.max(0, newWidth);
      if (newWidth > MAX_WIDTH) newWidth = MAX_WIDTH;
      
      // Visual feedback while dragging
      el.style.width = `${newWidth}px`;
      el.style.display = 'flex';
      
      if (newWidth < COLLAPSE_THRESHOLD) {
        if (content) content.style.opacity = '0.3';
      } else {
        if (content) {
          content.style.opacity = '1';
          content.style.display = 'block';
        }
      }
    };

    const onMouseUp = (e: MouseEvent) => {
      if (!isResizing) return;
      
      const dx = Math.abs(e.clientX - startX);
      isResizing = false;
      
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
      if (content) content.style.opacity = '1';

      // Check if it was a click (toggle) vs drag
      if (dx < clickThreshold) {
        // Toggle on click
        const isCollapsed = localStorage.getItem('forum_sidebar_collapsed') === 'true';
        if (isCollapsed) {
          expand();
        } else {
          collapse();
        }
      } else {
        // It was a drag - check final width
        const currentWidth = el.offsetWidth;
        if (currentWidth < COLLAPSE_THRESHOLD) {
          collapse();
        } else {
          expand(currentWidth);
        }
      }
    };

    // Listen for toggle_sidebar event from the hamburger menu button
    this.handleEvent('toggle_sidebar', () => {
      const isCollapsed = localStorage.getItem('forum_sidebar_collapsed') === 'true';
      if (isCollapsed) {
        expand();
      } else {
        collapse();
      }
    });

    // Allow clicking collapsed handle to expand
    if (collapsedHandle) {
      collapsedHandle.addEventListener('click', () => {
        expand();
      });
    }

    handle.addEventListener('mousedown', onMouseDown);
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
  }
};

// Register inline hooks on window so they can be accessed by loadHeavyModulesAndConnect
(window as any)._AutoDismissFlash = AutoDismissFlash;
(window as any)._MessageReactions = MessageReactions;
(window as any)._MessageList = MessageList;
(window as any)._ChatInput = ChatInput;
(window as any)._ReloadPage = ReloadPage;
(window as any)._FullscreenContainer = FullscreenContainer;
(window as any)._SidebarResizer = SidebarResizer;
(window as any)._AdminSidebarResizer = AdminSidebarResizer;

// NOW that all hooks are defined, load heavy modules and connect LiveSocket
console.log('⏳ Starting heavy module loading and LiveSocket connection...');
loadHeavyModulesAndConnect();

console.log('✅ Phoenix LiveView hooks initialization started');
// Note: Three.js background scenes are mounted via Phoenix LiveView hooks
// (phx-hook attributes) so we avoid manual initialization here which
// can conflict with LiveView's hook lifecycle.

// Static scene initializer: for layout-mounted background canvas elements that
// are not part of a LiveView patch (they use data-static-scene), initialize
// the matching Three.js hook directly so LiveView doesn't attempt to attach
// hooks to DOM nodes it didn't render.
const initializeStaticScenes = () => {
  try {
    // Get hooks from liveSocket if available
    const hooks = liveSocket ? (liveSocket as any).opts?.hooks : null;
    if (!hooks) {
      console.log('⏳ Waiting for liveSocket hooks to be available...');
      return;
    }
    
    const staticEls = Array.from(document.querySelectorAll('[data-static-scene]')) as HTMLElement[];
    staticEls.forEach((el) => {
      const sceneName = el.getAttribute('data-static-scene');
      if (!sceneName) return;

      // Map scene names to hook constructors available in liveSocket hooks
      const hookConstructor: any = hooks[sceneName];
      if (!hookConstructor) {
        console.warn('No hook registered for static scene:', sceneName);
        return;
      }

  // If this element was already initialized
  if ((el as any)._threeJSHook) {
    // Check if the scene has changed
    if ((el as any)._currentSceneName === sceneName) {
      return;
    }
    
    // Scene changed, destroy old one
    console.log('🔄 Switching static scene to:', sceneName);
    const oldHook = (el as any)._threeJSHook;
    if (typeof oldHook.destroyed === 'function') {
      try {
        oldHook.destroyed.call(oldHook);
      } catch (e) {
        console.error('Error destroying old scene:', e);
      }
    }
    (el as any)._threeJSHook = null;
  }

      // Create a minimal hook-like context and call mounted()
      try {
        const instance = Object.create(hookConstructor);
        instance.el = el;
        if (typeof instance.mounted === 'function') {
          instance.mounted.call(instance);
          // Mark the element as initialized and store instance
          (el as any)._threeJSHook = instance;
          (el as any)._currentSceneName = sceneName;
          console.log('✅ Initialized static scene:', sceneName, 'on', el.id || el.tagName);
        }
      } catch (err) {
        console.error('❌ Failed to initialize static scene', sceneName, err);
      }
    });
  } catch (err) {
    console.error('❌ Error initializing static scenes', err);
  }
};

// Run after a short delay to allow LiveSocket to perform initial patches
setTimeout(initializeStaticScenes, 250);

// Re-initialize on page navigation if needed
window.addEventListener('phx:page-loading-stop', () => {
  setTimeout(() => {
    if (document.querySelector('[data-static-scene]')) {
      initializeStaticScenes();
    }
  }, 100);
});

// Also initialize static scenes when heavy modules finish loading
window.addEventListener('heavy-modules-loaded', () => {
  setTimeout(() => {
    if (document.querySelector('[data-static-scene]')) {
      initializeStaticScenes();
    }
  }, 50);
});

// MutationObserver fallback: if LiveView removes and re-inserts the canvas during a patch,
// detect insertion and re-initialize the static scene on the new node.
try {
  const observer = new MutationObserver((mutations) => {
    for (const m of mutations) {
      // Handle attribute changes (scene switching)
      if (m.type === 'attributes' && m.attributeName === 'data-static-scene') {
        setTimeout(() => initializeStaticScenes(), 50);
        return;
      }

      if (m.type === 'childList' && m.addedNodes.length > 0) {
        for (const node of Array.from(m.addedNodes)) {
          if (!(node instanceof HTMLElement)) continue;
          if (node.matches && node.matches('[data-static-scene]')) {
            setTimeout(() => initializeStaticScenes(), 50);
            return;
          }
          // Also check descendants
          if (node.querySelector && node.querySelector('[data-static-scene]')) {
            setTimeout(() => initializeStaticScenes(), 50);
            return;
          }
        }
      }
    }
  });

  observer.observe(document.documentElement || document.body, { 
    childList: true, 
    subtree: true, 
    attributes: true, 
    attributeFilter: ['data-static-scene'] 
  });
} catch {
  // ignore mutation observer failures
}

// Also log removals of the global background canvas for debugging
try {
  const removalObserver = new MutationObserver((mutations) => {
    for (const m of mutations) {
      if (m.type === 'childList' && m.removedNodes.length > 0) {
        for (const node of Array.from(m.removedNodes)) {
          if (!(node instanceof HTMLElement)) continue;
          if (node.id === 'global-background-canvas' || (node.querySelector && node.querySelector('#global-background-canvas'))) {
            console.warn('🧨 global-background-canvas was removed from DOM', node);
            try { console.trace(); } catch {
              // Ignore trace errors
            }
          }
        }
      }
    }
  });

  removalObserver.observe(document.documentElement || document.body, { childList: true, subtree: true });
} catch {
  // ignore removal observer failures
}

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