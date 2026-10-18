/**
 * Block-Based WYSIWYG Editor Hook for Phoenix LiveView
 * 
 * A comprehensive content editor with:
 * - Row/Column layouts for flexible content grids
 * - Multiple content block types (text, image, video, audio, gallery, etc.)
 * - Drag-and-drop block reordering AND file uploads
 * - Custom rich text editing with contenteditable
 * - Real-time auto-save
 * - Integration with Phoenix LiveView uploads
 */

// Block types supported by the editor
type BlockType = 
  | 'text' 
  | 'heading' 
  | 'image' 
  | 'video' 
  | 'audio'
  | 'gallery'
  | 'file'
  | 'code' 
  | 'quote' 
  | 'divider' 
  | 'columns' 
  | 'callout'
  | 'embed'
  | 'list'
  | 'table'
  | 'html'
  | 'api';

// Media item for gallery blocks
interface MediaItem {
  id: string;
  url: string;
  type: string;
  filename?: string;
  caption?: string;
  alt?: string;
}

interface Block {
  id: string;
  type: BlockType;
  content: any;
  settings?: Record<string, any>;
  media?: MediaItem[]; // For gallery blocks
}

interface Row {
  id: string;
  columns: Column[];
  settings?: {
    gap?: string;
    padding?: string;
    background?: string;
  };
}

interface Column {
  id: string;
  width: string; // e.g., "1/2", "1/3", "2/3", "full"
  blocks: Block[];
}

interface EditorState {
  rows: Row[];
  version: number;
}

// Allowed file types for upload
const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/svg+xml'];
const ALLOWED_VIDEO_TYPES = ['video/mp4', 'video/webm', 'video/ogg', 'video/quicktime'];
const ALLOWED_AUDIO_TYPES = ['audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/mp3', 'audio/webm'];
const ALLOWED_DOCUMENT_TYPES = ['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'text/plain'];
const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB

// Get file type category
const getFileCategory = (mimeType: string): 'image' | 'video' | 'audio' | 'document' | 'other' => {
  if (ALLOWED_IMAGE_TYPES.includes(mimeType)) return 'image';
  if (ALLOWED_VIDEO_TYPES.includes(mimeType)) return 'video';
  if (ALLOWED_AUDIO_TYPES.includes(mimeType)) return 'audio';
  if (ALLOWED_DOCUMENT_TYPES.includes(mimeType)) return 'document';
  return 'other';
};

// Generate unique IDs
const generateId = (): string => {
  return `block-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
};

const BlockEditorHook = {
  mounted(this: any) {
    console.log('🧱 BlockEditor mounted');
    
    // Parse configuration
    const config = {
      autosaveDelay: parseInt(this.el.dataset.autosaveDelay || '5000'),
      placeholder: this.el.dataset.placeholder || 'Click to add content...',
      readonly: this.el.dataset.readonly === 'true'
    };

    // Initialize editor state
    this.state = this.parseInitialContent();
    this.richTextEditors = new Map<string, HTMLElement>();
    this.draggedBlock = null;
    this.autosaveTimeout = null;
    this.config = config;
    
    // Render the editor
    this.render();
    
    // Set up event listeners
    this.setupEventListeners();
    
    // Listen for LiveView events
    this.setupLiveViewHandlers();
  },

  parseInitialContent(this: any): EditorState {
    const content = this.el.dataset.initialContent;
    
    if (content && content.trim()) {
      try {
        // Try to parse as block editor format
        const parsed = JSON.parse(content);
        if (parsed.rows) {
          return parsed;
        }
      } catch {
        // If not JSON or not block format, convert HTML to blocks
        return this.htmlToBlocks(content);
      }
    }
    
    // Return default empty state with one text block
    return {
      rows: [{
        id: generateId(),
        columns: [{
          id: generateId(),
          width: 'full',
          blocks: [{
            id: generateId(),
            type: 'text',
            content: ''
          }]
        }]
      }],
      version: 1
    };
  },

  htmlToBlocks(this: any, html: string): EditorState {
    // Convert existing HTML content into block format
    // This handles migration from plain HTML content
    return {
      rows: [{
        id: generateId(),
        columns: [{
          id: generateId(),
          width: 'full',
          blocks: [{
            id: generateId(),
            type: 'text',
            content: html
          }]
        }]
      }],
      version: 1
    };
  },

  render(this: any) {
    // Clear existing rich text editor references
    this.richTextEditors.clear();

    // Build the editor HTML
    const html = `
      <div class="block-editor">
        <!-- Editor Content (with drop zone for files) -->
        <div class="block-editor-content" id="${this.el.id}-drop-zone">
          ${this.renderRows()}
        </div>
        </div>

        <!-- Add Row Button at Bottom -->
        <div class="add-row-footer">
          <button type="button" class="add-row-btn" data-action="add-row">
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
            </svg>
            Add Row
          </button>
        </div>
      </div>
    `;

    this.el.innerHTML = html;

    // Initialize rich text editors for text blocks (with small delay to ensure DOM is ready)
    requestAnimationFrame(() => {
      this.initializeRichTextEditors();
    });

    // Update hidden input
    this.updateHiddenInput();
  },

  renderRows(this: any): string {
    if (!this.state.rows || this.state.rows.length === 0) {
      return '<div class="empty-editor-placeholder">Click "Add Row" to start building your content</div>';
    }

    return this.state.rows.map((row: Row, rowIndex: number) => `
      <div class="editor-row group" data-row-id="${row.id}" data-row-index="${rowIndex}">
        <div class="row-handle" draggable="true" title="Drag to reorder">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8h16M4 16h16"/>
          </svg>
        </div>
        <div class="row-content columns-${row.columns.length}">
          ${row.columns.map((col: Column, colIndex: number) => this.renderColumn(col, row.id, colIndex, row.columns.length)).join('')}
        </div>
        <div class="row-actions">
          <button type="button" class="row-action-btn" data-action="row-settings" data-row-id="${row.id}" title="Row Settings">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/>
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/>
            </svg>
          </button>
          <button type="button" class="row-action-btn row-delete" data-action="delete-row" data-row-id="${row.id}" title="Delete Row">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
            </svg>
          </button>
        </div>
      </div>
    `).join('');
  },

  renderColumn(this: any, column: Column, rowId: string, colIndex: number, totalColumns: number): string {
    // Calculate width - default to equal distribution if not set
    const defaultWidth = (100 / totalColumns).toFixed(2);
    const width = column.width || `${defaultWidth}%`;
    const widthValue = parseFloat(width.replace('%', ''));
    
    // Calculate the space taken by resize handles between columns
    // Each resize handle is 20px wide (with 8px margins), and there are (totalColumns - 1) handles
    const resizeHandlesCount = totalColumns - 1;
    const totalHandleWidth = resizeHandlesCount * 12; // Effective 12px per handle after margins
    // Each column needs to subtract its proportional share of the resize handle space
    const handleSpacePerColumn = (totalHandleWidth / totalColumns).toFixed(1);
    
    // Use calc() to subtract the resize handle space from each column's percentage
    const columnStyle = totalColumns > 1 
      ? `flex: 0 0 calc(${widthValue}% - ${handleSpacePerColumn}px); max-width: calc(${widthValue}% - ${handleSpacePerColumn}px);`
      : `flex: 0 0 ${widthValue}%; max-width: ${widthValue}%;`;
    
    // Render resize handle for all columns except the last one
    const resizeHandle = colIndex < totalColumns - 1 ? `
      <div class="column-resize-handle" data-row-id="${rowId}" data-left-col-id="${column.id}" data-col-index="${colIndex}">
        <div class="resize-handle-bar"></div>
      </div>
    ` : '';
    
    return `
      <div class="editor-column" style="${columnStyle}" data-column-id="${column.id}" data-row-id="${rowId}" data-col-index="${colIndex}" data-width="${width}">
        <div class="column-blocks">
          ${column.blocks.map((block: Block, blockIndex: number) => this.renderBlock(block, column.id, blockIndex)).join('')}
        </div>
        <div class="add-block-placeholder" data-column-id="${column.id}">
          <button type="button" class="add-block-btn" data-action="add-block-to-column" data-column-id="${column.id}">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"/>
            </svg>
            Add Block
          </button>
        </div>
      </div>${resizeHandle}
    `;
  },

  renderBlock(this: any, block: Block, columnId: string, blockIndex: number): string {
    const blockContent = this.renderBlockContent(block);
    
    return `
      <div class="content-block group/block block-${block.type}" data-block-id="${block.id}" data-column-id="${columnId}" data-block-index="${blockIndex}">
        <div class="block-handle" draggable="true" data-block-id="${block.id}" data-column-id="${columnId}" data-action="block-settings" title="Drag to reorder or click for options">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8h16M4 16h16"/>
          </svg>
        </div>
        <div class="block-content">
          ${blockContent}
        </div>
      </div>
    `;
  },

  renderBlockContent(this: any, block: Block): string {
    switch (block.type) {
      case 'text':
        return `
          <div class="rich-text-block" data-block-id="${block.id}">
            <div class="rich-text-toolbar" id="toolbar-${block.id}">
              <div class="toolbar-group">
                <select class="text-format-select" data-command="formatBlock">
                  <option value="p">Normal</option>
                  <option value="h1">Heading 1</option>
                  <option value="h2">Heading 2</option>
                  <option value="h3">Heading 3</option>
                  <option value="h4">Heading 4</option>
                </select>
              </div>
              <div class="toolbar-group">
                <select class="font-family-select" data-command="fontName" title="Font Family">
                  <option value="">Font</option>
                  <option value="Arial, sans-serif">Arial</option>
                  <option value="Georgia, serif">Georgia</option>
                  <option value="Times New Roman, serif">Times</option>
                  <option value="Courier New, monospace">Courier</option>
                  <option value="Verdana, sans-serif">Verdana</option>
                  <option value="Trebuchet MS, sans-serif">Trebuchet</option>
                  <option value="Impact, sans-serif">Impact</option>
                </select>
              </div>
              <div class="toolbar-group">
                <select class="font-size-select" data-command="fontSize" title="Font Size">
                  <option value="">Size</option>
                  <option value="1">10px</option>
                  <option value="2">13px</option>
                  <option value="3">16px</option>
                  <option value="4">18px</option>
                  <option value="5">24px</option>
                  <option value="6">32px</option>
                  <option value="7">48px</option>
                </select>
              </div>
              <div class="toolbar-group">
                <label class="color-picker-btn" title="Text Color">
                  <span class="color-icon">A</span>
                  <input type="color" class="text-color-input" data-command="foreColor" value="#ffffff">
                </label>
                <label class="color-picker-btn" title="Background Color">
                  <span class="bg-color-icon">▄</span>
                  <input type="color" class="bg-color-input" data-command="hiliteColor" value="#000000">
                </label>
              </div>
              <div class="toolbar-group">
                <button type="button" class="format-btn" data-command="bold" title="Bold (Ctrl+B)"><strong>B</strong></button>
                <button type="button" class="format-btn" data-command="italic" title="Italic (Ctrl+I)"><em>I</em></button>
                <button type="button" class="format-btn" data-command="underline" title="Underline (Ctrl+U)"><u>U</u></button>
                <button type="button" class="format-btn" data-command="strikeThrough" title="Strikethrough"><s>S</s></button>
              </div>
              <div class="toolbar-group">
                <button type="button" class="format-btn" data-command="insertOrderedList" title="Numbered List">1.</button>
                <button type="button" class="format-btn" data-command="insertUnorderedList" title="Bullet List">•</button>
              </div>
              <div class="toolbar-group">
                <button type="button" class="format-btn" data-command="justifyLeft" title="Align Left">⟨</button>
                <button type="button" class="format-btn" data-command="justifyCenter" title="Center">≡</button>
                <button type="button" class="format-btn" data-command="justifyRight" title="Align Right">⟩</button>
              </div>
              <div class="toolbar-group">
                <button type="button" class="format-btn link-btn" data-command="createLink" title="Insert Link">🔗</button>
                <button type="button" class="format-btn" data-command="removeFormat" title="Clear Formatting">✕</button>
              </div>
            </div>
            <div class="rich-text-editor" contenteditable="true" data-block-id="${block.id}" data-placeholder="Start typing...">${block.content || ''}</div>
          </div>
        `;
      
      case 'heading':
        const level = block.settings?.level || 2;
        return `
          <div class="heading-block">
            <select class="heading-level" data-block-id="${block.id}">
              ${[1,2,3,4,5,6].map(l => `<option value="${l}" ${l === level ? 'selected' : ''}>H${l}</option>`).join('')}
            </select>
            <input type="text" class="heading-input" data-block-id="${block.id}" value="${this.escapeHtml(block.content || '')}" placeholder="Heading text...">
          </div>
        `;
      
      case 'image':
        return `
          <div class="image-block">
            ${block.content ? `
              <img src="${block.content}" alt="${block.settings?.alt || ''}" class="block-image">
              <div class="image-caption">
                <input type="text" placeholder="Add caption..." value="${block.settings?.caption || ''}" data-block-id="${block.id}" class="caption-input">
              </div>
            ` : `
              <div class="image-upload-area" data-block-id="${block.id}">
                <input type="file" accept="image/*" class="image-file-input" data-block-id="${block.id}" style="display:none">
                <button type="button" class="image-upload-btn" data-action="upload-image" data-block-id="${block.id}">
                  <svg class="w-8 h-8 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                  </svg>
                  Click to upload or drag an image
                </button>
                <input type="text" placeholder="Or paste image URL..." class="image-url-input" data-block-id="${block.id}">
              </div>
            `}
          </div>
        `;
      
      case 'video':
        return `
          <div class="video-block">
            ${block.content ? `
              <div class="video-embed">${this.renderVideoEmbed(block.content)}</div>
            ` : `
              <div class="video-input-area">
                <input type="text" placeholder="Paste YouTube, Vimeo, or video URL..." class="video-url-input" data-block-id="${block.id}">
                <button type="button" class="embed-video-btn" data-action="embed-video" data-block-id="${block.id}">Embed</button>
              </div>
            `}
          </div>
        `;
      
      case 'code':
        return `
          <div class="code-block">
            <div class="code-block-toolbar">
              <select class="code-language" data-block-id="${block.id}">
                <option value="">Select language...</option>
                <option value="javascript" ${block.settings?.language === 'javascript' ? 'selected' : ''}>JavaScript</option>
                <option value="typescript" ${block.settings?.language === 'typescript' ? 'selected' : ''}>TypeScript</option>
                <option value="elixir" ${block.settings?.language === 'elixir' ? 'selected' : ''}>Elixir</option>
                <option value="python" ${block.settings?.language === 'python' ? 'selected' : ''}>Python</option>
                <option value="html" ${block.settings?.language === 'html' ? 'selected' : ''}>HTML</option>
                <option value="css" ${block.settings?.language === 'css' ? 'selected' : ''}>CSS</option>
                <option value="sql" ${block.settings?.language === 'sql' ? 'selected' : ''}>SQL</option>
                <option value="bash" ${block.settings?.language === 'bash' ? 'selected' : ''}>Bash</option>
              </select>
              <button type="button" class="code-copy-btn" data-action="copy-code" data-block-id="${block.id}" title="Copy code">Copy</button>
            </div>
            <textarea class="code-textarea" data-block-id="${block.id}" placeholder="Paste your code here...">${this.escapeHtml(block.content || '')}</textarea>
          </div>
        `;
      
      case 'quote':
        return `
          <div class="quote-block">
            <blockquote>
              <textarea class="quote-text" data-block-id="${block.id}" placeholder="Enter quote...">${this.escapeHtml(block.content || '')}</textarea>
              <cite>
                <input type="text" class="quote-author" data-block-id="${block.id}" value="${this.escapeHtml(block.settings?.author || '')}" placeholder="— Author">
              </cite>
            </blockquote>
          </div>
        `;
      
      case 'callout':
        const calloutType = block.settings?.calloutType || 'info';
        return `
          <div class="callout-block callout-${calloutType}">
            <select class="callout-type" data-block-id="${block.id}">
              <option value="info" ${calloutType === 'info' ? 'selected' : ''}>ℹ️ Info</option>
              <option value="warning" ${calloutType === 'warning' ? 'selected' : ''}>⚠️ Warning</option>
              <option value="success" ${calloutType === 'success' ? 'selected' : ''}>✅ Success</option>
              <option value="error" ${calloutType === 'error' ? 'selected' : ''}>❌ Error</option>
              <option value="tip" ${calloutType === 'tip' ? 'selected' : ''}>💡 Tip</option>
            </select>
            <textarea class="callout-content" data-block-id="${block.id}" placeholder="Callout content...">${this.escapeHtml(block.content || '')}</textarea>
          </div>
        `;
      
      case 'divider':
        return `<hr class="block-divider">`;
      
      case 'html':
        const htmlPreviewMode = block.settings?.previewMode || 'edit';
        return `
          <div class="html-block" data-block-id="${block.id}">
            <div class="html-block-header">
              <span class="html-block-label">
                <svg class="w-4 h-4 inline-block mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/>
                </svg>
                HTML Embed
              </span>
              <div class="html-mode-toggle">
                <button type="button" class="mode-btn ${htmlPreviewMode === 'edit' ? 'active' : ''}" data-action="html-mode" data-mode="edit" data-block-id="${block.id}">Edit</button>
                <button type="button" class="mode-btn ${htmlPreviewMode === 'preview' ? 'active' : ''}" data-action="html-mode" data-mode="preview" data-block-id="${block.id}">Preview</button>
              </div>
            </div>
            ${htmlPreviewMode === 'edit' ? `
              <textarea class="html-textarea" data-block-id="${block.id}" placeholder="Enter HTML code here...">${this.escapeHtml(block.content || '')}</textarea>
            ` : `
              <div class="html-preview">${block.content || '<p class="text-gray-500">No HTML content</p>'}</div>
            `}
          </div>
        `;
      
      case 'api':
        const apiMethod = block.settings?.method || 'GET';
        const apiHeaders = block.settings?.headers || '{}';
        const apiRefreshInterval = block.settings?.refreshInterval || 0;
        return `
          <div class="api-block" data-block-id="${block.id}">
            <div class="api-block-header">
              <span class="api-block-label">
                <svg class="w-4 h-4 inline-block mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                </svg>
                API Data
              </span>
            </div>
            <div class="api-config">
              <div class="api-url-row">
                <select class="api-method" data-block-id="${block.id}">
                  <option value="GET" ${apiMethod === 'GET' ? 'selected' : ''}>GET</option>
                  <option value="POST" ${apiMethod === 'POST' ? 'selected' : ''}>POST</option>
                </select>
                <input type="text" class="api-url-input" data-block-id="${block.id}" placeholder="https://api.example.com/data" value="${this.escapeHtml(block.content || '')}">
                <button type="button" class="api-fetch-btn" data-action="api-fetch" data-block-id="${block.id}">Fetch</button>
              </div>
              <details class="api-advanced">
                <summary>Advanced Options</summary>
                <div class="api-advanced-content">
                  <label>Headers (JSON):</label>
                  <textarea class="api-headers" data-block-id="${block.id}" placeholder='{"Authorization": "Bearer token"}'>${this.escapeHtml(apiHeaders)}</textarea>
                  <label>Refresh Interval (seconds, 0 = no auto-refresh):</label>
                  <input type="number" class="api-refresh" data-block-id="${block.id}" value="${apiRefreshInterval}" min="0">
                  <label>Response Template (use {{key}} for data):</label>
                  <textarea class="api-template" data-block-id="${block.id}" placeholder="<div>{{name}}: {{value}}</div>">${this.escapeHtml(block.settings?.template || '')}</textarea>
                </div>
              </details>
            </div>
            <div class="api-result" data-block-id="${block.id}">
              ${block.settings?.lastResult ? `
                <div class="api-result-content">${block.settings.lastResult}</div>
                <div class="api-result-time">Last fetched: ${block.settings.lastFetched || 'Unknown'}</div>
              ` : '<p class="text-gray-500">Click "Fetch" to load API data</p>'}
            </div>
          </div>
        `;
      
      case 'embed':
        return `
          <div class="embed-block">
            ${block.content ? `
              <div class="embed-preview">${block.content}</div>
            ` : `
              <div class="embed-input-area">
                <input type="text" placeholder="Paste embed URL or HTML..." class="embed-input" data-block-id="${block.id}">
                <button type="button" class="embed-btn" data-action="add-embed" data-block-id="${block.id}">Embed</button>
              </div>
            `}
          </div>
        `;
      
      case 'gallery':
        const mediaItems = block.media || [];
        const displayMode = block.settings?.displayMode || 'carousel';
        return `
          <div class="gallery-block" data-block-id="${block.id}" data-display-mode="${displayMode}">
            <div class="gallery-controls">
              <select class="gallery-display-mode" data-block-id="${block.id}">
                <option value="carousel" ${displayMode === 'carousel' ? 'selected' : ''}>🎠 Carousel</option>
                <option value="grid" ${displayMode === 'grid' ? 'selected' : ''}>⊞ Grid</option>
                <option value="masonry" ${displayMode === 'masonry' ? 'selected' : ''}>▦ Masonry</option>
              </select>
              <button type="button" class="gallery-add-btn" data-action="gallery-add" data-block-id="${block.id}">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                </svg>
                Add Images
              </button>
              <input type="file" accept="image/*" multiple class="gallery-file-input" data-block-id="${block.id}" style="display:none">
            </div>
            ${mediaItems.length > 0 ? `
              <div class="gallery-container gallery-${displayMode}">
                ${displayMode === 'carousel' ? `
                  <button type="button" class="gallery-nav gallery-prev" data-block-id="${block.id}" data-action="gallery-prev">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
                    </svg>
                  </button>
                ` : ''}
                <div class="gallery-items-wrapper">
                  <div class="gallery-items" data-current-index="${block.settings?.currentIndex || 0}">
                    ${mediaItems.map((item: MediaItem, idx: number) => `
                      <div class="gallery-item ${displayMode === 'carousel' && idx === (block.settings?.currentIndex || 0) ? 'active' : ''}" 
                           data-index="${idx}" data-item-id="${item.id}">
                        <img src="${item.url}" alt="${item.alt || ''}" class="gallery-image">
                        ${item.caption ? `<div class="gallery-caption">${item.caption}</div>` : ''}
                        <button type="button" class="gallery-remove-item" data-action="gallery-remove-item" 
                                data-block-id="${block.id}" data-item-id="${item.id}" title="Remove image">
                          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                          </svg>
                        </button>
                      </div>
                    `).join('')}
                  </div>
                  ${displayMode === 'carousel' ? `
                    <div class="gallery-dots">
                      ${mediaItems.map((_: MediaItem, idx: number) => `
                        <button type="button" class="gallery-dot ${idx === (block.settings?.currentIndex || 0) ? 'active' : ''}" 
                                data-block-id="${block.id}" data-action="gallery-goto" data-index="${idx}"></button>
                      `).join('')}
                    </div>
                  ` : ''}
                </div>
                ${displayMode === 'carousel' ? `
                  <button type="button" class="gallery-nav gallery-next" data-block-id="${block.id}" data-action="gallery-next">
                    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
                    </svg>
                  </button>
                ` : ''}
              </div>
            ` : `
              <div class="gallery-drop-zone" data-block-id="${block.id}">
                <svg class="w-12 h-12 mx-auto mb-3 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"/>
                </svg>
                <p class="text-gray-400 text-sm">Drag and drop images here or click to upload</p>
                <p class="text-gray-500 text-xs mt-1">Supports JPG, PNG, GIF, WebP</p>
              </div>
            `}
          </div>
        `;
      
      case 'audio':
        return `
          <div class="audio-block" data-block-id="${block.id}">
            ${block.content ? `
              <div class="audio-player-container">
                <audio controls class="audio-player" src="${block.content}">
                  Your browser does not support the audio element.
                </audio>
                <div class="audio-info">
                  <span class="audio-filename">${block.settings?.filename || 'Audio file'}</span>
                  <button type="button" class="audio-remove-btn" data-action="remove-media" data-block-id="${block.id}" title="Remove audio">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                    </svg>
                  </button>
                </div>
              </div>
            ` : `
              <div class="audio-upload-area" data-block-id="${block.id}">
                <input type="file" accept="audio/*" class="audio-file-input" data-block-id="${block.id}" style="display:none">
                <button type="button" class="audio-upload-btn" data-action="upload-audio" data-block-id="${block.id}">
                  <svg class="w-8 h-8 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"/>
                  </svg>
                  Click to upload or drag an audio file
                </button>
                <p class="text-gray-500 text-xs mt-2">Supports MP3, WAV, OGG, WebM audio</p>
                <input type="text" placeholder="Or paste audio URL..." class="audio-url-input" data-block-id="${block.id}">
              </div>
            `}
          </div>
        `;
      
      case 'file':
        const fileUrl = block.content || '';
        const fileName = block.settings?.filename || 'Download file';
        const fileSize = block.settings?.fileSize || '';
        const fileType = block.settings?.fileType || 'document';
        
        return `
          <div class="file-block" data-block-id="${block.id}">
            ${block.content ? `
              <div class="file-preview">
                <div class="file-icon">
                  ${this.getFileIcon(fileType)}
                </div>
                <div class="file-details">
                  <a href="${fileUrl}" target="_blank" class="file-name">${this.escapeHtml(fileName)}</a>
                  <span class="file-size">${this.escapeHtml(fileSize)}</span>
                </div>
                <button type="button" class="file-remove-btn" data-action="remove-media" data-block-id="${block.id}" title="Remove file">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                  </svg>
                </button>
              </div>
            ` : `
              <div class="file-upload-area" data-block-id="${block.id}">
                <input type="file" accept=".pdf,.doc,.docx,.txt,.zip,.rar" class="file-file-input" data-block-id="${block.id}" style="display:none">
                <button type="button" class="file-upload-btn" data-action="upload-file" data-block-id="${block.id}">
                  <svg class="w-8 h-8 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                  </svg>
                  Click to upload or drag a file
                </button>
                <p class="text-gray-500 text-xs mt-2">Supports PDF, Word, Text, ZIP files</p>
              </div>
            `}
          </div>
        `;
      
      default:
        return `<div class="unknown-block">Unknown block type: ${block.type}</div>`;
    }
  },

  getFileIcon(this: any, fileType: string): string {
    switch (fileType) {
      case 'pdf':
        return `<svg class="w-10 h-10 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
        </svg>`;
      case 'word':
        return `<svg class="w-10 h-10 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
        </svg>`;
      case 'archive':
        return `<svg class="w-10 h-10 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"/>
        </svg>`;
      default:
        return `<svg class="w-10 h-10 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
        </svg>`;
    }
  },

  renderVideoEmbed(this: any, url: string): string {
    // Extract video ID and create embed
    const youtubeMatch = url.match(/(?:youtube\.com\/(?:watch\?v=|embed\/)|youtu\.be\/)([^&\s]+)/);
    if (youtubeMatch) {
      return `<iframe src="https://www.youtube.com/embed/${youtubeMatch[1]}" frameborder="0" allowfullscreen class="video-iframe"></iframe>`;
    }
    
    const vimeoMatch = url.match(/vimeo\.com\/(\d+)/);
    if (vimeoMatch) {
      return `<iframe src="https://player.vimeo.com/video/${vimeoMatch[1]}" frameborder="0" allowfullscreen class="video-iframe"></iframe>`;
    }
    
    // Default: show as link
    return `<a href="${url}" target="_blank">${url}</a>`;
  },

  escapeHtml(this: any, str: string): string {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
  },

  initializeRichTextEditors(this: any) {
    // Find all rich text editor containers
    const textBlocks = this.el.querySelectorAll('.rich-text-block');
    console.log('🔤 Initializing rich text editors, found:', textBlocks.length, 'blocks');
    
    textBlocks.forEach((container: HTMLElement) => {
      const blockId = container.dataset.blockId;
      const editor = container.querySelector('.rich-text-editor') as HTMLElement;
      const toolbar = container.querySelector('.rich-text-toolbar') as HTMLElement;
      
      if (!editor || !blockId) {
        console.warn('⚠️ Missing editor or blockId for text block');
        return;
      }
      
      console.log('🔤 Setting up rich text editor for block:', blockId, editor);
      
      // Store reference
      this.richTextEditors.set(blockId, editor);
      
      // Ensure editor is editable - set attributes directly
      editor.setAttribute('contenteditable', 'true');
      editor.setAttribute('role', 'textbox');
      editor.setAttribute('aria-multiline', 'true');
      editor.tabIndex = 0;
      
      // CRITICAL: Stop event propagation on the editor to prevent parent handlers from interfering
      editor.addEventListener('mousedown', (e: MouseEvent) => {
        console.log('🔤 Editor mousedown, stopping propagation');
        e.stopPropagation();
      });
      
      // Add click handler to ensure focus works
      editor.addEventListener('click', (e: MouseEvent) => {
        console.log('🔤 Editor clicked, focusing...');
        e.stopPropagation();
        editor.focus();
      });
      
      // Handle toolbar button clicks
      toolbar.addEventListener('mousedown', (e: MouseEvent) => {
        const btn = (e.target as HTMLElement).closest('.format-btn, .text-format-select');
        if (btn) {
          // Only prevent default for toolbar buttons, not the whole toolbar
          e.preventDefault();
        }
      });
      
      toolbar.addEventListener('click', (e: MouseEvent) => {
        const btn = (e.target as HTMLElement).closest('.format-btn') as HTMLElement;
        if (!btn) return;
        
        e.preventDefault();
        e.stopPropagation();
        
        const command = btn.dataset.command;
        
        // Ensure editor is focused
        editor.focus();
        
        // Small delay to ensure focus is set
        requestAnimationFrame(() => {
          if (command === 'createLink') {
            const url = prompt('Enter URL:');
            if (url) {
              document.execCommand('createLink', false, url);
            }
          } else if (command) {
            document.execCommand(command, false);
          }
          
          this.updateBlockContent(blockId, 'text', editor.innerHTML);
        });
      });
      
      // Handle format select change
      const formatSelect = toolbar.querySelector('.text-format-select') as HTMLSelectElement;
      if (formatSelect) {
        formatSelect.addEventListener('mousedown', (e: MouseEvent) => {
          // Store current selection before dropdown steals focus
          const selection = window.getSelection();
          if (selection && selection.rangeCount > 0) {
            (editor as any)._savedRange = selection.getRangeAt(0).cloneRange();
          }
        });
        
        formatSelect.addEventListener('change', (e: Event) => {
          const value = (e.target as HTMLSelectElement).value;
          
          // Restore selection if saved
          editor.focus();
          const savedRange = (editor as any)._savedRange;
          if (savedRange) {
            const selection = window.getSelection();
            if (selection) {
              selection.removeAllRanges();
              selection.addRange(savedRange);
            }
          }
          
          document.execCommand('formatBlock', false, value);
          this.updateBlockContent(blockId, 'text', editor.innerHTML);
        });
      }
      
      // Handle font family select
      const fontFamilySelect = toolbar.querySelector('.font-family-select') as HTMLSelectElement;
      if (fontFamilySelect) {
        fontFamilySelect.addEventListener('mousedown', (e: MouseEvent) => {
          const selection = window.getSelection();
          if (selection && selection.rangeCount > 0) {
            (editor as any)._savedRange = selection.getRangeAt(0).cloneRange();
          }
        });
        
        fontFamilySelect.addEventListener('change', (e: Event) => {
          const value = (e.target as HTMLSelectElement).value;
          if (!value) return;
          
          editor.focus();
          const savedRange = (editor as any)._savedRange;
          if (savedRange) {
            const selection = window.getSelection();
            if (selection) {
              selection.removeAllRanges();
              selection.addRange(savedRange);
            }
          }
          
          document.execCommand('fontName', false, value);
          this.updateBlockContent(blockId, 'text', editor.innerHTML);
        });
      }
      
      // Handle font size select
      const fontSizeSelect = toolbar.querySelector('.font-size-select') as HTMLSelectElement;
      if (fontSizeSelect) {
        fontSizeSelect.addEventListener('mousedown', (e: MouseEvent) => {
          const selection = window.getSelection();
          if (selection && selection.rangeCount > 0) {
            (editor as any)._savedRange = selection.getRangeAt(0).cloneRange();
          }
        });
        
        fontSizeSelect.addEventListener('change', (e: Event) => {
          const value = (e.target as HTMLSelectElement).value;
          if (!value) return;
          
          editor.focus();
          const savedRange = (editor as any)._savedRange;
          if (savedRange) {
            const selection = window.getSelection();
            if (selection) {
              selection.removeAllRanges();
              selection.addRange(savedRange);
            }
          }
          
          document.execCommand('fontSize', false, value);
          this.updateBlockContent(blockId, 'text', editor.innerHTML);
        });
      }
      
      // Handle text color picker
      const textColorInput = toolbar.querySelector('.text-color-input') as HTMLInputElement;
      if (textColorInput) {
        textColorInput.addEventListener('input', (e: Event) => {
          const value = (e.target as HTMLInputElement).value;
          editor.focus();
          document.execCommand('foreColor', false, value);
          this.updateBlockContent(blockId, 'text', editor.innerHTML);
        });
      }
      
      // Handle background color picker
      const bgColorInput = toolbar.querySelector('.bg-color-input') as HTMLInputElement;
      if (bgColorInput) {
        bgColorInput.addEventListener('input', (e: Event) => {
          const value = (e.target as HTMLInputElement).value;
          editor.focus();
          document.execCommand('hiliteColor', false, value);
          this.updateBlockContent(blockId, 'text', editor.innerHTML);
        });
      }
      
      // Show toolbar on focus
      editor.addEventListener('focus', () => {
        toolbar.classList.add('active');
      });
      
      // Hide toolbar on blur (with delay for button clicks)
      editor.addEventListener('blur', () => {
        setTimeout(() => {
          if (!container.contains(document.activeElement)) {
            toolbar.classList.remove('active');
          }
        }, 200);
      });
      
      // Handle content changes
      editor.addEventListener('input', () => {
        this.updateBlockContent(blockId, 'text', editor.innerHTML);
        this.scheduleAutosave();
      });
      
      // Handle keyboard shortcuts
      editor.addEventListener('keydown', (e: KeyboardEvent) => {
        if (e.ctrlKey || e.metaKey) {
          switch (e.key.toLowerCase()) {
            case 'b':
              e.preventDefault();
              document.execCommand('bold', false);
              break;
            case 'i':
              e.preventDefault();
              document.execCommand('italic', false);
              break;
            case 'u':
              e.preventDefault();
              document.execCommand('underline', false);
              break;
          }
        }
      });
      
      // Handle paste - clean up pasted content
      editor.addEventListener('paste', (e: ClipboardEvent) => {
        e.preventDefault();
        const text = e.clipboardData?.getData('text/html') || e.clipboardData?.getData('text/plain') || '';
        
        // Insert as HTML but clean it up
        const temp = document.createElement('div');
        temp.innerHTML = text;
        
        // Remove script tags and event handlers
        temp.querySelectorAll('script, style').forEach(el => el.remove());
        
        // Clean up the HTML
        const cleanHtml = temp.innerHTML;
        document.execCommand('insertHTML', false, cleanHtml);
        
        this.updateBlockContent(blockId, 'text', editor.innerHTML);
        this.scheduleAutosave();
      });
    });
  },

  setupEventListeners(this: any) {
    // Toolbar actions
    this.el.addEventListener('click', (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const actionBtn = target.closest('[data-action]') as HTMLElement;
      
      if (!actionBtn) return;
      
      const action = actionBtn.dataset.action;
      
      switch (action) {
        case 'add-row':
          this.addRow(1);
          break;
        case 'add-columns-2':
          this.addRow(2);
          break;
        case 'add-columns-3':
          this.addRow(3);
          break;
        case 'add-columns-4':
          this.addRow(4);
          break;
        case 'add-columns-5':
          this.addRow(5);
          break;
        case 'add-columns-6':
          this.addRow(6);
          break;
        case 'add-columns-7':
          this.addRow(7);
          break;
        case 'add-columns-8':
          this.addRow(8);
          break;
        case 'add-block':
          const blockType = actionBtn.dataset.blockType as BlockType;
          this.addBlockToLastColumn(blockType);
          break;
        case 'add-block-to-column':
          const columnId = actionBtn.dataset.columnId;
          this.showBlockTypeMenu(actionBtn, columnId!);
          break;
        case 'delete-row':
          const rowId = actionBtn.dataset.rowId;
          this.deleteRow(rowId!);
          break;
        case 'delete-block':
          const deleteBlockId = actionBtn.dataset.blockId;
          this.deleteBlock(deleteBlockId!);
          break;
        case 'upload-image':
          const imgBlockId = actionBtn.dataset.blockId;
          const imgFileInput = this.el.querySelector(`.image-file-input[data-block-id="${imgBlockId}"]`);
          if (imgFileInput) imgFileInput.click();
          break;
        case 'embed-video':
          const vidBlockId = actionBtn.dataset.blockId;
          const vidUrlInput = this.el.querySelector(`.video-url-input[data-block-id="${vidBlockId}"]`) as HTMLInputElement;
          if (vidUrlInput && vidUrlInput.value) {
            this.updateBlockContent(vidBlockId!, 'video', vidUrlInput.value);
            this.render();
          }
          break;
        // Gallery actions
        case 'gallery-add':
          const galleryBlockId = actionBtn.dataset.blockId;
          const galleryFileInput = this.el.querySelector(`.gallery-file-input[data-block-id="${galleryBlockId}"]`);
          if (galleryFileInput) galleryFileInput.click();
          break;
        case 'gallery-prev':
          this.galleryNavigate(actionBtn.dataset.blockId!, -1);
          break;
        case 'gallery-next':
          this.galleryNavigate(actionBtn.dataset.blockId!, 1);
          break;
        case 'gallery-goto':
          this.galleryGoTo(actionBtn.dataset.blockId!, parseInt(actionBtn.dataset.index || '0'));
          break;
        case 'gallery-remove-item':
          this.galleryRemoveItem(actionBtn.dataset.blockId!, actionBtn.dataset.itemId!);
          break;
        // Audio actions
        case 'upload-audio':
          const audioBlockId = actionBtn.dataset.blockId;
          const audioFileInput = this.el.querySelector(`.audio-file-input[data-block-id="${audioBlockId}"]`);
          if (audioFileInput) audioFileInput.click();
          break;
        // File actions
        case 'upload-file':
          const fileBlockId = actionBtn.dataset.blockId;
          const fileFileInput = this.el.querySelector(`.file-file-input[data-block-id="${fileBlockId}"]`);
          if (fileFileInput) fileFileInput.click();
          break;
        // Remove media (audio/file blocks)
        case 'remove-media':
          const removeBlockId = actionBtn.dataset.blockId;
          this.removeMediaFromBlock(removeBlockId!);
          break;
        // Row settings (column layout editing)
        case 'row-settings':
          const settingsRowId = actionBtn.dataset.rowId;
          this.showRowSettingsMenu(actionBtn, settingsRowId!);
          break;
        // Block settings
        case 'block-settings':
          const blockSettingsId = actionBtn.dataset.blockId;
          this.showBlockSettingsMenu(actionBtn, blockSettingsId!);
          break;
        // Copy code
        case 'copy-code':
          const codeBlockId = actionBtn.dataset.blockId;
          const codeTextarea = this.el.querySelector(`.code-textarea[data-block-id="${codeBlockId}"]`) as HTMLTextAreaElement;
          if (codeTextarea) {
            navigator.clipboard.writeText(codeTextarea.value).then(() => {
              actionBtn.textContent = 'Copied!';
              setTimeout(() => { actionBtn.textContent = 'Copy'; }, 2000);
            });
          }
          break;
        // HTML block mode toggle
        case 'html-mode':
          const htmlBlockId = actionBtn.dataset.blockId;
          const htmlMode = actionBtn.dataset.mode;
          this.updateBlockSettings(htmlBlockId!, { previewMode: htmlMode });
          this.render();
          break;
        // API fetch
        case 'api-fetch':
          const apiBlockId = actionBtn.dataset.blockId;
          this.fetchApiData(apiBlockId!);
          break;
      }
    });
    
    // Handle input changes for various block types
    this.el.addEventListener('input', (e: Event) => {
      const target = e.target as HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
      const blockId = target.dataset.blockId;
      
      if (!blockId) return;
      
      if (target.classList.contains('heading-input')) {
        this.updateBlockContent(blockId, 'heading', target.value);
      } else if (target.classList.contains('code-textarea')) {
        this.updateBlockContent(blockId, 'code', target.value);
      } else if (target.classList.contains('quote-text')) {
        this.updateBlockContent(blockId, 'quote', target.value);
      } else if (target.classList.contains('callout-content')) {
        this.updateBlockContent(blockId, 'callout', target.value);
      } else if (target.classList.contains('caption-input')) {
        this.updateBlockSettings(blockId, { caption: target.value });
      } else if (target.classList.contains('quote-author')) {
        this.updateBlockSettings(blockId, { author: target.value });
      } else if (target.classList.contains('html-textarea')) {
        this.updateBlockContent(blockId, 'html', target.value);
      } else if (target.classList.contains('api-url-input')) {
        this.updateBlockContent(blockId, 'api', target.value);
      } else if (target.classList.contains('api-headers')) {
        this.updateBlockSettings(blockId, { headers: target.value });
      } else if (target.classList.contains('api-template')) {
        this.updateBlockSettings(blockId, { template: target.value });
      } else if (target.classList.contains('api-refresh')) {
        this.updateBlockSettings(blockId, { refreshInterval: parseInt(target.value) || 0 });
      }
      
      this.scheduleAutosave();
    });
    
    // Handle select changes
    this.el.addEventListener('change', (e: Event) => {
      const target = e.target as HTMLSelectElement;
      const blockId = target.dataset.blockId;
      
      if (!blockId) return;
      
      if (target.classList.contains('heading-level')) {
        this.updateBlockSettings(blockId, { level: parseInt(target.value) });
      } else if (target.classList.contains('code-language')) {
        this.updateBlockSettings(blockId, { language: target.value });
      } else if (target.classList.contains('callout-type')) {
        this.updateBlockSettings(blockId, { calloutType: target.value });
        // Re-render to apply new callout styling
        this.render();
      } else if (target.classList.contains('api-method')) {
        this.updateBlockSettings(blockId, { method: target.value });
      }
      
      this.scheduleAutosave();
    });
    
    // Handle image file uploads
    this.el.addEventListener('change', (e: Event) => {
      const target = e.target as HTMLInputElement;
      if (target.classList.contains('image-file-input') && target.files?.[0]) {
        const blockId = target.dataset.blockId;
        this.handleImageUpload(blockId!, target.files[0]);
      } else if (target.classList.contains('gallery-file-input') && target.files?.length) {
        const blockId = target.dataset.blockId;
        this.handleGalleryUpload(blockId!, Array.from(target.files));
      } else if (target.classList.contains('audio-file-input') && target.files?.[0]) {
        const blockId = target.dataset.blockId;
        this.handleAudioUpload(blockId!, target.files[0]);
      } else if (target.classList.contains('file-file-input') && target.files?.[0]) {
        const blockId = target.dataset.blockId;
        this.handleFileUpload(blockId!, target.files[0]);
      } else if (target.classList.contains('gallery-display-mode')) {
        const blockId = target.dataset.blockId;
        this.updateBlockSettings(blockId!, { displayMode: target.value });
        this.render();
      }
    });
    
    // Handle image URL input
    this.el.addEventListener('keypress', (e: KeyboardEvent) => {
      const target = e.target as HTMLInputElement;
      if (target.classList.contains('image-url-input') && e.key === 'Enter') {
        const blockId = target.dataset.blockId;
        if (target.value) {
          this.updateBlockContent(blockId!, 'image', target.value);
          this.render();
        }
      } else if (target.classList.contains('audio-url-input') && e.key === 'Enter') {
        const blockId = target.dataset.blockId;
        if (target.value) {
          this.updateBlockContent(blockId!, 'audio', target.value);
          this.updateBlockSettings(blockId!, { filename: 'External audio' });
          this.render();
        }
      }
    });
    
    // Drag and drop for blocks AND files
    this.setupDragAndDrop();
    this.setupFileDragDrop();
    this.setupColumnResize();
  },

  setupColumnResize(this: any) {
    // Column resize handle drag functionality
    let isResizing = false;
    let resizeData: {
      rowId: string;
      leftColId: string;
      rightColId: string;
      colIndex: number;
      startX: number;
      rowContent: HTMLElement;
      leftCol: HTMLElement;
      rightCol: HTMLElement;
      initialLeftWidth: number;
      initialRightWidth: number;
      totalWidth: number;
    } | null = null;

    this.el.addEventListener('mousedown', (e: MouseEvent) => {
      const handle = (e.target as HTMLElement).closest('.column-resize-handle') as HTMLElement;
      if (!handle) return;

      e.preventDefault();
      e.stopPropagation();
      isResizing = true;

      const rowId = handle.dataset.rowId!;
      const leftColId = handle.dataset.leftColId!;
      const colIndex = parseInt(handle.dataset.colIndex || '0');

      // Find the row and columns
      const rowContent = handle.closest('.row-content') as HTMLElement;
      const columns = rowContent.querySelectorAll('.editor-column');
      const leftCol = columns[colIndex] as HTMLElement;
      const rightCol = columns[colIndex + 1] as HTMLElement;

      if (!leftCol || !rightCol) return;

      const rightColId = rightCol.dataset.columnId!;

      // Get initial widths as percentages - prefer calc values, fall back to data attributes
      const getWidthFromElement = (el: HTMLElement): number => {
        const styleValue = el.style.flex?.split(' ')[2] || el.style.maxWidth || '';
        // Extract percentage from calc() or direct percentage
        const calcMatch = styleValue.match(/calc\(([\d.]+)%/);
        if (calcMatch) return parseFloat(calcMatch[1]);
        const percentMatch = styleValue.match(/([\d.]+)%/);
        if (percentMatch) return parseFloat(percentMatch[1]);
        return parseFloat(el.dataset.width?.replace('%', '') || '50');
      };
      
      const leftWidth = getWidthFromElement(leftCol);
      const rightWidth = getWidthFromElement(rightCol);

      resizeData = {
        rowId,
        leftColId,
        rightColId,
        colIndex,
        startX: e.clientX,
        rowContent,
        leftCol,
        rightCol,
        initialLeftWidth: leftWidth,
        initialRightWidth: rightWidth,
        totalWidth: leftWidth + rightWidth
      };

      handle.classList.add('resizing');
      rowContent.classList.add('resizing');
      document.body.style.cursor = 'col-resize';
      document.body.style.userSelect = 'none';
    });

    document.addEventListener('mousemove', (e: MouseEvent) => {
      if (!isResizing || !resizeData) return;

      const { rowContent, leftCol, rightCol, startX, initialLeftWidth, initialRightWidth, totalWidth } = resizeData;

      // Calculate the delta as a percentage of the row width
      const rowWidth = rowContent.offsetWidth;
      const deltaX = e.clientX - startX;
      const deltaPercent = (deltaX / rowWidth) * 100;

      // Calculate new widths
      let newLeftWidth = initialLeftWidth + deltaPercent;
      let newRightWidth = initialRightWidth - deltaPercent;

      // Minimum column width of 10%
      const minWidth = 10;
      if (newLeftWidth < minWidth) {
        newLeftWidth = minWidth;
        newRightWidth = totalWidth - minWidth;
      } else if (newRightWidth < minWidth) {
        newRightWidth = minWidth;
        newLeftWidth = totalWidth - minWidth;
      }

      // Update the visual widths - store the percentage values as data attributes for easy retrieval
      leftCol.style.flex = `0 0 ${newLeftWidth}%`;
      leftCol.style.maxWidth = `${newLeftWidth}%`;
      leftCol.dataset.currentWidth = `${newLeftWidth}`;
      rightCol.style.flex = `0 0 ${newRightWidth}%`;
      rightCol.style.maxWidth = `${newRightWidth}%`;
      rightCol.dataset.currentWidth = `${newRightWidth}`;
    });

    document.addEventListener('mouseup', (e: MouseEvent) => {
      if (!isResizing || !resizeData) return;

      const { rowId, leftColId, rightColId, leftCol, rightCol, rowContent, colIndex } = resizeData;

      // Get the final widths from the data attributes we set during drag
      const newLeftWidth = parseFloat(leftCol.dataset.currentWidth || leftCol.dataset.width?.replace('%', '') || '50');
      const newRightWidth = parseFloat(rightCol.dataset.currentWidth || rightCol.dataset.width?.replace('%', '') || '50');

      // Update the state
      const row = this.state.rows.find((r: Row) => r.id === rowId);
      if (row) {
        const leftColumn = row.columns.find((c: Column) => c.id === leftColId);
        const rightColumn = row.columns.find((c: Column) => c.id === rightColId);
        if (leftColumn) leftColumn.width = `${newLeftWidth.toFixed(2)}%`;
        if (rightColumn) rightColumn.width = `${newRightWidth.toFixed(2)}%`;

        this.updateHiddenInput();
        this.scheduleAutosave();
      }

      // Clean up data attributes
      delete leftCol.dataset.currentWidth;
      delete rightCol.dataset.currentWidth;

      // Clean up
      const handle = rowContent.querySelector('.column-resize-handle.resizing');
      if (handle) handle.classList.remove('resizing');
      rowContent.classList.remove('resizing');
      document.body.style.cursor = '';
      document.body.style.userSelect = '';

      isResizing = false;
      resizeData = null;
    });
  },

  setupFileDragDrop(this: any) {
    // File drag and drop onto the editor or specific blocks
    const dropZone = this.el.querySelector('.block-editor-content');
    if (!dropZone) return;

    ['dragenter', 'dragover', 'dragleave', 'drop'].forEach(eventName => {
      dropZone.addEventListener(eventName, (e: Event) => {
        e.preventDefault();
        e.stopPropagation();
      });
    });

    ['dragenter', 'dragover'].forEach(eventName => {
      dropZone.addEventListener(eventName, () => {
        dropZone.classList.add('file-drag-over');
      });
    });

    ['dragleave', 'drop'].forEach(eventName => {
      dropZone.addEventListener(eventName, () => {
        dropZone.classList.remove('file-drag-over');
      });
    });

    dropZone.addEventListener('drop', (e: DragEvent) => {
      // Check if this is a file drop (not a block reorder)
      const files = e.dataTransfer?.files;
      if (!files || files.length === 0) return;

      // Check if dropped onto a specific block
      const target = e.target as HTMLElement;
      const imageBlock = target.closest('.image-block, .image-upload-area');
      const galleryBlock = target.closest('.gallery-block, .gallery-drop-zone');
      const audioBlock = target.closest('.audio-block, .audio-upload-area');
      const fileBlock = target.closest('.file-block, .file-upload-area');

      if (imageBlock) {
        const blockId = imageBlock.closest('[data-block-id]')?.getAttribute('data-block-id') || 
                        (imageBlock as HTMLElement).dataset.blockId;
        if (blockId && files[0]) {
          this.handleImageUpload(blockId, files[0]);
        }
      } else if (galleryBlock) {
        const blockId = galleryBlock.closest('[data-block-id]')?.getAttribute('data-block-id') ||
                        (galleryBlock as HTMLElement).dataset.blockId;
        if (blockId) {
          this.handleGalleryUpload(blockId, Array.from(files));
        }
      } else if (audioBlock) {
        const blockId = audioBlock.closest('[data-block-id]')?.getAttribute('data-block-id') ||
                        (audioBlock as HTMLElement).dataset.blockId;
        if (blockId && files[0]) {
          this.handleAudioUpload(blockId, files[0]);
        }
      } else if (fileBlock) {
        const blockId = fileBlock.closest('[data-block-id]')?.getAttribute('data-block-id') ||
                        (fileBlock as HTMLElement).dataset.blockId;
        if (blockId && files[0]) {
          this.handleFileUpload(blockId, files[0]);
        }
      } else {
        // Dropped onto the editor generally - create appropriate block based on file type
        this.handleGeneralFileDrop(Array.from(files));
      }
    });
  },

  handleGeneralFileDrop(this: any, files: File[]) {
    // Create blocks based on file types
    files.forEach(file => {
      const category = getFileCategory(file.type);
      
      switch (category) {
        case 'image':
          if (files.length > 1) {
            // Multiple images - create gallery block
            const galleryBlock = this.addBlockToLastColumn('gallery');
            if (galleryBlock) {
              this.handleGalleryUpload(galleryBlock.id, files.filter(f => getFileCategory(f.type) === 'image'));
            }
            return; // Process all images at once
          } else {
            const imageBlock = this.addBlockToLastColumn('image');
            if (imageBlock) {
              this.handleImageUpload(imageBlock.id, file);
            }
          }
          break;
        case 'video':
          const videoBlock = this.addBlockToLastColumn('video');
          if (videoBlock) {
            this.handleVideoUpload(videoBlock.id, file);
          }
          break;
        case 'audio':
          const audioBlock = this.addBlockToLastColumn('audio');
          if (audioBlock) {
            this.handleAudioUpload(audioBlock.id, file);
          }
          break;
        case 'document':
          const fileBlock = this.addBlockToLastColumn('file');
          if (fileBlock) {
            this.handleFileUpload(fileBlock.id, file);
          }
          break;
        default:
          console.warn('Unsupported file type:', file.type);
      }
    });
  },

  setupDragAndDrop(this: any) {
    // Block handle dragging
    this.el.addEventListener('dragstart', (e: DragEvent) => {
      const target = e.target as HTMLElement;
      
      // Handle block handle dragging
      if (target.classList.contains('block-handle')) {
        const blockId = target.dataset.blockId;
        const columnId = target.dataset.columnId;
        const block = target.closest('.content-block') as HTMLElement;
        
        if (blockId && columnId && block) {
          e.dataTransfer?.setData('text/plain', blockId);
          e.dataTransfer!.effectAllowed = 'move';
          block.classList.add('dragging');
          this.draggedBlock = { type: 'block', id: blockId, columnId: columnId };
        }
      }
      // Handle row handle dragging  
      else if (target.classList.contains('row-handle')) {
        const row = target.closest('.editor-row') as HTMLElement;
        if (row && row.dataset.rowId) {
          e.dataTransfer?.setData('text/plain', row.dataset.rowId);
          e.dataTransfer!.effectAllowed = 'move';
          row.classList.add('dragging');
          this.draggedBlock = { type: 'row', id: row.dataset.rowId };
        }
      }
    });
    
    this.el.addEventListener('dragend', (e: DragEvent) => {
      document.querySelectorAll('.dragging').forEach(el => el.classList.remove('dragging'));
      document.querySelectorAll('.drag-over').forEach(el => el.classList.remove('drag-over'));
      this.draggedBlock = null;
    });
    
    this.el.addEventListener('dragover', (e: DragEvent) => {
      e.preventDefault();
      e.dataTransfer!.dropEffect = 'move';
      
      const target = e.target as HTMLElement;
      
      if (this.draggedBlock?.type === 'block') {
        const dropTarget = target.closest('.content-block, .column-blocks') as HTMLElement;
        if (dropTarget && !dropTarget.classList.contains('dragging')) {
          dropTarget.classList.add('drag-over');
        }
      } else if (this.draggedBlock?.type === 'row') {
        const dropTarget = target.closest('.editor-row') as HTMLElement;
        if (dropTarget && !dropTarget.classList.contains('dragging')) {
          dropTarget.classList.add('drag-over');
        }
      }
    });
    
    this.el.addEventListener('dragleave', (e: DragEvent) => {
      const target = e.target as HTMLElement;
      target.classList.remove('drag-over');
    });
    
    this.el.addEventListener('drop', (e: DragEvent) => {
      e.preventDefault();
      
      document.querySelectorAll('.drag-over').forEach(el => el.classList.remove('drag-over'));
      
      if (!this.draggedBlock) return;
      
      const target = e.target as HTMLElement;
      
      if (this.draggedBlock.type === 'block') {
        const dropTarget = target.closest('.content-block, .column-blocks') as HTMLElement;
        if (dropTarget) {
          const targetBlockId = dropTarget.dataset.blockId;
          const targetColumnId = dropTarget.dataset.columnId || dropTarget.closest('.editor-column')?.getAttribute('data-column-id');
          
          this.moveBlock(
            this.draggedBlock.id,
            this.draggedBlock.columnId,
            targetColumnId!,
            targetBlockId
          );
        }
      } else if (this.draggedBlock.type === 'row') {
        const dropTarget = target.closest('.editor-row') as HTMLElement;
        if (dropTarget) {
          const targetRowId = dropTarget.dataset.rowId;
          this.moveRow(this.draggedBlock.id, targetRowId!);
        }
      }
    });
  },

  addRow(this: any, numColumns: number = 1) {
    // Support 1-8 columns
    const colCount = Math.max(1, Math.min(8, numColumns));
    const widthPercent = (100 / colCount).toFixed(2);
    
    const newRow: Row = {
      id: generateId(),
      columns: [],
      settings: {}
    };
    
    for (let i = 0; i < colCount; i++) {
      newRow.columns.push({
        id: generateId(),
        width: `${widthPercent}%`,
        blocks: [{
          id: generateId(),
          type: 'text',
          content: ''
        }]
      });
    }
    
    this.state.rows.push(newRow);
    this.render();
    this.scheduleAutosave();
  },

  addBlockToLastColumn(this: any, blockType: BlockType): Block | null {
    // Add block to the last column of the last row
    if (this.state.rows.length === 0) {
      this.addRow(1);
    }
    
    const lastRow = this.state.rows[this.state.rows.length - 1];
    const lastColumn = lastRow.columns[lastRow.columns.length - 1];
    
    return this.addBlockToColumn(lastColumn.id, blockType);
  },

  addBlockToColumn(this: any, columnId: string, blockType: BlockType): Block | null {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        if (col.id === columnId) {
          const newBlock: Block = {
            id: generateId(),
            type: blockType,
            content: '',
            settings: {},
            media: blockType === 'gallery' ? [] : undefined
          };
          col.blocks.push(newBlock);
          this.render();
          this.scheduleAutosave();
          return newBlock;
        }
      }
    }
    return null;
  },

  showBlockTypeMenu(this: any, button: HTMLElement, columnId: string) {
    // Create a popup menu for selecting block type
    const existingMenu = document.querySelector('.block-type-menu');
    if (existingMenu) existingMenu.remove();
    
    const menu = document.createElement('div');
    menu.className = 'block-type-menu';
    menu.innerHTML = `
      <button data-type="text">📝 Text</button>
      <button data-type="heading">🔤 Heading</button>
      <button data-type="image">🖼️ Image</button>
      <button data-type="gallery">🎠 Gallery</button>
      <button data-type="video">🎬 Video</button>
      <button data-type="audio">🎵 Audio</button>
      <button data-type="file">📄 File</button>
      <button data-type="code">💻 Code</button>
      <button data-type="quote">💬 Quote</button>
      <button data-type="callout">📌 Callout</button>
      <button data-type="html">🔧 HTML Embed</button>
      <button data-type="api">⚡ API Data</button>
      <button data-type="divider">➖ Divider</button>
    `;
    
    const rect = button.getBoundingClientRect();
    menu.style.position = 'fixed';
    menu.style.zIndex = '9999';
    
    // Append to body first to get actual dimensions
    document.body.appendChild(menu);
    
    const menuRect = menu.getBoundingClientRect();
    const viewportHeight = window.innerHeight;
    const viewportWidth = window.innerWidth;
    
    // Calculate position with viewport boundary checking
    let left = rect.left;
    let top = rect.bottom + 5;
    
    // Check if menu would go off the right edge
    if (left + menuRect.width > viewportWidth - 10) {
      left = viewportWidth - menuRect.width - 10;
    }
    
    // Check if menu would go off the bottom edge - show above button instead
    if (top + menuRect.height > viewportHeight - 10) {
      top = rect.top - menuRect.height - 5;
      // If still off screen (not enough room above), just pin to bottom
      if (top < 10) {
        top = viewportHeight - menuRect.height - 10;
      }
    }
    
    // Ensure left is not negative
    if (left < 10) left = 10;
    
    menu.style.left = `${left}px`;
    menu.style.top = `${top}px`;
    
    menu.addEventListener('click', (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const blockType = target.dataset.type as BlockType;
      if (blockType) {
        this.addBlockToColumn(columnId, blockType);
        menu.remove();
      }
    });
    
    // Menu already appended above for dimension calculation
    
    // Close menu on click outside
    const closeMenu = (e: MouseEvent) => {
      if (!menu.contains(e.target as Node)) {
        menu.remove();
        document.removeEventListener('click', closeMenu);
      }
    };
    setTimeout(() => document.addEventListener('click', closeMenu), 0);
  },

  showRowSettingsMenu(this: any, button: HTMLElement, rowId: string) {
    // Create a popup menu for row settings (column layout)
    const existingMenu = document.querySelector('.row-settings-menu');
    if (existingMenu) existingMenu.remove();
    
    const row = this.state.rows.find((r: Row) => r.id === rowId);
    if (!row) return;
    
    const currentCols = row.columns.length;
    
    // Column count buttons
    const colButtons = [1,2,3,4,5,6,7,8].map(n => {
      const icons: Record<number, string> = {1: '▣', 2: '▥', 3: '⊟', 4: '⊞', 5: '▦', 6: '⋮⋮', 7: '⋮⋮⋮', 8: '⊞⊞'};
      return `<button data-cols="${n}" class="${currentCols === n ? 'active' : ''}" title="${n} Column${n > 1 ? 's' : ''}">${icons[n]} ${n}</button>`;
    }).join('');
    
    // Show current column widths info
    const widthsInfo = row.columns.map((col: Column, i: number) => {
      const width = col.width || 'auto';
      return `Col ${i+1}: ${width}`;
    }).join(' | ');
    
    const menu = document.createElement('div');
    menu.className = 'row-settings-menu';
    menu.innerHTML = `
      <div class="menu-title">Column Layout</div>
      <div class="column-count-grid">
        ${colButtons}
      </div>
      <div class="menu-divider"></div>
      <div class="menu-info">Drag handles between columns to resize</div>
      <div class="menu-widths">${widthsInfo}</div>
      <div class="menu-divider"></div>
      <button data-action="reset-widths">⊜ Reset Equal Widths</button>
      <button data-action="move-up" ${this.state.rows.indexOf(row) === 0 ? 'disabled' : ''}>↑ Move Up</button>
      <button data-action="move-down" ${this.state.rows.indexOf(row) === this.state.rows.length - 1 ? 'disabled' : ''}>↓ Move Down</button>
      <button data-action="duplicate">⧉ Duplicate Row</button>
    `;
    
    const rect = button.getBoundingClientRect();
    menu.style.position = 'fixed';
    menu.style.left = `${Math.min(rect.left, window.innerWidth - 280)}px`;
    menu.style.top = `${rect.bottom + 5}px`;
    menu.style.zIndex = '1000';
    
    menu.addEventListener('click', (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const cols = target.dataset.cols;
      const action = target.dataset.action;
      
      if (cols) {
        this.changeRowColumns(rowId, parseInt(cols));
        menu.remove();
      } else if (action === 'move-up') {
        this.moveRowUp(rowId);
        menu.remove();
      } else if (action === 'move-down') {
        this.moveRowDown(rowId);
        menu.remove();
      } else if (action === 'duplicate') {
        this.duplicateRow(rowId);
        menu.remove();
      } else if (action === 'reset-widths') {
        this.resetColumnWidths(rowId);
        menu.remove();
      }
    });
    
    document.body.appendChild(menu);
    
    // Close menu on click outside
    const closeMenu = (e: MouseEvent) => {
      if (!menu.contains(e.target as Node)) {
        menu.remove();
        document.removeEventListener('click', closeMenu);
      }
    };
    setTimeout(() => document.addEventListener('click', closeMenu), 0);
  },

  showBlockSettingsMenu(this: any, button: HTMLElement, blockId: string) {
    // Find the block and its info
    let block: Block | null = null;
    let columnId: string | null = null;
    let blockIndex: number = -1;
    let totalBlocks: number = 0;
    let currentRowIndex: number = -1;
    let currentColIndex: number = -1;
    
    for (let ri = 0; ri < this.state.rows.length; ri++) {
      const row = this.state.rows[ri];
      for (let ci = 0; ci < row.columns.length; ci++) {
        const col = row.columns[ci];
        const idx = col.blocks.findIndex((b: Block) => b.id === blockId);
        if (idx !== -1) {
          block = col.blocks[idx];
          columnId = col.id;
          blockIndex = idx;
          totalBlocks = col.blocks.length;
          currentRowIndex = ri;
          currentColIndex = ci;
          break;
        }
      }
      if (block) break;
    }
    
    if (!block) return;
    
    // Build move to column options
    const currentRow = this.state.rows[currentRowIndex];
    const hasMultipleColumns = currentRow.columns.length > 1;
    const hasMultipleRows = this.state.rows.length > 1;
    
    let moveToColumnHtml = '';
    if (hasMultipleColumns) {
      moveToColumnHtml = '<div class="menu-divider"></div><div class="menu-subtitle">Move to Column</div>';
      currentRow.columns.forEach((col: Column, colIdx: number) => {
        if (colIdx !== currentColIndex) {
          moveToColumnHtml += `<button data-action="move-to-column" data-target-column="${col.id}">→ Column ${colIdx + 1}</button>`;
        }
      });
    }
    
    let moveToRowHtml = '';
    if (hasMultipleRows) {
      moveToRowHtml = '<div class="menu-divider"></div><div class="menu-subtitle">Move to Row</div>';
      this.state.rows.forEach((row: Row, rowIdx: number) => {
        if (rowIdx !== currentRowIndex) {
          // Move to first column of the target row
          moveToRowHtml += `<button data-action="move-to-row" data-target-row="${rowIdx}">→ Row ${rowIdx + 1}</button>`;
        }
      });
    }
    
    // Create popup menu
    const existingMenu = document.querySelector('.block-settings-menu');
    if (existingMenu) existingMenu.remove();
    
    const menu = document.createElement('div');
    menu.className = 'block-settings-menu';
    menu.innerHTML = `
      <div class="menu-title">Block Actions</div>
      <button data-action="move-up" ${blockIndex === 0 ? 'disabled' : ''}>↑ Move Up</button>
      <button data-action="move-down" ${blockIndex >= totalBlocks - 1 ? 'disabled' : ''}>↓ Move Down</button>
      ${moveToColumnHtml}
      ${moveToRowHtml}
      <div class="menu-divider"></div>
      <button data-action="duplicate">⧉ Duplicate</button>
      <button data-action="delete" class="danger">🗑️ Delete Block</button>
    `;
    
    const rect = button.getBoundingClientRect();
    menu.style.position = 'fixed';
    menu.style.left = `${Math.min(rect.left, window.innerWidth - 200)}px`;
    menu.style.top = `${rect.bottom + 5}px`;
    menu.style.zIndex = '1000';
    
    menu.addEventListener('click', (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const action = target.dataset.action;
      
      if (action === 'move-up') {
        this.moveBlockInColumn(blockId, columnId!, -1);
        menu.remove();
      } else if (action === 'move-down') {
        this.moveBlockInColumn(blockId, columnId!, 1);
        menu.remove();
      } else if (action === 'move-to-column') {
        const targetColumnId = target.dataset.targetColumn;
        if (targetColumnId) {
          this.moveBlock(blockId, columnId!, targetColumnId);
        }
        menu.remove();
      } else if (action === 'move-to-row') {
        const targetRowIdx = parseInt(target.dataset.targetRow || '-1');
        if (targetRowIdx >= 0 && targetRowIdx < this.state.rows.length) {
          const targetRow = this.state.rows[targetRowIdx];
          const targetColumnId = targetRow.columns[0]?.id;
          if (targetColumnId) {
            this.moveBlock(blockId, columnId!, targetColumnId);
          }
        }
        menu.remove();
      } else if (action === 'duplicate') {
        this.duplicateBlock(blockId);
        menu.remove();
      } else if (action === 'delete') {
        this.deleteBlock(blockId);
        menu.remove();
      }
    });
    
    document.body.appendChild(menu);
    
    // Close menu on click outside
    const closeMenu = (e: MouseEvent) => {
      if (!menu.contains(e.target as Node)) {
        menu.remove();
        document.removeEventListener('click', closeMenu);
      }
    };
    setTimeout(() => document.addEventListener('click', closeMenu), 0);
  },

  moveBlockInColumn(this: any, blockId: string, columnId: string, direction: number) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        if (col.id === columnId) {
          const idx = col.blocks.findIndex((b: Block) => b.id === blockId);
          if (idx !== -1) {
            const newIdx = idx + direction;
            if (newIdx >= 0 && newIdx < col.blocks.length) {
              const [block] = col.blocks.splice(idx, 1);
              col.blocks.splice(newIdx, 0, block);
              this.render();
              this.scheduleAutosave();
            }
          }
          return;
        }
      }
    }
  },

  duplicateBlock(this: any, blockId: string) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        const idx = col.blocks.findIndex((b: Block) => b.id === blockId);
        if (idx !== -1) {
          const original = col.blocks[idx];
          const duplicate: Block = {
            ...JSON.parse(JSON.stringify(original)),
            id: generateId()
          };
          col.blocks.splice(idx + 1, 0, duplicate);
          this.render();
          this.scheduleAutosave();
          return;
        }
      }
    }
  },

  changeRowColumns(this: any, rowId: string, newColCount: number) {
    const row = this.state.rows.find((r: Row) => r.id === rowId);
    if (!row) return;
    
    // Limit to 1-8 columns
    newColCount = Math.max(1, Math.min(8, newColCount));
    const currentCount = row.columns.length;
    
    if (newColCount === currentCount) return;
    
    // Calculate equal width percentage
    const widthPercent = (100 / newColCount).toFixed(2);
    
    if (newColCount > currentCount) {
      // Add columns with equal width
      for (let i = currentCount; i < newColCount; i++) {
        row.columns.push({
          id: generateId(),
          width: `${widthPercent}%`,
          blocks: [{
            id: generateId(),
            type: 'text',
            content: ''
          }]
        });
      }
      // Update widths of existing columns to equal distribution
      row.columns.forEach((col: Column) => col.width = `${widthPercent}%`);
    } else {
      // Collect blocks ONLY from columns that will be removed
      const blocksFromRemovedColumns: Block[] = [];
      for (let i = newColCount; i < currentCount; i++) {
        blocksFromRemovedColumns.push(...row.columns[i].blocks);
      }
      
      // Keep only the first newColCount columns
      row.columns = row.columns.slice(0, newColCount);
      
      // Add the collected blocks from removed columns to the first column
      if (blocksFromRemovedColumns.length > 0) {
        row.columns[0].blocks.push(...blocksFromRemovedColumns);
      }
      
      // Set equal widths for remaining columns
      row.columns.forEach((col: Column) => col.width = `${widthPercent}%`);
    }
    
    this.render();
    this.scheduleAutosave();
  },

  resetColumnWidths(this: any, rowId: string) {
    const row = this.state.rows.find((r: Row) => r.id === rowId);
    if (!row) return;
    
    const widthPercent = (100 / row.columns.length).toFixed(2);
    row.columns.forEach((col: Column) => col.width = `${widthPercent}%`);
    
    this.render();
    this.scheduleAutosave();
  },

  moveRowUp(this: any, rowId: string) {
    const idx = this.state.rows.findIndex((r: Row) => r.id === rowId);
    if (idx > 0) {
      [this.state.rows[idx - 1], this.state.rows[idx]] = [this.state.rows[idx], this.state.rows[idx - 1]];
      this.render();
      this.scheduleAutosave();
    }
  },

  moveRowDown(this: any, rowId: string) {
    const idx = this.state.rows.findIndex((r: Row) => r.id === rowId);
    if (idx < this.state.rows.length - 1) {
      [this.state.rows[idx], this.state.rows[idx + 1]] = [this.state.rows[idx + 1], this.state.rows[idx]];
      this.render();
      this.scheduleAutosave();
    }
  },

  duplicateRow(this: any, rowId: string) {
    const row = this.state.rows.find((r: Row) => r.id === rowId);
    if (!row) return;
    
    // Deep clone the row with new IDs
    const newRow: Row = {
      id: generateId(),
      columns: row.columns.map((col: Column) => ({
        id: generateId(),
        width: col.width,
        blocks: col.blocks.map((block: Block) => ({
          ...block,
          id: generateId(),
          media: block.media ? block.media.map(m => ({...m, id: generateId()})) : undefined
        }))
      })),
      settings: {...row.settings}
    };
    
    const idx = this.state.rows.indexOf(row);
    this.state.rows.splice(idx + 1, 0, newRow);
    this.render();
    this.scheduleAutosave();
  },

  deleteRow(this: any, rowId: string) {
    this.state.rows = this.state.rows.filter((r: Row) => r.id !== rowId);
    this.render();
    this.scheduleAutosave();
  },

  deleteBlock(this: any, blockId: string) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        col.blocks = col.blocks.filter((b: Block) => b.id !== blockId);
      }
    }
    this.render();
    this.scheduleAutosave();
  },

  moveBlock(this: any, blockId: string, fromColumnId: string, toColumnId: string, beforeBlockId?: string) {
    let block: Block | null = null;
    
    // Remove from source
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        const idx = col.blocks.findIndex((b: Block) => b.id === blockId);
        if (idx !== -1) {
          block = col.blocks.splice(idx, 1)[0];
          break;
        }
      }
      if (block) break;
    }
    
    if (!block) return;
    
    // Add to target
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        if (col.id === toColumnId) {
          if (beforeBlockId) {
            const targetIdx = col.blocks.findIndex((b: Block) => b.id === beforeBlockId);
            if (targetIdx !== -1) {
              col.blocks.splice(targetIdx, 0, block);
            } else {
              col.blocks.push(block);
            }
          } else {
            col.blocks.push(block);
          }
          break;
        }
      }
    }
    
    this.render();
    this.scheduleAutosave();
  },

  moveRow(this: any, fromRowId: string, beforeRowId: string) {
    const fromIdx = this.state.rows.findIndex((r: Row) => r.id === fromRowId);
    const toIdx = this.state.rows.findIndex((r: Row) => r.id === beforeRowId);
    
    if (fromIdx === -1 || toIdx === -1 || fromIdx === toIdx) return;
    
    const [row] = this.state.rows.splice(fromIdx, 1);
    this.state.rows.splice(toIdx, 0, row);
    
    this.render();
    this.scheduleAutosave();
  },

  updateBlockContent(this: any, blockId: string, type: BlockType, content: any) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        for (const block of col.blocks) {
          if (block.id === blockId) {
            block.content = content;
            this.updateHiddenInput();
            return;
          }
        }
      }
    }
  },

  updateBlockSettings(this: any, blockId: string, settings: Record<string, any>) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        for (const block of col.blocks) {
          if (block.id === blockId) {
            block.settings = { ...block.settings, ...settings };
            this.updateHiddenInput();
            return;
          }
        }
      }
    }
  },

  fetchApiData(this: any, blockId: string) {
    // Find the block
    let block: Block | null = null;
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        for (const b of col.blocks) {
          if (b.id === blockId) {
            block = b;
            break;
          }
        }
      }
    }
    
    if (!block || !block.content) {
      console.warn('API block not found or no URL set');
      return;
    }
    
    const url = block.content;
    const method = block.settings?.method || 'GET';
    let headers: Record<string, string> = {};
    
    try {
      headers = JSON.parse(block.settings?.headers || '{}');
    } catch (e) {
      console.warn('Invalid headers JSON:', e);
    }
    
    // Show loading state
    const resultDiv = this.el.querySelector(`.api-result[data-block-id="${blockId}"]`);
    if (resultDiv) {
      resultDiv.innerHTML = '<p class="text-blue-400">Loading...</p>';
    }
    
    fetch(url, { method, headers })
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        return response.json();
      })
      .then(data => {
        let displayHtml = '';
        const template = block.settings?.template;
        
        if (template) {
          // Apply template
          displayHtml = template.replace(/\{\{(\w+(?:\.\w+)*)\}\}/g, (match: string, path: string) => {
            const keys = path.split('.');
            let value: any = data;
            for (const key of keys) {
              value = value?.[key];
            }
            return value !== undefined ? String(value) : match;
          });
        } else {
          // Default: pretty-print JSON
          displayHtml = `<pre class="api-json">${JSON.stringify(data, null, 2)}</pre>`;
        }
        
        const now = new Date().toLocaleTimeString();
        this.updateBlockSettings(blockId, { 
          lastResult: displayHtml, 
          lastFetched: now,
          error: null
        });
        
        if (resultDiv) {
          resultDiv.innerHTML = `
            <div class="api-result-content">${displayHtml}</div>
            <div class="api-result-time">Last fetched: ${now}</div>
          `;
        }
        
        this.scheduleAutosave();
      })
      .catch(error => {
        const errorHtml = `<p class="text-red-400">Error: ${error.message}</p>`;
        this.updateBlockSettings(blockId, { 
          lastResult: errorHtml, 
          lastFetched: new Date().toLocaleTimeString(),
          error: error.message
        });
        
        if (resultDiv) {
          resultDiv.innerHTML = errorHtml;
        }
      });
  },

  handleImageUpload(this: any, blockId: string, file: File) {
    // Validate file
    if (!ALLOWED_IMAGE_TYPES.includes(file.type)) {
      console.warn('Invalid image type:', file.type);
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      console.warn('File too large:', file.size);
      return;
    }

    // Show loading state
    this.updateBlockSettings(blockId, { loading: true });
    this.render();

    // Upload to server via LiveView
    this.uploadFileToServer(file, blockId, 'image');
  },

  handleGalleryUpload(this: any, blockId: string, files: File[]) {
    const validFiles = files.filter(f => ALLOWED_IMAGE_TYPES.includes(f.type) && f.size <= MAX_FILE_SIZE);
    
    if (validFiles.length === 0) {
      console.warn('No valid image files');
      return;
    }

    // Upload each file
    validFiles.forEach(file => {
      this.uploadFileToServer(file, blockId, 'gallery');
    });
  },

  handleVideoUpload(this: any, blockId: string, file: File) {
    if (!ALLOWED_VIDEO_TYPES.includes(file.type)) {
      console.warn('Invalid video type:', file.type);
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      console.warn('File too large:', file.size);
      return;
    }

    this.updateBlockSettings(blockId, { loading: true });
    this.uploadFileToServer(file, blockId, 'video');
  },

  handleAudioUpload(this: any, blockId: string, file: File) {
    if (!ALLOWED_AUDIO_TYPES.includes(file.type)) {
      console.warn('Invalid audio type:', file.type);
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      console.warn('File too large:', file.size);
      return;
    }

    this.updateBlockSettings(blockId, { loading: true, filename: file.name });
    this.uploadFileToServer(file, blockId, 'audio');
  },

  handleFileUpload(this: any, blockId: string, file: File) {
    if (file.size > MAX_FILE_SIZE) {
      console.warn('File too large:', file.size);
      return;
    }

    // Determine file type
    let fileType = 'document';
    if (file.type === 'application/pdf') fileType = 'pdf';
    else if (file.type.includes('word')) fileType = 'word';
    else if (file.type.includes('zip') || file.type.includes('rar')) fileType = 'archive';

    this.updateBlockSettings(blockId, { 
      loading: true, 
      filename: file.name,
      fileType,
      fileSize: this.formatFileSize(file.size)
    });
    this.uploadFileToServer(file, blockId, 'file');
  },

  uploadFileToServer(this: any, file: File, blockId: string, mediaType: string) {
    // Read file as base64 and send to LiveView
    const reader = new FileReader();
    reader.onload = (e) => {
      const base64Data = (e.target?.result as string).split(',')[1]; // Remove data URL prefix
      
      this.pushEvent('block-media-upload', {
        blockId,
        mediaType,
        filename: file.name,
        size: file.size,
        mimeType: file.type,
        data: base64Data
      });
    };
    reader.onerror = () => {
      console.error('Failed to read file');
      this.updateBlockSettings(blockId, { loading: false, error: 'Failed to read file' });
      this.render();
    };
    reader.readAsDataURL(file);
  },

  formatFileSize(this: any, bytes: number): string {
    if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(1)} MB`;
    if (bytes >= 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${bytes} B`;
  },

  // Gallery navigation
  galleryNavigate(this: any, blockId: string, direction: number) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        for (const block of col.blocks) {
          if (block.id === blockId && block.type === 'gallery') {
            const items = block.media || [];
            if (items.length === 0) return;
            
            let currentIndex = block.settings?.currentIndex || 0;
            currentIndex = (currentIndex + direction + items.length) % items.length;
            
            block.settings = { ...block.settings, currentIndex };
            this.render();
            return;
          }
        }
      }
    }
  },

  galleryGoTo(this: any, blockId: string, index: number) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        for (const block of col.blocks) {
          if (block.id === blockId && block.type === 'gallery') {
            block.settings = { ...block.settings, currentIndex: index };
            this.render();
            return;
          }
        }
      }
    }
  },

  galleryRemoveItem(this: any, blockId: string, itemId: string) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        for (const block of col.blocks) {
          if (block.id === blockId && block.type === 'gallery') {
            block.media = (block.media || []).filter((item: MediaItem) => item.id !== itemId);
            
            // Notify LiveView to remove from database
            this.pushEvent('block-media-remove', { blockId, itemId });
            
            // Adjust current index if needed
            if (block.settings?.currentIndex >= block.media.length) {
              block.settings.currentIndex = Math.max(0, block.media.length - 1);
            }
            
            this.render();
            this.scheduleAutosave();
            return;
          }
        }
      }
    }
  },

  removeMediaFromBlock(this: any, blockId: string) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        for (const block of col.blocks) {
          if (block.id === blockId) {
            // Notify LiveView to remove from database
            if (block.content) {
              this.pushEvent('block-media-remove', { blockId, url: block.content });
            }
            
            block.content = '';
            block.settings = {};
            this.render();
            this.scheduleAutosave();
            return;
          }
        }
      }
    }
  },

  // Add media item to gallery block
  addMediaToGallery(this: any, blockId: string, mediaItem: MediaItem) {
    for (const row of this.state.rows) {
      for (const col of row.columns) {
        for (const block of col.blocks) {
          if (block.id === blockId && block.type === 'gallery') {
            if (!block.media) block.media = [];
            block.media.push(mediaItem);
            this.updateHiddenInput();
            this.render();
            return;
          }
        }
      }
    }
  },

  updateHiddenInput(this: any) {
    const editorId = this.el.id;
    const hiddenInput = document.getElementById(`${editorId}-input`) as HTMLInputElement;
    
    if (hiddenInput) {
      // Store both formats: JSON for block editor, HTML for backwards compatibility
      const jsonContent = JSON.stringify(this.state);
      const htmlContent = this.stateToHtml();
      
      // Store JSON in hidden input
      hiddenInput.value = jsonContent;
      hiddenInput.dispatchEvent(new Event('input', { bubbles: true }));
    }
  },

  stateToHtml(this: any): string {
    // Convert block state to HTML for display/fallback
    let html = '';
    
    for (const row of this.state.rows) {
      const isMultiColumn = row.columns.length > 1;
      
      if (isMultiColumn) {
        html += `<div class="content-row columns-${row.columns.length}">`;
      }
      
      for (const col of row.columns) {
        if (isMultiColumn) {
          html += `<div class="content-column" style="flex: 1;">`;
        }
        
        for (const block of col.blocks) {
          html += this.blockToHtml(block);
        }
        
        if (isMultiColumn) {
          html += '</div>';
        }
      }
      
      if (isMultiColumn) {
        html += '</div>';
      }
    }
    
    return html;
  },

  blockToHtml(this: any, block: Block): string {
    switch (block.type) {
      case 'text':
        return block.content || '';
      
      case 'heading':
        const level = block.settings?.level || 2;
        return `<h${level}>${block.content || ''}</h${level}>`;
      
      case 'image':
        const alt = block.settings?.alt || '';
        const caption = block.settings?.caption || '';
        return `<figure><img src="${block.content}" alt="${alt}"><figcaption>${caption}</figcaption></figure>`;
      
      case 'gallery':
        const items = block.media || [];
        if (items.length === 0) return '';
        return `<div class="gallery gallery-${block.settings?.displayMode || 'grid'}">${
          items.map((item: MediaItem) => `<figure><img src="${item.url}" alt="${item.alt || ''}">${item.caption ? `<figcaption>${item.caption}</figcaption>` : ''}</figure>`).join('')
        }</div>`;
      
      case 'video':
        // Check if it's an uploaded video file or an embed
        if (block.content && (block.content.startsWith('/uploads') || block.content.startsWith('http'))) {
          if (block.content.includes('youtube') || block.content.includes('vimeo')) {
            return this.renderVideoEmbed(block.content);
          }
          return `<video controls src="${block.content}" class="block-video"></video>`;
        }
        return this.renderVideoEmbed(block.content || '');
      
      case 'audio':
        return block.content ? `<audio controls src="${block.content}" class="block-audio"></audio>` : '';
      
      case 'file':
        if (!block.content) return '';
        return `<a href="${block.content}" class="file-download" target="_blank" download>
          ${block.settings?.filename || 'Download file'}
          ${block.settings?.fileSize ? ` (${block.settings.fileSize})` : ''}
        </a>`;
      
      case 'code':
        const lang = block.settings?.language || '';
        return `<pre><code class="language-${lang}">${this.escapeHtml(block.content || '')}</code></pre>`;
      
      case 'quote':
        const author = block.settings?.author || '';
        return `<blockquote>${block.content || ''}<cite>${author}</cite></blockquote>`;
      
      case 'callout':
        const calloutType = block.settings?.calloutType || 'info';
        return `<div class="callout callout-${calloutType}">${block.content || ''}</div>`;
      
      case 'html':
        // Return raw HTML (with safety note - user is responsible for content)
        return block.content || '';
      
      case 'api':
        // Return the last fetched result or a placeholder
        return block.settings?.lastResult || '<div class="api-placeholder">API Data Block</div>';
      
      case 'divider':
        return '<hr>';
      
      default:
        return '';
    }
  },

  scheduleAutosave(this: any) {
    if (this.autosaveTimeout) {
      clearTimeout(this.autosaveTimeout);
    }
    
    this.autosaveTimeout = setTimeout(() => {
      this.save();
    }, this.config.autosaveDelay);
  },

  save(this: any) {
    const content = JSON.stringify(this.state);
    const html = this.stateToHtml();
    
    this.pushEvent('editor-change', {
      content,
      html,
      format: 'blocks'
    });
    
    this.pushEvent('editor-autosave', {
      content,
      html,
      format: 'blocks'
    });
  },

  setupLiveViewHandlers(this: any) {
    // Listen for content updates from LiveView
    this.handleEvent('update-editor-content', ({ content }: { content: string }) => {
      try {
        const parsed = JSON.parse(content);
        if (parsed.rows) {
          this.state = parsed;
          this.render();
        }
      } catch {
        // If not JSON, convert HTML to blocks
        this.state = this.htmlToBlocks(content);
        this.render();
      }
    });
    
    // Listen for media upload success (unified handler for all media types)
    this.handleEvent('block-media-uploaded', ({ blockId, url, mediaType, filename, mediaId }: { 
      blockId: string; 
      url: string; 
      mediaType: string;
      filename?: string;
      mediaId?: string;
    }) => {
      // Clear loading state
      this.updateBlockSettings(blockId, { loading: false });
      
      if (mediaType === 'gallery') {
        // Add to gallery
        this.addMediaToGallery(blockId, {
          id: mediaId || generateId(),
          url,
          type: 'image',
          filename
        });
      } else {
        // Update block content
        this.updateBlockContent(blockId, mediaType as BlockType, url);
        if (filename) {
          this.updateBlockSettings(blockId, { filename });
        }
        this.render();
      }
      
      this.scheduleAutosave();
    });
    
    // Listen for upload errors
    this.handleEvent('block-media-error', ({ blockId, error }: { blockId: string; error: string }) => {
      this.updateBlockSettings(blockId, { loading: false, error });
      this.render();
      console.error('Upload error:', error);
    });

    // Legacy handler for backward compatibility
    this.handleEvent('block-image-uploaded', ({ blockId, url }: { blockId: string; url: string }) => {
      this.updateBlockContent(blockId, 'image', url);
      this.updateBlockSettings(blockId, { loading: false });
      this.render();
    });
  },

  destroyed(this: any) {
    // Clean up rich text editor references
    this.richTextEditors.clear();
    
    // Clear autosave timeout
    if (this.autosaveTimeout) {
      clearTimeout(this.autosaveTimeout);
    }
  }
};

export default BlockEditorHook;
