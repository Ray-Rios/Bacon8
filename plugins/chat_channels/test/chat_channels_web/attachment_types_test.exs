defmodule ChatChannelsWeb.AttachmentTypesTest do
  use ExUnit.Case, async: true

  alias ChatChannelsWeb.ChatLive

  # LiveView raises in allow_upload/3 for an accept entry whose extension the MIME library does not
  # know, which fails the whole /chat page with a 500 (2026-10-29: .mkv, .yaml and others did).
  test "every accepted attachment extension has a known MIME type" do
    unknown =
      for "." <> ext = e <- ChatLive.attachment_types(), MIME.type(ext) == "application/octet-stream", do: e

    assert unknown == []
  end

  test "no active content or program types are accepted" do
    refute Enum.any?(ChatLive.attachment_types(), &Bacon8.SafePath.active_content?("x" <> &1))

    for ext <- ~w(.exe .msi .bat .cmd .ps1 .sh .jar .apk .dmg) do
      refute ext in ChatLive.attachment_types()
    end
  end
end
