defmodule Bacon8Web.Api.ProjectController do
  use Bacon8Web, :controller
  alias Bacon8.Scheduler
  plug Bacon8Web.Plugs.ApiKeyOrAuth when action in [:calendar]

  def calendar(conn, _params) do
    projects = Scheduler.list_projects_for_calendar()
    json(conn, %{projects: projects})
  end
end
