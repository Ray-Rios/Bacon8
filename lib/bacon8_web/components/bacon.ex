defmodule Bacon8Web.Components.Bacon do
  @moduledoc """
  Two strips of bacon: the Bacon8 site icon, on the desktop's Start button and the navbar's
  Games link (the favicon and app icons are the same picture, from `brand/bacon8-mark.png`).
  Rendered in Blender, it sizzles gently and reacts when hovered, a different way each time
  (`<b8-bacon>`, `assets/js/sizzle_bacon.ts`; pictures in `priv/static/images/bacon/`).

      <.bacon />                     text-sized
      <.bacon size={28} />           28 px

  Anywhere an icon string is shown (plugins' `nav_links`, `admin_nav`, `profile_tabs`),
  the icon `"bacon"` means this: `Bacon8Web.Components.Gem.icon/1`.
  """
  use Phoenix.Component

  @doc "The bacon. `still`: no idle sizzle or bob; `calm`: no hover reactions; `pinned`: sizzles, no bob."
  attr :size, :integer, default: nil
  attr :still, :boolean, default: false
  attr :calm, :boolean, default: false
  attr :pinned, :boolean, default: false, doc: "sizzles but doesn't bob"
  attr :class, :any, default: nil
  attr :rest, :global

  def bacon(assigns) do
    ~H"""
    <b8-bacon
      size={@size}
      still={@still}
      calm={@calm}
      pinned={@pinned}
      class={@class}
      style={@size && "--bacon-size:#{@size}px"}
      {@rest}
    ></b8-bacon>
    """
  end
end
