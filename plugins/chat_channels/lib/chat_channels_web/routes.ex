defmodule ChatChannelsWeb.Routes do
  @moduledoc """
  Chat Channels' routes. The page lives at /chat; the admin page for custom emojis
  at /admin/chat_channels/custom-emojis.
  """
  use Bacon8.Plugin.Routes

  site do
    live "/", ChatLive, :index
    live "/:channel_id", ChatLive, :channel
  end

  admin do
    live "/custom-emojis", Admin.CustomEmojisLive, :index
  end

  # The feature was the forum, at /forum, until it became Chat (2026-10-25). Bookmarks,
  # old messages and invites out there still point at it.
  fixed reason: "/forum was this page's address before it became /chat; drop once old links have faded",
        pipe_through: :browser do
    get "/forum", ForumRedirectController, :index
    get "/forum/:channel_id", ForumRedirectController, :channel
  end
end
