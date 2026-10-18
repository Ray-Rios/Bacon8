defmodule Bacon8Web.Components.RichEditor do
  @moduledoc """
  Quill.js WYSIWYG rich text editor component for LiveView.
  
  Features:
  - Rich text formatting (bold, italic, headers, lists, etc.)
  - Image upload support
  - Auto-save functionality
  - Collaborative editing ready (with Y.js integration later)
  
  ## Usage
  
      <.rich_editor
        id="blog-content"
        value={@content}
        placeholder="Start writing your blog post..."
        on_change="content-changed"
        autosave_delay={30000}
      />
  """
  use Phoenix.Component

  @doc """
  Renders a Quill.js rich text editor.
  
  ## Attributes
  
  * `:id` (required) - Unique identifier for the editor instance
  * `:value` - Initial content (can be HTML string or Quill Delta JSON)
  * `:content` - Alias for value (for convenience)
  * `:field` - Phoenix.HTML.Form field (alternative to value)
  * `:placeholder` - Placeholder text
  * `:on_change` - Event name to fire when content changes
  * `:on_autosave` - Event name to fire for autosave
  * `:autosave_delay` - Delay in milliseconds before autosave (default: 30000)
  * `:readonly` - Whether editor is read-only (default: false)
  * `:min_height` - Minimum height of the editor (default: "400px")
  * `:class` - Additional CSS classes
  """
  attr :id, :string, required: true
  attr :value, :string, default: ""
  attr :content, :string, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :placeholder, :string, default: "Start writing..."
  attr :on_change, :string, default: nil
  attr :on_autosave, :string, default: nil
  attr :autosave_delay, :integer, default: 30000
  attr :readonly, :boolean, default: false
  attr :min_height, :string, default: "400px"
  attr :class, :string, default: ""

  def rich_editor(assigns) do
    # Support both :value and :content attribute names
    assigns = 
      if assigns.content do
        assign(assigns, :value, assigns.content)
      else
        assigns
      end
    
    # If field is provided, use it; otherwise use value
    assigns = 
      if assigns.field do
        assign(assigns, :value, Phoenix.HTML.Form.input_value(assigns.field.form, assigns.field.field))
      else
        assigns
      end

    ~H"""
    <div class={"rich-editor-wrapper #{@class}"}>
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
      
      <!-- Quill editor container -->
      <div 
        id={@id}
        phx-hook="QuillEditor"
        phx-update="ignore"
        data-placeholder={@placeholder}
        data-autosave-delay={@autosave_delay}
        data-readonly={to_string(@readonly)}
        data-initial-content={@value}
        style={"min-height: #{@min_height};"}
        class="quill-editor bg-gray-800 text-white rounded-lg border border-gray-700"
      >
        <!-- Quill will inject its toolbar and editor here -->
      </div>
      
      <!-- Loading indicator -->
      <div id={"#{@id}-loading"} class="hidden mt-2 text-sm text-gray-500">
        <span class="inline-flex items-center">
          <svg class="animate-spin -ml-1 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          Saving...
        </span>
      </div>
      
      <!-- Success indicator -->
      <div id={"#{@id}-saved"} class="hidden mt-2 text-sm text-green-600">
        ✓ Saved
      </div>
    </div>
    
    <style>
      /* Quill editor styling */
      .rich-editor-wrapper .ql-container {
        font-size: 16px;
        min-height: 300px;
      }
      
      .rich-editor-wrapper .ql-editor {
        min-height: 300px;
        max-height: 600px;
        overflow-y: auto;
      }
      
      .rich-editor-wrapper .ql-editor.ql-blank::before {
        color: #9ca3af;
        font-style: normal;
      }
      
      /* Dark mode adjustments if needed */
      .dark .rich-editor-wrapper .quill-editor {
        background-color: #1f2937;
        border-color: #374151;
      }
      
      .dark .rich-editor-wrapper .ql-toolbar {
        background-color: #111827;
        border-color: #374151;
      }
      
      .dark .rich-editor-wrapper .ql-editor {
        color: #f3f4f6;
      }
      
      .dark .rich-editor-wrapper .ql-editor.ql-blank::before {
        color: #6b7280;
      }
    </style>
    """
  end
  
  @doc """
  Alias for rich_editor - renders a Quill.js WYSIWYG editor.
  """
  attr :id, :string, required: true
  attr :value, :string, default: ""
  attr :content, :string, default: nil
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :placeholder, :string, default: "Start writing..."
  attr :on_change, :string, default: nil
  attr :on_autosave, :string, default: nil
  attr :autosave_delay, :integer, default: 30000
  attr :readonly, :boolean, default: false
  attr :min_height, :string, default: "400px"
  attr :class, :string, default: ""
  
  def quill_editor(assigns) do
    rich_editor(assigns)
  end
end
