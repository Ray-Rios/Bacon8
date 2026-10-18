/**
 * Collaborative Quill Editor Hook with Y.js CRDT
 * 
 * Enables real-time collaborative editing with:
 * - Conflict-free replicated data type (CRDT) via Y.js
 * - Live cursor positions for all users
 * - Presence awareness (who's online)
 * - Automatic conflict resolution
 */

import Quill from 'quill';
import QuillCursors from 'quill-cursors';
import * as Y from 'yjs';
import { Socket } from "phoenix";
// Quill CSS is imported via PostCSS in assets/css/app.css (@import "quill/dist/quill.snow.css"),
// so it should not be imported in TS files. esbuild may otherwise produce runtime require calls
// which are not supported in the browser and will throw an error preventing JS execution.

// Register the cursors module
Quill.register('modules/cursors', QuillCursors);

interface CollaborativeEditorConfig {
  documentId: string;
  userId: string;
  userName: string;
  userColor: string;
  channelTopic: string;
  autosaveDelay?: number;
  placeholder?: string;
  readOnly?: boolean;
}

const CollaborativeQuillHook = {
  mounted(this: any) {
    const config: CollaborativeEditorConfig = {
      documentId: this.el.dataset.documentId,
      userId: this.el.dataset.userId,
      userName: this.el.dataset.userName || 'Anonymous',
      userColor: this.el.dataset.userColor || '#3B82F6',
      channelTopic: `collab:${this.el.dataset.documentId}`,
      autosaveDelay: parseInt(this.el.dataset.autosaveDelay || '30000'),
      placeholder: this.el.dataset.placeholder || 'Start writing...',
      readOnly: this.el.dataset.readonly === 'true'
    };

    // Initialize Y.js document
    this.ydoc = new Y.Doc();
    this.ytext = this.ydoc.getText('quill');
    
    // Track awareness (user cursors and presence)
    this.awareness = {
      clientID: this.ydoc.clientID,
      states: new Map()
    };

    // Create Quill editor with cursors module
    this.quill = new Quill(this.el, {
      theme: 'snow',
      readOnly: config.readOnly,
      placeholder: config.placeholder,
      modules: {
        cursors: {
          transformOnTextChange: true,
        },
        toolbar: [
          [{ 'header': [1, 2, 3, 4, 5, 6, false] }],
          [{ 'font': [] }],
          [{ 'size': ['small', false, 'large', 'huge'] }],
          ['bold', 'italic', 'underline', 'strike'],
          [{ 'color': [] }, { 'background': [] }],
          [{ 'script': 'sub'}, { 'script': 'super' }],
          [{ 'list': 'ordered'}, { 'list': 'bullet' }],
          [{ 'indent': '-1'}, { 'indent': '+1' }],
          [{ 'direction': 'rtl' }],
          [{ 'align': [] }],
          ['blockquote', 'code-block'],
          ['link', 'image', 'video'],
          ['clean']
        ]
      }
    });

    this.cursors = this.quill.getModule('cursors');

    // Connect to Phoenix Channel for Y.js sync
    this.connectChannel(config);

    // Bind Y.js to Quill
    this.bindYjsToQuill();

    // Track local cursor changes
    this.quill.on('selection-change', (range: any) => {
      if (range) {
        this.broadcastCursor(range, config);
      }
    });

    // Set initial content
    const initialContent = this.el.querySelector('input[type="hidden"]')?.value;
    if (initialContent && this.ytext.length === 0) {
      try {
        const delta = JSON.parse(initialContent);
        this.quill.setContents(delta);
      } catch {
        // If not Delta format, assume HTML
        this.quill.root.innerHTML = initialContent;
      }
    }

    // Auto-save
    let autosaveTimeout: any;
    this.quill.on('text-change', () => {
      if (config.autosaveDelay > 0) {
        clearTimeout(autosaveTimeout);
        autosaveTimeout = setTimeout(() => {
          this.autosave();
        }, config.autosaveDelay);
      }
    });
  },

  connectChannel(this: any, config: CollaborativeEditorConfig) {
    // Create a dedicated socket connection for collaborative editing
    // This avoids multiplexing over the LiveView socket which can cause issues
    // and ensures we use the authenticated UserSocket
    const socket = new Socket("/socket", {
      params: { token: this.el.dataset.userToken }
    });
    socket.connect();
    this.socket = socket;

    // Join Phoenix Channel
    this.channel = socket.channel(config.channelTopic, {
      user_id: config.userId
    });

    this.channel.join()
      .receive('ok', (resp: any) => {
        console.log('✅ Joined collaborative editing channel', resp);
        this.syncDocument();
      })
      .receive('error', (resp: any) => {
        console.error('❌ Failed to join channel', resp);
      });

    // Handle Y.js sync updates from other clients
    this.channel.on('sync_update', (payload: any) => {
      const update = new Uint8Array(payload.update);
      Y.applyUpdate(this.ydoc, update);
    });

    // Handle cursor updates
    this.channel.on('cursor_update', (payload: any) => {
      if (payload.user_id !== config.userId) {
        this.updateRemoteCursor(payload);
      }
    });

    // Handle presence updates
    this.channel.on('presence_state', (state: any) => {
      this.updatePresence(state);
    });

    this.channel.on('presence_diff', (diff: any) => {
      this.handlePresenceDiff(diff);
    });

    // Handle user typing indicators
    this.channel.on('user_typing', (payload: any) => {
      this.showTypingIndicator(payload);
    });
  },

  bindYjsToQuill(this: any) {
    // Apply Y.js changes to Quill
    this.ytext.observe((event: any) => {
      if (event.transaction.origin !== this.quill) {
        const delta = event.delta;
        this.quill.updateContents(delta, 'silent');
      }
    });

    // Apply Quill changes to Y.js
    this.quill.on('text-change', (delta: any, oldDelta: any, source: string) => {
      if (source !== 'silent') {
        // Convert Quill delta to Y.js operations
        this.ydoc.transact(() => {
          delta.ops.forEach((op: any) => {
            if (op.retain) {
              // No-op for retain
            } else if (op.insert) {
              this.ytext.insert(0, op.insert);
            } else if (op.delete) {
              this.ytext.delete(0, op.delete);
            }
          });
        }, this.quill);

        // Broadcast update to other clients
        this.broadcastUpdate();
      }
    });
  },

  syncDocument(this: any) {
    // Y.js sync protocol: Step 1 - Send state vector
    const stateVector = Y.encodeStateVector(this.ydoc);
    
    this.channel.push('sync_step1', { vector: Array.from(stateVector) })
      .receive('ok', (resp: any) => {
        if (resp.updates && resp.updates.length > 0) {
          // Apply missing updates
          resp.updates.forEach((update: number[]) => {
            Y.applyUpdate(this.ydoc, new Uint8Array(update));
          });
        }
      });
  },

  broadcastUpdate(this: any) {
    // Broadcast Y.js update to server
    const update = Y.encodeStateAsUpdate(this.ydoc);
    this.channel.push('sync_step2', { update: Array.from(update) });
  },

  broadcastCursor(this: any, range: any, config: CollaborativeEditorConfig) {
    this.channel.push('cursor', {
      position: range.index,
      selection: range.length,
      user_id: config.userId,
      name: config.userName,
      color: config.userColor
    });
  },

  updateRemoteCursor(this: any, payload: any) {
    // Update or create cursor for remote user
    const { user_id, name, color, position, selection } = payload;
    
    if (!this.cursors.cursors().find((c: any) => c.id === user_id)) {
      this.cursors.createCursor(user_id, name, color);
    }
    
    this.cursors.moveCursor(user_id, {
      index: position,
      length: selection
    });
  },

  updatePresence(this: any, state: any) {
    // Update awareness with current online users
    console.log('👥 Presence state:', state);
    this.awareness.states = new Map(Object.entries(state));
    this.renderPresenceIndicators();
  },

  handlePresenceDiff(this: any, diff: any) {
    // Handle users joining/leaving
    if (diff.joins) {
      Object.keys(diff.joins).forEach(userId => {
        console.log('👤 User joined:', userId);
      });
    }
    if (diff.leaves) {
      Object.keys(diff.leaves).forEach(userId => {
        console.log('👋 User left:', userId);
        this.cursors.removeCursor(userId);
      });
    }
  },

  renderPresenceIndicators(this: any) {
    // Show avatars of currently editing users
    const container = document.getElementById(`${this.el.id}-presence`);
    if (!container) return;

    const users = Array.from(this.awareness.states.values());
    container.innerHTML = users.map((user: any) => {
      return `
        <div class="flex items-center space-x-1 px-2 py-1 bg-gray-700 rounded-full text-xs">
          <div class="w-6 h-6 rounded-full" style="background-color: ${user.avatar_color}">
            ${user.avatar_url ? 
              `<img src="${user.avatar_url}" class="w-6 h-6 rounded-full" />` :
              `<span class="flex items-center justify-center h-full text-white font-bold">${user.name[0]}</span>`
            }
          </div>
          <span class="text-white">${user.name}</span>
        </div>
      `;
    }).join('');
  },

  showTypingIndicator(this: any, payload: any) {
    // Show temporary typing indicator
    console.log(`⌨️  ${payload.name} is typing...`);
  },

  autosave(this: any) {
    const html = this.quill.root.innerHTML;
    const delta = this.quill.getContents();
    
    this.pushEvent('editor-autosave', {
      html: html,
      delta: JSON.stringify(delta)
    });
  },

  updated(this: any) {
    // Handle LiveView updates
  },

  destroyed(this: any) {
    if (this.channel) {
      this.channel.leave();
    }
    if (this.socket) {
      this.socket.disconnect();
    }
    if (this.quill) {
      this.quill = null;
    }
    if (this.ydoc) {
      this.ydoc.destroy();
    }
  }
};

export default CollaborativeQuillHook;
