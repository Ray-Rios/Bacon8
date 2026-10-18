defmodule Bacon8Web.PageController do
  use Bacon8Web, :controller

  ## Index (normal Phoenix homepage)
  def index(conn, _params) do
    render(conn, :index)
  end
end
