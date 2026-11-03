defmodule BaconWorldWeb.Admin.WorldFileController do
  @moduledoc """
  /admin/bacon_world/world/export/:number - a zone's heights for World Creator (2026-11-02):
  `?format=png` (16-bit greyscale) or `?format=raw` (16-bit big-endian), with the metres for 0 and
  65535 in the file name and in the `x-bacon-world-min` / `-max` headers. Admins only.
  """
  use Bacon8Web, :controller

  alias BaconWorld.WorldEditor

  def export(conn, %{"number" => number} = params) do
    # the admin scope's :browser pipeline doesn't load the user for controllers: read the session here
    conn = if Map.has_key?(conn.assigns, :current_user), do: conn, else: Bacon8Web.Auth.call(conn, [])
    user = conn.assigns[:current_user]

    with true <- (user && user.is_admin) || {:error, 403, "Admins only."},
         {n, ""} <- Integer.parse(number),
         zone when not is_nil(zone) <- WorldEditor.get(n) || {:error, 404, "No such zone."},
         {:ok, out} <- WorldEditor.export(zone, if(params["format"] == "raw", do: :raw, else: :png)) do
      conn
      |> put_resp_header("x-bacon-world-min", to_string(out.min))
      |> put_resp_header("x-bacon-world-max", to_string(out.max))
      |> send_download({:binary, out.bytes}, filename: out.filename, content_type: if(params["format"] == "raw", do: "application/octet-stream", else: "image/png"))
    else
      {:error, status, msg} -> conn |> put_status(status) |> text(msg)
      {:error, msg} -> conn |> put_status(422) |> text(msg)
      _ -> conn |> put_status(400) |> text("Bad zone number.")
    end
  end

  @doc "/admin/bacon_world/world/detail/:number.png - the zone's 2048 px picture for zooming (admins only)."
  def detail(conn, %{"number" => number}) do
    conn = if Map.has_key?(conn.assigns, :current_user), do: conn, else: Bacon8Web.Auth.call(conn, [])
    user = conn.assigns[:current_user]
    number = String.replace_suffix(number, ".png", "")

    with true <- (user && user.is_admin) || {:error, 403, "Admins only."},
         {n, ""} <- Integer.parse(number),
         zone when not is_nil(zone) <- WorldEditor.get(n) || {:error, 404, "No such zone."},
         {:ok, file} <- WorldEditor.detail_png(zone) do
      conn
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> put_resp_content_type("image/png")
      |> send_file(200, file)
    else
      {:error, status, msg} -> conn |> put_status(status) |> text(msg)
      {:error, msg} -> conn |> put_status(422) |> text(msg)
      _ -> conn |> put_status(400) |> text("Bad zone number.")
    end
  end
end
