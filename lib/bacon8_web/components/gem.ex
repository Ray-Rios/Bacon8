defmodule Bacon8Web.Components.Gem do
  @moduledoc """
  The Bacon8 Gem: the site's currency (Bacon Store's Gems) and the shop icon, a fiery gem
  rendered in Blender that turns and floats in 3D and reacts when hovered
  (`<b8-gem>`, `assets/js/fire_gem.ts`; pictures in `priv/static/images/gem/`).

      <.gem />                       text-sized
      <.gem size={96} />             96 px
      <.gems amount={1500} />        the gem and "1,500"

  Anywhere an icon string is shown (plugins' `nav_links`, `admin_nav`, `profile_tabs`),
  the icon `"gem"` means this gem: `<.icon icon={item.icon} />`.
  """
  use Phoenix.Component

  @doc "The gem. `still`: no idle turning or floating; `calm`: no hover reactions."
  attr :size, :integer, default: nil
  attr :still, :boolean, default: false
  attr :calm, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global

  def gem(assigns) do
    ~H"""
    <b8-gem
      size={@size}
      still={@still}
      calm={@calm}
      class={@class}
      style={@size && "--gem-size:#{@size}px"}
      {@rest}
    ></b8-gem>
    """
  end

  @doc "An amount of Gems: the gem, then the number (1,500)."
  attr :amount, :integer, required: true
  attr :size, :integer, default: nil
  attr :class, :any, default: nil

  def gems(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1 whitespace-nowrap", @class]} data-gem-host>
      <.gem size={@size} /><span>{format(@amount)}</span>
    </span>
    """
  end

  @doc ~S'An icon string, or the gem for `"gem"`.'
  attr :icon, :string, required: true
  attr :size, :integer, default: 18

  def icon(%{icon: "gem"} = assigns), do: ~H"<.gem size={@size} />"
  def icon(assigns), do: ~H"{@icon}"

  @doc "1500 -> \"1,500\"."
  def format(n) when is_integer(n) do
    n
    |> abs()
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
    |> then(&if(n < 0, do: "-" <> &1, else: &1))
  end

  def format(nil), do: "0"
end
