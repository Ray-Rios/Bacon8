defmodule FeedbackWeb.Routes do
  @moduledoc """
  Suggestions & Bugs' routes. Pages at /feedback (members only; the LiveViews send guests
  away), screenshots at /feedback/shots/:id, the runner's API at /api/feedback/agent/... (its
  own bearer token, checked by `FeedbackWeb.AgentController`), and the runner's admin page at
  /admin/feedback/agent.
  """
  use Bacon8.Plugin.Routes

  site do
    live("/", FeedbackLive, :index)
    live("/new", FeedbackLive, :new)
    live("/:id", FeedbackItemLive, :show)
  end

  # Not :browser, whose `accepts ["html"]` would refuse some <img> requests.
  site pipe_through: :drive_files do
    get("/shots/:id", ShotController, :show)
  end

  # Claude's runner. `:api` has no authentication of its own (BACON8.md invariant 16): every
  # action checks the runner's token first.
  site_api do
    get("/agent/next", AgentController, :next)
    get("/agent/items/:id", AgentController, :show)
    post("/agent/items/:id/report", AgentController, :report)
    get("/agent/shots/:id", AgentController, :shot)
  end

  admin do
    live("/agent", Admin.AgentLive, :index)
  end
end
