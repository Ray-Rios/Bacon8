defmodule Bacon8Web.Components.ContentExtras do
  @moduledoc """
  Two small pieces the page and post editors share: the time a draft goes live by itself
  (`Bacon8.Content.Publisher`), and the list of earlier versions with a Restore button
  (`Bacon8.Content.Revisions`).
  """
  use Phoenix.Component

  attr :name, :string, required: true, doc: "the field's name, e.g. \"post[scheduled_at]\""
  attr :value, :any, default: nil, doc: "a DateTime/NaiveDateTime or nil"

  def schedule_input(assigns) do
    ~H"""
    <div class="glass-dark p-6 rounded-lg space-y-2">
      <h3 class="text-lg font-semibold text-white">Schedule</h3>
      <label for="scheduled-at" class="block text-sm text-gray-300">Publish automatically at (UTC)</label>
      <input id="scheduled-at" type="datetime-local" name={@name} value={local_value(@value)} class="px-3 py-2 rounded bg-gray-700 text-white border border-gray-600" />
      <p class="text-xs text-gray-400">
        Leave empty to publish by hand. Use <strong>Save</strong> (not Publish) to keep it a draft until then;
        pressing Publish publishes at once and clears the time.
      </p>
    </div>
    """
  end

  attr :revisions, :list, required: true

  def history(assigns) do
    ~H"""
    <div :if={@revisions != []} id="revision-history" class="glass-dark p-6 rounded-lg space-y-2">
      <h3 class="text-lg font-semibold text-white">Earlier versions</h3>
      <p class="text-xs text-gray-400">Kept when the words change, at most one every five minutes. Restoring keeps the current version first.</p>
      <ul class="divide-y divide-gray-700">
        <li :for={rev <- @revisions} id={"revision-#{rev.id}"} class="py-2 flex items-center justify-between gap-4">
          <span class="text-sm text-gray-200">
            <%= Calendar.strftime(rev.inserted_at, "%b %d, %Y %H:%M") %> UTC
            <span class="text-gray-400">· <%= rev.title %></span>
          </span>
          <button type="button" phx-click="restore_revision" phx-value-id={rev.id}
            data-confirm="Put this version back? The current one is kept in this list."
            class="px-3 py-1 rounded bg-gray-600 hover:bg-gray-500 text-white text-sm">Restore</button>
        </li>
      </ul>
    </div>
    """
  end

  # <input type="datetime-local"> wants "2026-10-27T09:30"
  defp local_value(nil), do: nil
  defp local_value(%{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  defp local_value(other) when is_binary(other), do: other
end
