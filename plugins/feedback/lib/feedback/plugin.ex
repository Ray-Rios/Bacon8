defmodule Feedback.Plugin do
  @moduledoc """
  Suggestions & Bugs: members suggest things and report bugs about the site and its games (with
  screenshots) and vote on them; admins approve them and submit them to Claude, whose runner on
  the owner's PC fixes, tests, commits and (when allowed) deploys them, reporting back here. A
  *site* plugin mounted at `/feedback`, opened from the start menu; not for guests. See
  `Feedback` and README.md.
  """
  use Bacon8.Plugin,
    slug: "feedback",
    name: "Suggestions & Bugs",
    version: "1.0.0",
    description:
      "Members' suggestions and bug reports, votes, and a queue that hands approved ones to Claude."

  @impl true
  def mount, do: "feedback"

  @impl true
  def routes, do: FeedbackWeb.Routes

  # The start menu's icon. Guests (and banned or inactive accounts) don't get it.
  @impl true
  def desktop_apps(user) do
    if Feedback.member?(user),
      do: [%{label: "Suggestions & Bugs", path: "/feedback", icon: "💡"}],
      else: []
  end

  @impl true
  def admin_nav, do: [%{label: "Claude runner", path: "/admin/feedback/agent", icon: "🤖"}]

  @impl true
  def admin_dashboard do
    counts = Feedback.counts()

    %{
      stats: [
        %{label: "Suggestions to review", value: Map.get(counts, "open", 0), icon: "💡"},
        %{label: "Waiting for Deploy", value: Map.get(counts, "ready", 0), icon: "🚀"}
      ]
    }
  end

  @impl true
  def storage_refs, do: Feedback.storage_refs()

  @impl true
  def hub_event({:user_content_removed, user_id}), do: Feedback.remove_user_content(user_id)
  def hub_event(_event), do: :ok
end
