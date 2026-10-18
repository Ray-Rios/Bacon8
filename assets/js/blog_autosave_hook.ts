// Blog autosave hook - TypeScript version

import { LiveViewHook } from './types/liveview';

interface BlogPost {
  [key: string]: string;
}

interface BlogAutosaveData {
  timer: number | null;
  form: HTMLFormElement;
  lastData: string;
  suspended: boolean;
}

interface BlogAutosaveHook extends LiveViewHook, BlogAutosaveData {
  extractPostData(form: HTMLFormElement): BlogPost;
}

export const BlogAutosave: BlogAutosaveHook = {
  mounted() {
    const form = this.el as HTMLFormElement;
    this.form = form;
    this.suspended = false;
    
    const contentField = form.querySelector('[name="post[content]"]') as HTMLInputElement | HTMLTextAreaElement;
    this.lastData = contentField?.value || '';
    
    const timer = window.setInterval(() => {
      // If suspended (e.g. user just submitted the form), skip autosave to avoid races
      if (this.suspended) return;

      const currentContentField = this.form.querySelector('[name="post[content]"]') as HTMLInputElement | HTMLTextAreaElement;
      const currentData = currentContentField?.value || '';

      if (currentData !== this.lastData && currentData.trim() !== '') {
        this.lastData = currentData;
        const post = this.extractPostData(this.form);
        this.pushEvent('autosave_draft', { post });
      }
    }, 10000); // Auto-save every 10 seconds

    // Suspend autosave briefly when the user submits the form to avoid overwriting a publish
    form.addEventListener('submit', () => {
      this.suspended = true;
      // Resume autosave after a short window (2s) so the save handler can complete
      window.setTimeout(() => { this.suspended = false; }, 2000);
    });
    
    this.timer = timer;
  },
  
  extractPostData(form: HTMLFormElement): BlogPost {
    const formData = new FormData(form);
    const post: BlogPost = {};
    
    for (const [key, value] of formData.entries()) {
      if (key.startsWith('post[') && typeof value === 'string') {
        const fieldName = key.slice(5, -1); // Remove 'post[' and ']'
        // Don't include is_published in autosave - let buttons control publish status
        if (fieldName !== 'is_published') {
          post[fieldName] = value;
        }
      }
    }
    
    return post;
  },
  
  destroyed() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }
} as BlogAutosaveHook;