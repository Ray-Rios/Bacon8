// Rich Editor Hook for WordPress-style content editing with full-screen support

import { RichEditorHook, TextSelection } from './types/rich-editor';

export const RichEditor: RichEditorHook = {
  mounted() {
    this.initializeEditor();
    this.isFullscreen = false;
  },

  updated() {
    // Re-initialize if needed
  },

  initializeEditor(): void {
    const textarea = this.el as HTMLTextAreaElement;
    
    // Create editor container
    const editorContainer = this.createEditorContainer();
    if (textarea.parentNode) {
      textarea.parentNode.insertBefore(editorContainer, textarea);
      editorContainer.appendChild(textarea);
    }
    
    // Create toolbar
    const toolbar = this.createToolbar();
    editorContainer.insertBefore(toolbar, textarea);
    
    // Add editor styling
    textarea.classList.add('rich-editor-textarea');
    
    // Store references
    this.currentContainer = editorContainer;
    this.currentTextarea = textarea;
    this.currentToolbar = toolbar;
    
    // Add event listeners
    this.addEventListeners(textarea, toolbar, editorContainer);
  },

  createEditorContainer(): HTMLElement {
    const container = document.createElement('div');
    container.className = 'rich-editor-container';
    return container;
  },

  createToolbar(): HTMLElement {
    const toolbar = document.createElement('div');
    toolbar.className = 'rich-editor-toolbar';
    toolbar.innerHTML = `
      <div class="toolbar-left">
        <div class="toolbar-group">
          <button type="button" data-command="bold" title="Bold (Ctrl+B)">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M6 4h8a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z"></path>
              <path d="M6 12h9a4 4 0 0 1 4 4 4 4 0 0 1-4 4H6z"></path>
            </svg>
          </button>
          <button type="button" data-command="italic" title="Italic (Ctrl+I)">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <line x1="19" y1="4" x2="10" y2="4"></line>
              <line x1="14" y1="20" x2="5" y2="20"></line>
              <line x1="15" y1="4" x2="9" y2="20"></line>
            </svg>
          </button>
          <button type="button" data-command="underline" title="Underline (Ctrl+U)">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M6 3v7a6 6 0 0 0 6 6 6 6 0 0 0 6-6V3"></path>
              <line x1="4" y1="21" x2="20" y2="21"></line>
            </svg>
          </button>
        </div>
        
        <div class="toolbar-group">
          <button type="button" data-command="h1" title="Heading 1">H1</button>
          <button type="button" data-command="h2" title="Heading 2">H2</button>
          <button type="button" data-command="h3" title="Heading 3">H3</button>
        </div>
        
        <div class="toolbar-group">
          <button type="button" data-command="ul" title="Bullet List">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <line x1="8" y1="6" x2="21" y2="6"></line>
              <line x1="8" y1="12" x2="21" y2="12"></line>
              <line x1="8" y1="18" x2="21" y2="18"></line>
              <line x1="3" y1="6" x2="3.01" y2="6"></line>
              <line x1="3" y1="12" x2="3.01" y2="12"></line>
              <line x1="3" y1="18" x2="3.01" y2="18"></line>
            </svg>
          </button>
          <button type="button" data-command="ol" title="Numbered List">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <line x1="10" y1="6" x2="21" y2="6"></line>
              <line x1="10" y1="12" x2="21" y2="12"></line>
              <line x1="10" y1="18" x2="21" y2="18"></line>
              <path d="M4 6h1v4"></path>
              <path d="M4 10h2"></path>
              <path d="M6 18H4c0-1 2-2 2-3s-1-1.5-2-1"></path>
            </svg>
          </button>
          <button type="button" data-command="link" title="Insert Link (Ctrl+K)">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"></path>
              <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"></path>
            </svg>
          </button>
        </div>
        
        <div class="toolbar-group">
          <button type="button" data-command="image" title="Insert Image">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect>
              <circle cx="8.5" cy="8.5" r="1.5"></circle>
              <polyline points="21,15 16,10 5,21"></polyline>
            </svg>
          </button>
          <button type="button" data-command="code" title="Code Block">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="16,18 22,12 16,6"></polyline>
              <polyline points="8,6 2,12 8,18"></polyline>
            </svg>
          </button>
          <button type="button" data-command="quote" title="Quote">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M3 21c3 0 7-1 7-8V5c0-1.25-.756-2.017-2-2H4c-1.25 0-2 .75-2 1.972V11c0 1.25.75 2 2 2 1 0 1 0 1 1v1c0 1-1 2-2 2s-1 .008-1 1.031V20c0 1 0 1 1 1z"></path>
              <path d="M15 21c3 0 7-1 7-8V5c0-1.25-.757-2.017-2-2h-4c-1.25 0-2 .75-2 1.972V11c0 1.25.75 2 2 2h.75c0 2.25.25 4-2.75 4v3c0 1 0 1 1 1z"></path>
            </svg>
          </button>
        </div>
      </div>
      
      <div class="toolbar-right">
        <div class="toolbar-group">
          <button type="button" data-command="preview" title="Preview" class="preview-btn">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
              <circle cx="12" cy="12" r="3"></circle>
            </svg>
          </button>
          <button type="button" data-command="fullscreen" title="Fullscreen (F11)" class="fullscreen-btn">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"></path>
            </svg>
          </button>
        </div>
      </div>
    `;
    
    return toolbar;
  },

  addEventListeners(textarea: HTMLTextAreaElement, toolbar: HTMLElement, container: HTMLElement): void {
    // Toolbar button clicks
    toolbar.addEventListener('click', (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const button = target.closest('button') as HTMLButtonElement;
      if (button) {
        e.preventDefault();
        const command = button.dataset.command;
        
        if (command === 'fullscreen') {
          this.toggleFullscreen(container);
        } else if (command === 'preview') {
          this.togglePreview(textarea, container);
        } else if (command) {
          this.executeCommand(command, textarea);
        }
      }
    });

    // Keyboard shortcuts
    textarea.addEventListener('keydown', (e: KeyboardEvent) => {
      if (e.ctrlKey || e.metaKey) {
        switch (e.key) {
          case 'b':
            e.preventDefault();
            this.executeCommand('bold', textarea);
            break;
          case 'i':
            e.preventDefault();
            this.executeCommand('italic', textarea);
            break;
          case 'u':
            e.preventDefault();
            this.executeCommand('underline', textarea);
            break;
          case 'k':
            e.preventDefault();
            this.executeCommand('link', textarea);
            break;
        }
      }
      
      // F11 for fullscreen
      if (e.key === 'F11') {
        e.preventDefault();
        this.toggleFullscreen(container);
      }
      
      // Escape to exit fullscreen
      if (e.key === 'Escape' && this.isFullscreen) {
        this.toggleFullscreen(container);
      }
    });

    // Auto-resize textarea
    textarea.addEventListener('input', () => {
      this.autoResize(textarea);
    });

    // Initial resize
    this.autoResize(textarea);
  },

  toggleFullscreen(container: HTMLElement): void {
    this.isFullscreen = !this.isFullscreen;
    
    if (this.isFullscreen) {
      container.classList.add('fullscreen');
      document.body.classList.add('editor-fullscreen');
    } else {
      container.classList.remove('fullscreen');
      document.body.classList.remove('editor-fullscreen');
    }
    
    // Update fullscreen button icon
    const fullscreenBtn = container.querySelector('.fullscreen-btn svg');
    if (fullscreenBtn) {
      if (this.isFullscreen) {
        fullscreenBtn.innerHTML = `
          <path d="M8 3v3a2 2 0 0 1-2 2H3m18 0h-3a2 2 0 0 1-2-2V3m0 18v-3a2 2 0 0 1 2-2h3M3 16h3a2 2 0 0 1 2 2v3"></path>
        `;
      } else {
        fullscreenBtn.innerHTML = `
          <path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"></path>
        `;
      }
    }
  },

  togglePreview(textarea: HTMLTextAreaElement, container: HTMLElement): void {
    const existingPreview = container.querySelector('.editor-preview');
    
    if (existingPreview) {
      existingPreview.remove();
      textarea.style.display = 'block';
      const previewBtn = container.querySelector('.preview-btn');
      previewBtn?.classList.remove('active');
    } else {
      const preview = document.createElement('div');
      preview.className = 'editor-preview';
      preview.innerHTML = this.renderMarkdown(textarea.value);
      
      textarea.style.display = 'none';
      container.appendChild(preview);
      const previewBtn = container.querySelector('.preview-btn');
      previewBtn?.classList.add('active');
    }
  },

  renderMarkdown(content: string): string {
    return content
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/^# (.*$)/gim, '<h1>$1</h1>')
      .replace(/^## (.*$)/gim, '<h2>$1</h2>')
      .replace(/^### (.*$)/gim, '<h3>$1</h3>')
      .replace(/^- (.*$)/gim, '<li>$1</li>')
      .replace(/^1\. (.*$)/gim, '<li>$1</li>')
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
      .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1">')
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/```\n([\s\S]*?)\n```/g, '<pre><code>$1</code></pre>')
      .replace(/^> (.*$)/gim, '<blockquote>$1</blockquote>')
      .replace(/\n/g, '<br>');
  },

  executeCommand(command: string, textarea: HTMLTextAreaElement): void {
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const selectedText = textarea.value.substring(start, end);
    const beforeText = textarea.value.substring(0, start);
    const afterText = textarea.value.substring(end);

    let replacement = '';
    let cursorOffset = 0;

    switch (command) {
      case 'bold':
        replacement = `**${selectedText || 'bold text'}**`;
        cursorOffset = selectedText ? 0 : -2;
        break;
      
      case 'italic':
        replacement = `*${selectedText || 'italic text'}*`;
        cursorOffset = selectedText ? 0 : -1;
        break;
      
      case 'underline':
        replacement = `<u>${selectedText || 'underlined text'}</u>`;
        cursorOffset = selectedText ? 0 : -4;
        break;
      
      case 'h1':
        replacement = `# ${selectedText || 'Heading 1'}`;
        cursorOffset = selectedText ? 0 : 0;
        break;
      
      case 'h2':
        replacement = `## ${selectedText || 'Heading 2'}`;
        cursorOffset = selectedText ? 0 : 0;
        break;
      
      case 'h3':
        replacement = `### ${selectedText || 'Heading 3'}`;
        cursorOffset = selectedText ? 0 : 0;
        break;
      
      case 'ul':
        replacement = `- ${selectedText || 'List item'}`;
        cursorOffset = selectedText ? 0 : 0;
        break;
      
      case 'ol':
        replacement = `1. ${selectedText || 'List item'}`;
        cursorOffset = selectedText ? 0 : 0;
        break;
      
      case 'link': {
        const url = prompt('Enter URL:');
        if (url) {
          replacement = `[${selectedText || 'link text'}](${url})`;
          cursorOffset = selectedText ? 0 : -3 - url.length;
        } else {
          return;
        }
        break;
      }
      
      case 'image': {
        const imageUrl = prompt('Enter image URL:');
        if (imageUrl) {
          const altText = selectedText || 'image';
          replacement = `![${altText}](${imageUrl})`;
          cursorOffset = 0;
        } else {
          return;
        }
        break;
      }
      
      case 'code':
        if (selectedText.includes('\n')) {
          replacement = `\`\`\`\n${selectedText || 'code block'}\n\`\`\``;
        } else {
          replacement = `\`${selectedText || 'code'}\``;
        }
        cursorOffset = selectedText ? 0 : (selectedText.includes('\n') ? -4 : -1);
        break;
      
      case 'quote':
        replacement = `> ${selectedText || 'Quote text'}`;
        cursorOffset = selectedText ? 0 : 0;
        break;
      
      default:
        return;
    }

    // Update textarea value
    textarea.value = beforeText + replacement + afterText;
    
    // Set cursor position
    const newCursorPos = start + replacement.length + cursorOffset;
    textarea.setSelectionRange(newCursorPos, newCursorPos);
    
    // Focus textarea
    textarea.focus();
    
    // Trigger input event for LiveView
    textarea.dispatchEvent(new Event('input', { bubbles: true }));
    
    // Auto-resize
    this.autoResize(textarea);
  },

  autoResize(textarea: HTMLTextAreaElement): void {
    textarea.style.height = 'auto';
    textarea.style.height = Math.max(200, textarea.scrollHeight) + 'px';
  },

  getSelection(textarea: HTMLTextAreaElement): TextSelection {
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    return {
      start,
      end,
      text: textarea.value.substring(start, end)
    };
  },

  replaceSelection(textarea: HTMLTextAreaElement, newText: string): void {
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const beforeText = textarea.value.substring(0, start);
    const afterText = textarea.value.substring(end);
    
    textarea.value = beforeText + newText + afterText;
    textarea.setSelectionRange(start + newText.length, start + newText.length);
  },

  wrapSelection(textarea: HTMLTextAreaElement, before: string, after: string): void {
    const selection = this.getSelection(textarea);
    const newText = before + selection.text + after;
    this.replaceSelection(textarea, newText);
  }
} as RichEditorHook;

// Add CSS styles
const style = document.createElement('style');
style.textContent = `
  .rich-editor-container {
    position: relative;
    border: 1px solid #d1d5db;
    border-radius: 6px;
    background: white;
    transition: all 0.3s ease;
  }

  .rich-editor-container.fullscreen {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 9999;
    border-radius: 0;
    border: none;
    background: #1a1a1a;
  }

  .rich-editor-toolbar {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px;
    background: #f8f9fa;
    border-bottom: 1px solid #d1d5db;
    border-radius: 6px 6px 0 0;
  }

  .fullscreen .rich-editor-toolbar {
    background: #2d2d2d;
    border-bottom-color: #404040;
    border-radius: 0;
  }

  .toolbar-left {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .toolbar-right {
    display: flex;
    gap: 8px;
  }

  .toolbar-group {
    display: flex;
    gap: 4px;
    padding-right: 8px;
    border-right: 1px solid #e5e7eb;
  }

  .toolbar-group:last-child {
    border-right: none;
    padding-right: 0;
  }

  .fullscreen .toolbar-group {
    border-right-color: #404040;
  }

  .rich-editor-toolbar button {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    padding: 6px;
    background: white;
    border: 1px solid #d1d5db;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s;
    font-size: 12px;
    font-weight: 600;
    color: #374151;
  }

  .fullscreen .rich-editor-toolbar button {
    background: #404040;
    border-color: #525252;
    color: #e5e7eb;
  }

  .rich-editor-toolbar button:hover {
    background: #f3f4f6;
    border-color: #9ca3af;
    transform: translateY(-1px);
  }

  .fullscreen .rich-editor-toolbar button:hover {
    background: #525252;
    border-color: #6b7280;
  }

  .rich-editor-toolbar button:active,
  .rich-editor-toolbar button.active {
    background: #e5e7eb;
    transform: translateY(1px);
  }

  .fullscreen .rich-editor-toolbar button:active,
  .fullscreen .rich-editor-toolbar button.active {
    background: #6b7280;
  }

  .rich-editor-textarea {
    width: 100%;
    border: none !important;
    border-radius: 0 0 6px 6px !important;
    min-height: 300px;
    resize: vertical;
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    font-size: 14px;
    line-height: 1.6;
    padding: 16px;
    background: white;
    color: #1f2937;
    outline: none;
  }

  .fullscreen .rich-editor-textarea {
    min-height: calc(100vh - 60px);
    background: #1a1a1a;
    color: #e5e7eb;
    border-radius: 0 !important;
    font-size: 16px;
    line-height: 1.8;
    padding: 24px;
  }

  .rich-editor-textarea:focus {
    outline: none;
    box-shadow: inset 0 0 0 2px rgba(59, 130, 246, 0.2);
  }

  .fullscreen .rich-editor-textarea:focus {
    box-shadow: inset 0 0 0 2px rgba(59, 130, 246, 0.4);
  }

  .editor-preview {
    padding: 16px;
    background: white;
    border-radius: 0 0 6px 6px;
    min-height: 300px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    line-height: 1.6;
    color: #1f2937;
  }

  .fullscreen .editor-preview {
    background: #1a1a1a;
    color: #e5e7eb;
    border-radius: 0;
    min-height: calc(100vh - 60px);
    padding: 24px;
    font-size: 16px;
    line-height: 1.8;
  }

  .editor-preview h1, .editor-preview h2, .editor-preview h3 {
    margin: 1.5em 0 0.5em 0;
    font-weight: 600;
  }

  .editor-preview h1 { font-size: 2em; }
  .editor-preview h2 { font-size: 1.5em; }
  .editor-preview h3 { font-size: 1.25em; }

  .editor-preview p {
    margin: 1em 0;
  }

  .editor-preview blockquote {
    border-left: 4px solid #3b82f6;
    padding-left: 16px;
    margin: 1em 0;
    font-style: italic;
    color: #6b7280;
  }

  .fullscreen .editor-preview blockquote {
    color: #9ca3af;
  }

  .editor-preview code {
    background: #f3f4f6;
    padding: 2px 6px;
    border-radius: 3px;
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    font-size: 0.9em;
  }

  .fullscreen .editor-preview code {
    background: #374151;
  }

  .editor-preview pre {
    background: #f8f9fa;
    padding: 16px;
    border-radius: 6px;
    overflow-x: auto;
    margin: 1em 0;
  }

  .fullscreen .editor-preview pre {
    background: #374151;
  }

  .editor-preview pre code {
    background: none;
    padding: 0;
  }

  body.editor-fullscreen {
    overflow: hidden;
  }

  /* Responsive design */
  @media (max-width: 768px) {
    .toolbar-left {
      flex-wrap: wrap;
    }
    
    .toolbar-group {
      margin-bottom: 4px;
    }
    
    .rich-editor-textarea {
      font-size: 16px; /* Prevent zoom on iOS */
    }
  }
`;
document.head.appendChild(style);