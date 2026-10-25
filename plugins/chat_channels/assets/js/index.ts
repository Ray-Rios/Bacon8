// Chat Channels' LiveView hooks (BACON8.md §9; assets/scripts/gen-plugin-hooks.js merges
// them into the LiveSocket). They were in the hub's app.ts while chat was its forum.
import { Sortable } from "./sortable-hook";

// Message list hook: auto-scroll behavior
const MessageList = {
  autoScrollEnabled: false,

  mounted(this: any) {
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
  updated(this: any) {
    // No-op
  }
};

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
  updated(this: any) {},
  destroyed(this: any) {}
};

// Sidebar Resizer Hook
const SidebarResizer = {
  mounted(this: any) {
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

export const hooks = { MessageList, ChatInput, SidebarResizer, Sortable };
