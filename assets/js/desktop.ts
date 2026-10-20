// Converted from assets/js/desktop.js -> TypeScript
// Provides LiveView hooks for draggable/resizable desktop windows,
// and small global initializers for the taskbar start button image
// and the system clock updater.

console.log('🖥️ Desktop hooks loading...');

type HookContext = { el: HTMLElement } & Record<string, any>;

const DesktopWindow: any = {
  mounted(this: HookContext) {
    console.log('🪟 DesktopWindow mounted, setting up dragging...');
    this.isDragging = false;
    this.dragOffset = { x: 0, y: 0 };
    this.dragStartPos = { x: 0, y: 0 };
    this.minDragDistance = 5; // Minimum pixels to move before starting drag
    this.hasDragged = false;
    this.windowId = this.el.getAttribute('phx-value-window_id') || (this.el.id?.replace('window-',''));
    // Get the target selector for LiveComponent events
    this.desktopTarget = this.el.getAttribute('data-desktop-target') || '#bacon8-desktop';

    const header = this.el.querySelector('.window-header') as HTMLElement | null;
    if (!header) return;

    // Make window draggable
    const onMouseDown = (e: MouseEvent) => {
      if ((e.target as HTMLElement).closest('button')) return; // Don't drag when clicking buttons

      this.isDragging = false; // Don't start dragging yet
      this.hasDragged = false; // Track if we actually dragged
      const rect = this.el.getBoundingClientRect();
      this.dragOffset = {
        x: e.clientX - rect.left,
        y: e.clientY - rect.top
      };
      this.dragStartPos = { x: e.clientX, y: e.clientY };

      // Prevent text selection during drag
      e.preventDefault();
    };

    const onMouseMove = (e: MouseEvent) => {
      if (this.isDragging) {
        // Already dragging, update position
        const container = document.querySelector('.desktop-container') as HTMLElement | null;
        const containerRect = container ? container.getBoundingClientRect() : { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight } as DOMRect;

        let newX = e.clientX - containerRect.left - this.dragOffset.x;
        let newY = e.clientY - containerRect.top - this.dragOffset.y;

        // Keep window within bounds
        newX = Math.max(0, Math.min(newX, (containerRect.width || window.innerWidth) - this.el.offsetWidth));
        newY = Math.max(0, Math.min(newY, (containerRect.height || window.innerHeight) - this.el.offsetHeight));

        this.el.style.left = newX + 'px';
        this.el.style.top = newY + 'px';
        this.hasDragged = true;
      } else if (this.dragStartPos.x !== 0) {
        // Check if we've moved enough to start dragging
        const deltaX = Math.abs(e.clientX - this.dragStartPos.x);
        const deltaY = Math.abs(e.clientY - this.dragStartPos.y);
        
        if (deltaX > this.minDragDistance || deltaY > this.minDragDistance) {
          this.isDragging = true;
        }
      }
    };

    const onMouseUp = () => { 
      // If we were dragging, persist the final position to LiveView
      if (this.isDragging && this.hasDragged) {
        const left = parseInt(this.el.style.left || '0', 10) || 0;
        const top = parseInt(this.el.style.top || '0', 10) || 0;
        try {
          // Use pushEventTo to target the LiveComponent directly
          if ((this as any).pushEventTo && this.windowId && this.desktopTarget) {
            (this as any).pushEventTo(this.desktopTarget, 'update_window_position', {
              window_id: this.windowId,
              x: left,
              y: top
            });
          }
        } catch (e) {
          console.error('Failed to push window position update', e);
        }
      }
      this.isDragging = false;
      this.dragStartPos = { x: 0, y: 0 };
      
      // Keep hasDragged true briefly so click handler can check it
      // Reset it after a short delay
      if (this.hasDragged) {
        setTimeout(() => {
          this.hasDragged = false;
        }, 50);
      }
    };
    
    // Prevent click events on the entire window when dragging
    const onWindowClick = (e: MouseEvent) => {
      if (this.hasDragged) {
        e.stopPropagation();
        e.preventDefault();
      }
    };

    header.addEventListener('mousedown', onMouseDown);
    this.el.addEventListener('click', onWindowClick, true); // Capture phase on window
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);

    // Save references for cleanup
    (this as any)._desktop_listeners = { onMouseDown, onMouseMove, onMouseUp, onWindowClick, header };
    
    // Handle folder name prompt event
    (this as any).handleEvent("prompt_folder_name", ({window_id}: {window_id: string}) => {
      const name = prompt("Enter folder name:");
      if (name && name.trim()) {
        (this as any).pushEvent("fm_create_folder", {
          window_id: window_id,
          name: name.trim()
        });
      }
    });
  },

  destroyed(this: HookContext) {
    const refs = (this as any)._desktop_listeners;
    if (!refs) return;
    refs.header.removeEventListener('mousedown', refs.onMouseDown);
    this.el.removeEventListener('click', refs.onWindowClick, true);
    document.removeEventListener('mousemove', refs.onMouseMove);
    document.removeEventListener('mouseup', refs.onMouseUp);
  }
};

const ResizeHandle: any = {
  mounted(this: HookContext) {
    this.isResizing = false;
    this.direction = this.el.dataset.direction || '';
    this.startSize = {} as any;
    this.startPos = {} as any;
    this.window = null as any;
    this.windowId = null as any;
    this.desktopTarget = '#bacon8-desktop'; // Target for LiveComponent events

    const onMouseDown = (e: MouseEvent) => {
      this.isResizing = true;
      this.window = this.el.closest('.desktop-window') as HTMLElement;
      this.windowId = this.window?.getAttribute('phx-value-window_id') || (this.window?.id?.replace('window-',''));
      // Get target from parent window element
      this.desktopTarget = this.window?.getAttribute('data-desktop-target') || '#bacon8-desktop';

      const rect = this.window.getBoundingClientRect();
      this.startSize = { width: rect.width, height: rect.height };
      this.startPos = { x: rect.left, y: rect.top, mouseX: e.clientX, mouseY: e.clientY };

      e.preventDefault();
      e.stopPropagation();
    };

    const onMouseMove = (e: MouseEvent) => {
      if (!this.isResizing) return;

      const deltaX = e.clientX - this.startPos.mouseX;
      const deltaY = e.clientY - this.startPos.mouseY;

      let newWidth = this.startSize.width;
      let newHeight = this.startSize.height;
      let newLeft = this.startPos.x;
      let newTop = this.startPos.y;

      if (this.direction.includes('e')) {
        newWidth = Math.max(300, this.startSize.width + deltaX);
      }
      if (this.direction.includes('w')) {
        newWidth = Math.max(300, this.startSize.width - deltaX);
        newLeft = this.startPos.x + deltaX;
      }
      if (this.direction.includes('s')) {
        newHeight = Math.max(200, this.startSize.height + deltaY);
      }
      if (this.direction.includes('n')) {
        newHeight = Math.max(200, this.startSize.height - deltaY);
        newTop = this.startPos.y + deltaY;
      }

      // Apply new dimensions and position
      this.window.style.width = newWidth + 'px';
      this.window.style.height = newHeight + 'px';

      // If the element had inline left/top, use those offsets; otherwise compute from rect
      const curLeft = parseInt(this.window.style.left || '0', 10) || 0;
      const curTop = parseInt(this.window.style.top || '0', 10) || 0;
      this.window.style.left = (newLeft - this.startPos.x + curLeft) + 'px';
      this.window.style.top = (newTop - this.startPos.y + curTop) + 'px';
    };

    const onMouseUp = () => { 
      if (this.isResizing && this.window) {
        const rect = this.window.getBoundingClientRect();
        const width = Math.round(rect.width);
        const height = Math.round(rect.height);
        const left = parseInt(this.window.style.left || '0', 10) || 0;
        const top = parseInt(this.window.style.top || '0', 10) || 0;
        try {
          // Use pushEventTo to target the LiveComponent directly
          if ((this as any).pushEventTo && this.windowId && this.desktopTarget) {
            (this as any).pushEventTo(this.desktopTarget, 'update_window_layout', {
              window_id: this.windowId,
              width,
              height,
              x: left,
              y: top
            });
          }
        } catch (e) {
          console.error('Failed to push window layout update', e);
        }
      }
      this.isResizing = false; 
    };

    this.el.addEventListener('mousedown', onMouseDown);
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);

    (this as any)._resize_listeners = { onMouseDown, onMouseMove, onMouseUp };
  },

  destroyed(this: HookContext) {
    const refs = (this as any)._resize_listeners;
    if (!refs) return;
    this.el.removeEventListener('mousedown', refs.onMouseDown);
    document.removeEventListener('mousemove', refs.onMouseMove);
    document.removeEventListener('mouseup', refs.onMouseUp);
  }
};

// Attach hooks to window so app.ts can register them into Phoenix hooks
(window as any).DesktopWindow = DesktopWindow;
(window as any).ResizeHandle = ResizeHandle;
console.log('🖥️ Desktop hooks registered to window:', !!DesktopWindow.mounted);

// --- Global small initializers for taskbar UI ---
const initTaskbarStartImage = () => {
  try {
    const startBtn = document.querySelector('#taskbar .start-button') as HTMLElement | null;
    if (!startBtn) return;
    
    // The start button is just the logo image - no additional setup needed
    // since it's now handled server-side in the template
    console.log('Start button initialized');
  } catch (e) {
    console.error('Failed to init start image', e);
  }
};

let _clockInterval: number | null = null;
const initTaskbarClock = () => {
  try {
    const el = document.getElementById('taskbar-clock');
    if (!el) return;

    const update = () => {
      const now = new Date();
      // Manual formatting to remove leading zero on hour if present
      let hours = now.getHours();
      const minutes = now.getMinutes();
      const ampm = hours >= 12 ? 'PM' : 'AM';
      hours = hours % 12;
      hours = hours ? hours : 12; // the hour '0' should be '12'
      const strMinutes = minutes < 10 ? '0' + minutes : minutes;
      const hhmm = hours + ':' + strMinutes + ' ' + ampm;
      
      // Full date: "December 7, 2025"
      const fullDate = now.toLocaleDateString([], { month: 'long', day: 'numeric', year: 'numeric' });

      const timeEl = el.querySelector('.time');
      if (timeEl) (timeEl as HTMLElement).textContent = hhmm;
      
      // Update tooltip and calendar header
      const dateFullEls = document.querySelectorAll('.date-full');
      dateFullEls.forEach(el => (el as HTMLElement).textContent = fullDate);

      const dateHeaderEls = document.querySelectorAll('.date-full-header');
      dateHeaderEls.forEach(el => (el as HTMLElement).textContent = fullDate);
    };

    // Run immediately then every 1s
    update();
    if (_clockInterval) window.clearInterval(_clockInterval);
    _clockInterval = window.setInterval(update, 1000);
  } catch (e) {
    console.error('Failed to init taskbar clock', e);
  }
};

// Initialize on DOMContentLoaded and also when LiveView finishes page loading
document.addEventListener('DOMContentLoaded', () => {
  initTaskbarStartImage();
  initTaskbarClock();
});

window.addEventListener('phx:page-loading-stop', () => {
  setTimeout(() => {
    initTaskbarStartImage();
    initTaskbarClock();
  }, 200);
});

export {};
