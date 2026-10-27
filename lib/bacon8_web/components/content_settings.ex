defmodule Bacon8Web.Components.ContentSettings do
  @moduledoc """
  What the in-place editors of a page or post show besides the block editor: the toolbar (Edit,
  Save, Cancel) and the settings panel (title, address, summary, tags or template, featured image,
  sharing, schedule, publish, earlier versions, delete). Handlers: `Bacon8Web.InPlaceEditing`.
  """
  use Phoenix.Component

  alias Bacon8Web.Components.ContentExtras

  @platforms ~w(twitter facebook linkedin reddit email)

  attr :kind, :atom, required: true
  attr :record, :map, required: true
  attr :editing, :boolean, required: true
  attr :saving, :boolean, default: false
  attr :last_saved, :any, default: nil
  attr :dirty, :boolean, default: false

  def toolbar(assigns) do
    ~H"""
    <div class="flex items-center gap-2 ml-4" id="edit-toolbar">
      <%= if @editing do %>
        <span :if={@saving} class="text-yellow-400 text-sm animate-pulse">Saving...</span>
        <span :if={@last_saved && !@saving && !@dirty} class="text-green-400 text-sm">Saved <%= Calendar.strftime(@last_saved, "%H:%M:%S") %></span>
        <span :if={@dirty} id="unsaved-note" class="text-amber-300 text-sm">
          <%= if @record.is_published, do: "Not saved yet. The live page changes when you press Save.", else: "Saving as you type..." %>
        </span>
        <button type="button" phx-click="save_content" class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg text-sm">Save &amp; Exit</button>
        <button type="button" phx-click="cancel_edit" class="bg-gray-600 hover:bg-gray-700 text-white px-4 py-2 rounded-lg text-sm">Cancel</button>
      <% else %>
        <button type="button" phx-click="toggle_edit" class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm">
          Edit <%= if @kind == :page, do: "Page", else: "Post" %>
        </button>
      <% end %>
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :record, :map, required: true
  attr :form, :any, required: true
  attr :revisions, :list, default: []
  attr :uploads, :any, required: true
  attr :featured_library, :any, default: nil

  def settings(assigns) do
    assigns = assign(assigns, platforms: @platforms)

    ~H"""
    <section id="content-settings" class="glass-dark rounded-lg p-4 mb-6 border border-gray-700 space-y-4">
      <div class="flex items-center justify-between gap-4 flex-wrap">
        <h2 class="text-lg font-semibold text-white">
          <%= if @kind == :page, do: "Page", else: "Post" %> settings
          <span class={["ml-2 px-2 py-1 text-xs rounded-full", if(@record.is_published, do: "bg-green-600 text-white", else: "bg-gray-600 text-gray-200")]}>
            <%= if @record.is_published, do: "Published", else: "Draft" %>
          </span>
          <span :if={@record.scheduled_at && !@record.is_published} class="ml-2 px-2 py-1 text-xs rounded-full bg-blue-600 text-white">
            Goes live <%= Calendar.strftime(@record.scheduled_at, "%b %d, %Y %H:%M") %> UTC
          </span>
        </h2>
        <div class="flex gap-2">
          <button :if={!@record.is_published} type="button" id="publish-now" phx-click="set_published" phx-value-to="true" class="px-4 py-2 rounded-lg bg-green-600 hover:bg-green-700 text-white text-sm">Publish now</button>
          <button :if={@record.is_published} type="button" id="unpublish" phx-click="set_published" phx-value-to="false" class="px-4 py-2 rounded-lg bg-orange-600 hover:bg-orange-700 text-white text-sm">Unpublish</button>
          <button type="button" id="delete-record" phx-click="delete_record" data-confirm="Delete this for good? Its pictures and earlier versions go with it." class="px-4 py-2 rounded-lg bg-red-700 hover:bg-red-800 text-white text-sm">Delete</button>
        </div>
      </div>

      <.form for={@form} id="settings-form" phx-submit="save_settings" phx-change="settings_change" autocomplete="off" class="space-y-4">
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.field label="Title" name="settings[title]" value={@form[:title].value} id="settings-title" />
          <.field label="Address (URL)" name="settings[slug]" value={@form[:slug].value} id="settings-slug" hint={"#{if @kind == :page, do: "/pages/", else: "/blog/"}address"} />
        </div>
        <div>
          <label for="settings-excerpt" class="block text-sm text-gray-300 mb-1">Summary</label>
          <textarea id="settings-excerpt" name="settings[excerpt]" rows="2" maxlength="500" class="w-full px-3 py-2 rounded bg-gray-700 text-white border border-gray-600"><%= @form[:excerpt].value %></textarea>
        </div>
        <.field label="Description for search engines (160 characters)" name="settings[meta_description]" value={@form[:meta_description].value} id="settings-meta" maxlength="160" />

        <div :if={@kind == :page} class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label for="settings-template" class="block text-sm text-gray-300 mb-1">Template</label>
            <select id="settings-template" name="settings[template_type]" class="w-full px-3 py-2 rounded bg-gray-700 text-white border border-gray-600">
              <option :for={{label, value} <- [{"Default", "default"}, {"Landing page", "landing"}, {"Full width", "full-width"}, {"With sidebar", "sidebar"}, {"Custom", "custom"}]} value={value} selected={@record.template_type == value}><%= label %></option>
            </select>
          </div>
          <.field label="Category" name="settings[category]" value={@form[:category].value} id="settings-category" />
        </div>

        <div :if={@kind == :post}>
          <.field label="Tags (separated by commas)" name="settings[tags]" value={Enum.join(@record.tags || [], ", ")} id="settings-tags" />
        </div>

        <div id="featured-image">
          <label class="block text-sm text-gray-300 mb-1">Featured image</label>
          <div class="flex items-start gap-4 flex-wrap">
            <img :if={@record.featured_image} src={@record.featured_image} alt="Current featured image" class="max-w-[10rem] rounded border border-gray-600" />
            <div class="space-y-2">
              <.live_file_input upload={@uploads.featured_image} class="text-sm text-gray-300" />
              <div class="flex gap-2">
                <button type="button" id="open-featured-library" phx-click="open_featured_library" class="px-3 py-1 rounded bg-gray-600 hover:bg-gray-500 text-white text-sm">Choose from the image library</button>
                <button :if={@record.featured_image} type="button" phx-click="remove_featured" class="px-3 py-1 rounded bg-gray-700 hover:bg-gray-600 text-white text-sm">Remove</button>
              </div>
              <p :for={entry <- @uploads.featured_image.entries} class="text-xs text-gray-300"><%= entry.client_name %> will be added when you save.</p>
            </div>
          </div>
        </div>

        <fieldset class="space-y-2">
          <legend class="text-sm text-gray-300">Share buttons</legend>
          <input type="hidden" name="settings[show_share_buttons]" value="false" />
          <label class="flex items-center gap-2 text-sm text-gray-200">
            <input type="checkbox" name="settings[show_share_buttons]" value="true" checked={@record.show_share_buttons != false} /> Show share buttons
          </label>
          <input type="hidden" name="settings[share_buttons_colored]" value="false" />
          <label class="flex items-center gap-2 text-sm text-gray-200">
            <input type="checkbox" name="settings[share_buttons_colored]" value="true" checked={@record.share_buttons_colored == true} /> In colour
          </label>
          <input type="hidden" name="settings[share_platforms][]" value="" />
          <div class="flex gap-4 flex-wrap">
            <label :for={platform <- @platforms} class="flex items-center gap-1 text-sm text-gray-200">
              <input type="checkbox" name="settings[share_platforms][]" value={platform} checked={platform in (@record.share_platforms || [])} /> <%= platform %>
            </label>
          </div>
        </fieldset>

        <ContentExtras.schedule_input :if={!@record.is_published} name="settings[scheduled_at]" value={@record.scheduled_at} />

        <button type="submit" class="px-5 py-2 rounded-lg bg-blue-600 hover:bg-blue-700 text-white font-medium">Save settings</button>
      </.form>

      <ContentExtras.history revisions={@revisions} />

      <div :if={@featured_library} id="featured-library" class="fixed inset-0 z-[10000] bg-black/70 flex items-center justify-center p-4" phx-window-keydown="close_featured_library" phx-key="Escape">
        <div class="w-full max-w-4xl max-h-[90vh] overflow-y-auto rounded-xl bg-gray-900 border border-gray-700 p-4 space-y-3">
          <div class="flex items-center gap-3">
            <strong class="text-white">Choose a picture</strong>
            <input type="search" name="query" value={@featured_library.query} placeholder="Search by file name..." phx-change="featured_library_search" phx-debounce="250" class="flex-1 px-3 py-1 rounded bg-gray-800 text-white border border-gray-600" />
            <button type="button" phx-click="close_featured_library" class="px-3 py-1 rounded bg-gray-700 text-white">Close</button>
          </div>
          <p :if={@featured_library.images == []} class="text-gray-400 text-center py-8">No pictures yet. Add one to a page or post and it will be here.</p>
          <div class="grid grid-cols-[repeat(auto-fill,minmax(120px,1fr))] gap-2">
            <button :for={image <- @featured_library.images} type="button" phx-click="pick_featured" phx-value-url={image.url} title={image.filename} class="aspect-square overflow-hidden rounded border-2 border-transparent hover:border-sky-400 bg-gray-800">
              <img src={image.url} alt={image.filename} loading="lazy" class="w-full h-full object-cover" />
            </button>
          </div>
          <button :if={@featured_library.more} type="button" phx-click="featured_library_more" class="mx-auto block px-4 py-1 rounded bg-gray-700 text-white">Show more</button>
        </div>
      </div>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :id, :string, required: true
  attr :hint, :string, default: nil
  attr :maxlength, :string, default: nil

  defp field(assigns) do
    ~H"""
    <div>
      <label for={@id} class="block text-sm text-gray-300 mb-1"><%= @label %></label>
      <input type="text" id={@id} name={@name} value={@value} maxlength={@maxlength} class="w-full px-3 py-2 rounded bg-gray-700 text-white border border-gray-600" />
      <p :if={@hint} class="text-xs text-gray-500 mt-1"><%= @hint %></p>
    </div>
    """
  end
end
