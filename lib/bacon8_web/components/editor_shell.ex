defmodule Bacon8Web.Components.EditorShell do
  @moduledoc """
  The screen a page or post is edited on (2026-10-28), shown by `PageLive` and `BlogLive` while
  `@editing`: full screen, phone first. A slim top bar (close, how saving is going, Undo, Redo,
  phone preview, the settings gear, Done and Publish), then the page itself: the title typed in
  place and the page builder (`BlockEditor.block_editor/1`, `assets/js/page_builder/`). The
  settings (`ContentSettings.settings/1`) slide in from the gear: from the right on a desktop,
  up from the bottom on a phone.

  Every button sends the events `Bacon8Web.InPlaceEditing` already handles; Undo, Redo and the
  preview are the builder's own (`pb:undo`, `pb:redo`, `pb:preview` window events).
  """
  use Phoenix.Component

  alias Bacon8Web.Components.{BlockEditor, ContentSettings}
  alias Phoenix.LiveView.JS

  attr :kind, :atom, required: true
  attr :record, :map, required: true
  attr :editor_id, :string, required: true
  attr :form, :any, required: true
  attr :revisions, :list, default: []
  attr :uploads, :any, required: true
  attr :featured_library, :any, default: nil
  attr :saving, :boolean, default: false
  attr :last_saved, :any, default: nil
  attr :dirty, :boolean, default: false
  attr :pending_title, :string, default: nil

  def shell(assigns) do
    assigns =
      assign(assigns,
        noun: if(assigns.kind == :page, do: "page", else: "post"),
        path: if(assigns.kind == :page, do: "/pages/", else: "/blog/") <> (assigns.record.slug || ""),
        title_value: title_value(assigns.pending_title, assigns.record.title)
      )

    ~H"""
    <div id="pb-shell" class="pb-shell" data-kind={@noun}>
      <header class="pb-bar">
        <button type="button" phx-click="cancel_edit" class="pb-bar-btn" aria-label="Close the editor" title={if @record.is_published, do: "Close (unsaved changes are thrown away)", else: "Close (your draft is saved)"}>
          <svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18" /></svg>
        </button>
        <div class="pb-bar-status" id="pb-status" aria-live="polite">
          <span class={["pb-dot", if(@record.is_published, do: "is-live", else: "is-draft")]}></span>
          <span class="pb-bar-state"><%= if @record.is_published, do: "Live", else: "Draft" %></span>
          <span class="pb-bar-sub"><%= status(assigns) %></span>
        </div>
        <div class="pb-bar-tools">
          <button type="button" id="pb-undo" phx-click={JS.dispatch("pb:undo")} class="pb-bar-btn" aria-label="Undo" title="Undo (Ctrl+Z)">
            <svg viewBox="0 0 24 24"><path d="M9 14L4 9l5-5" /><path d="M4 9h11a5 5 0 0 1 0 10h-3" /></svg>
          </button>
          <button type="button" id="pb-redo" phx-click={JS.dispatch("pb:redo")} class="pb-bar-btn" aria-label="Redo" title="Redo (Ctrl+Shift+Z)">
            <svg viewBox="0 0 24 24"><path d="M15 14l5-5-5-5" /><path d="M20 9H9a5 5 0 0 0 0 10h3" /></svg>
          </button>
          <button type="button" id="pb-preview" phx-click={JS.dispatch("pb:preview")} class="pb-bar-btn pb-wide-only" aria-label="See it on a phone" title="See it at phone width">
            <svg viewBox="0 0 24 24"><rect x="7" y="2" width="10" height="20" rx="2" /><path d="M11 18h2" /></svg>
          </button>
          <button type="button" id="pb-settings-btn" phx-click={toggle_settings()} class="pb-bar-btn" aria-label={"#{String.capitalize(@noun)} settings"} title="Settings: address, summary, picture, schedule">
            <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" /></svg>
          </button>
          <button type="button" phx-click="save_content" data-pb-flush class={["pb-bar-text", @record.is_published && "is-primary"]}>
            <%= if @record.is_published, do: "Save", else: "Done" %>
          </button>
          <button :if={!@record.is_published} type="button" id="pb-publish" phx-click="set_published" phx-value-to="true" class="pb-bar-text is-primary">Publish</button>
        </div>
      </header>

      <main class="pb-shell-main">
        <div class="pb-page">
          <textarea
            id="pb-title"
            name="title"
            rows="1"
            phx-hook="AutoGrow"
            phx-blur="update_title"
            phx-keyup="update_title"
            phx-debounce="700"
            placeholder={"Give your #{@noun} a title"}
            aria-label="Title"
            class="pb-title"
          ><%= @title_value %></textarea>
          <button type="button" phx-click={toggle_settings()} class="pb-meta">
            <span><%= @path %></span>
            <span :if={@record.scheduled_at && !@record.is_published}>· goes live <%= Calendar.strftime(@record.scheduled_at, "%b %d, %H:%M") %> UTC</span>
            <span class="pb-meta-edit">Edit settings</span>
          </button>
          <BlockEditor.block_editor
            id={@editor_id}
            content={@record.content}
            kind={@noun}
            placeholder={"Write your #{@noun}..."}
            min_height="60vh"
            autosave_delay={4000}
          />
        </div>
      </main>

      <div id="pb-settings-backdrop" class="pb-drawer-backdrop" phx-click={toggle_settings()}></div>
      <aside id="pb-settings" class="pb-drawer" aria-label={"#{String.capitalize(@noun)} settings"}>
        <div class="pb-drawer-head">
          <strong><%= String.capitalize(@noun) %> settings</strong>
          <button type="button" phx-click={toggle_settings()} class="pb-bar-btn" aria-label="Close settings">
            <svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18" /></svg>
          </button>
        </div>
        <div class="pb-drawer-body">
          <ContentSettings.settings kind={@kind} record={@record} form={@form} revisions={@revisions} uploads={@uploads} featured_library={@featured_library} />
        </div>
      </aside>
    </div>
    """
  end

  defp toggle_settings do
    JS.toggle_class("is-open", to: "#pb-settings")
    |> JS.toggle_class("is-open", to: "#pb-settings-backdrop")
  end

  # A just-started draft is called "Untitled": show the placeholder instead.
  defp title_value(pending, _title) when is_binary(pending), do: pending
  defp title_value(_, "Untitled"), do: ""
  defp title_value(_, title), do: title

  defp status(assigns) do
    cond do
      assigns.saving -> "Saving…"
      assigns.dirty and assigns.record.is_published -> "Not saved yet: Save puts it live"
      assigns.dirty -> "Saving as you type…"
      assigns.last_saved -> "Saved " <> Calendar.strftime(assigns.last_saved, "%H:%M")
      assigns.record.is_published -> "Changes wait until you press Save"
      true -> "Saved as you type"
    end
  end
end
