defmodule FeedbackWeb.ShotController do
  @moduledoc """
  `GET /feedback/shots/:id`: a screenshot, for members (`Feedback.member?/1`). Refusals are
  404. Served with `nosniff` and a sandboxing CSP: the bytes were checked to be an image when
  they came in, and are sent as the type found then.
  """
  use Bacon8Web, :controller

  alias Bacon8.Storage

  def show(conn, %{"id" => id}) do
    with %Feedback.Shot{} = shot <- Feedback.get_shot(id, conn.assigns[:current_user]),
         {:ok, path} <- Storage.local_path(shot.sha256) do
      conn
      |> put_resp_content_type(shot.content_type, nil)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> send_file(200, path)
    else
      _ -> conn |> put_status(404) |> text("Not found")
    end
  end
end
