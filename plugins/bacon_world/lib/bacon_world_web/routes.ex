defmodule BaconWorldWeb.Routes do
  @moduledoc "Bacon World's routes. Pages mount at /games/bacon_world (BACON8.md §9)."
  use Bacon8.Plugin.Routes

  browser do
    live "/", PlayLive, :index
  end

  # /admin/bacon_world/...
  admin do
    live "/", Admin.HomeLive, :index
    live "/skills", Admin.SkillTreeLive, :index
  end
end
