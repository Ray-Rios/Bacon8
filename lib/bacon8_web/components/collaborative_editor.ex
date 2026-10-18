defmodule Bacon8Web.Components.CollaborativeEditor do
  @moduledoc """
  Real-time collaborative editor component using Y.js and Quill.
  
  Multiple users can edit the same document simultaneously with:
  - Live cursor positions
  - Conflict-free merging via CRDT
  - User presence indicators
  - Automatic sync
  
  ## Usage
  
      <.collaborative_editor
        id="blog-content"
        document_id={@blog_post.id}
        value={@content}
        current_user={@current_user}
        placeholder="Start writing your blog post..."
      />
  """
  use Phoenix.Component

  @doc """
  Renders a collaborative Quill.js editor.
  
  ## Attributes
  
  * `:id` (required) - Unique identifier for the editor instance
  * `:document_id` (required) - Unique document identifier for syncing
  * `:current_user` (required) - Current user struct
  * `:value` - Initial content (can be HTML string or Quill Delta JSON)
  * `:field` - Phoenix.HTML.Form field (alternative to value)
  * `:placeholder` - Placeholder text
  * `:autosave_delay` - Delay in milliseconds before autosave (default: 30000)
  * `:readonly` - Whether editor is read-only (default: false)
  * `:class` - Additional CSS classes
  """
  attr :id, :string, required: true
  attr :document_id, :string, required: true
  attr :current_user, :map, required: true
  attr :value, :string, default: ""
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :placeholder, :string, default: "Start writing..."
  attr :autosave_delay, :integer, default: 30000
  attr :readonly, :boolean, default: false
  attr :class, :string, default: ""

  def collaborative_editor(assigns) do
    # Generate auth token for the socket connection
    token = Bacon8Web.AuthToken.generate(assigns.current_user)
    assigns = assign(assigns, :user_token, token)

    # If field is provided, use it; otherwise use value
    assigns = 
      if assigns.field do
        assign(assigns, :value, Phoenix.HTML.Form.input_value(assigns.field.form, assigns.field.field))
      else
        assigns
      end

    ~H"""
    <div class={"collaborative-editor-wrapper #{@class}"}>
      <!-- Presence indicators - who's editing -->
      <div class="flex items-center justify-between mb-4 p-3 bg-gray-800 rounded-lg border border-gray-700">
        <div class="flex items-center space-x-2 text-sm text-gray-300">
          <svg class="w-5 h-5 text-green-400" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd" />
          </svg>
          <span>Collaborative Editing Enabled</span>
        </div>
        <div id={"#{@id}-presence"} class="flex items-center space-x-2">
          <!-- User avatars will be injected here by JavaScript -->
        </div>
      </div>

      <!-- Hidden input to store content for form submission -->
      <%= if @field do %>
        <input 
          type="hidden" 
          id={"#{@id}-input"}
          name={Phoenix.HTML.Form.input_name(@field.form, @field.field)}
          value={@value}
        />
      <% else %>
        <input 
          type="hidden" 
          id={"#{@id}-input"}
          value={@value}
        />
      <% end %>
      
      <!-- Quill editor container with Y.js -->
      <div 
        id={@id}
        phx-hook="CollaborativeQuill"
        phx-update="ignore"
        data-document-id={@document_id}
        data-user-id={@current_user.id}
        data-user-token={@user_token}
        data-user-name={@current_user.name || @current_user.email}
        data-user-color={@current_user.avatar_color || "#3B82F6"}
        data-placeholder={@placeholder}
        data-autosave-delay={@autosave_delay}
        data-readonly={to_string(@readonly)}
        class="quill-editor bg-white rounded-lg border border-gray-300 min-h-[400px]"
      >
        <!-- Quill will inject its toolbar and editor here -->
      </div>
      
      <!-- Status indicators -->
      <div class="flex items-center justify-between mt-4">
        <!-- Sync status -->
        <div class="flex items-center space-x-2">
          <div id={"#{@id}-sync-status"} class="flex items-center space-x-1 text-sm">
            <div class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
            <span class="text-gray-400">Synced</span>
          </div>
        </div>
        
        <!-- Autosave status -->
        <div class="text-sm text-gray-500">
          <div id={"#{@id}-loading"} class="hidden">
            <span class="inline-flex items-center">
              <svg class="animate-spin -ml-1 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Saving...
            </span>
          </div>
          <div id={"#{@id}-saved"} class="hidden text-green-600">
            ✓ Saved
          </div>
        </div>
      </div>
    </div>
    
    <style>
      /* Collaborative editor styling */
      .collaborative-editor-wrapper .ql-container {
        font-size: 16px;
        min-height: 300px;
      }
      
      .collaborative-editor-wrapper .ql-editor {
        min-height: 300px;
        max-height: 600px;
        overflow-y: auto;
      }
      
      .collaborative-editor-wrapper .ql-editor.ql-blank::before {
        color: #9ca3af;
        font-style: normal;
      }
      
      /* Remote cursor styling */
      .collaborative-editor-wrapper .ql-cursor {
        position: absolute;
        pointer-events: none;
      }
      
      .collaborative-editor-wrapper .ql-cursor-caret {
        border-left: 2px solid;
        height: 1em;
        position: relative;
      }
      
      .collaborative-editor-wrapper .ql-cursor-flag {
        position: absolute;
        top: -1.5em;
        left: -2px;
        padding: 2px 6px;
        border-radius: 4px;
        font-size: 12px;
        white-space: nowrap;
        color: white;
      }
      
      .collaborative-editor-wrapper .ql-cursor-selection {
        background-color: currentColor;
        opacity: 0.3;
      }
      
      /* Dark mode adjustments */
      .dark .collaborative-editor-wrapper .quill-editor {
        background-color: #1f2937;
        border-color: #374151;
      }
      
      .dark .collaborative-editor-wrapper .ql-toolbar {
        background-color: #111827;
        border-color: #374151;
      }
      
      .dark .collaborative-editor-wrapper .ql-editor {
        color: #f3f4f6;
      }
      
      .dark .collaborative-editor-wrapper .ql-editor.ql-blank::before {
        color: #6b7280;
      }
    </style>
    """
  end
end
