defmodule Bacon8Web.Components.SocialShare do
  @moduledoc """
  Social media share buttons component for blog posts and pages.
  
  Provides configurable share buttons for popular platforms:
  - Twitter/X
  - Facebook
  - LinkedIn
  - Reddit
  - Email
  - Copy Link
  - Pinterest
  - WhatsApp
  - Telegram
  """
  use Phoenix.Component

  @doc """
  Renders social share buttons.

  ## Attributes
  - `url` - The full URL to share (required)
  - `title` - The title/text to share (required)
  - `description` - Optional description for some platforms
  - `image_url` - Optional image URL for Pinterest
  - `platforms` - List of platforms to show (defaults to all)
  - `show` - Whether to show the buttons (defaults to true)
  - `style` - Style variant: "horizontal", "vertical", "compact" (defaults to "horizontal")
  - `size` - Button size: "sm", "md", "lg" (defaults to "md")
  - `show_labels` - Whether to show text labels (defaults to false for compact view)

  ## Examples

      <.social_share
        url={@full_url}
        title={@post.title}
        platforms={@post.share_platforms}
        show={@post.show_share_buttons}
      />
  """
  attr :url, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :image_url, :string, default: nil
  attr :platforms, :list, default: ["twitter", "facebook", "linkedin", "reddit", "email", "copy"]
  attr :show, :boolean, default: true
  attr :style, :string, default: "horizontal", values: ["horizontal", "vertical", "compact"]
  attr :size, :string, default: "md", values: ["sm", "md", "lg"]
  attr :show_labels, :boolean, default: false
  attr :colored, :boolean, default: false
  attr :class, :string, default: ""

  def social_share(assigns) do
    ~H"""
    <div :if={@show && @platforms != []} class={["social-share-buttons", container_class(@style), @class]}>
      <span class="text-gray-400 text-sm mr-3 hidden sm:inline">Share:</span>
      
      <%= for platform <- @platforms do %>
        <%= render_button(assigns, platform, @colored) %>
      <% end %>
    </div>
    """
  end

  defp container_class("horizontal"), do: "flex flex-wrap items-center gap-2"
  defp container_class("vertical"), do: "flex flex-col gap-2"
  defp container_class("compact"), do: "flex flex-wrap items-center gap-1"

  defp button_size("sm"), do: "w-8 h-8"
  defp button_size("md"), do: "w-10 h-10"
  defp button_size("lg"), do: "w-12 h-12"

  defp icon_size("sm"), do: "w-4 h-4"
  defp icon_size("md"), do: "w-5 h-5"
  defp icon_size("lg"), do: "w-6 h-6"

  # Platform color helpers - returns {default_color, hover_color, colored_bg}
  defp platform_colors("twitter"), do: {"bg-gray-800 text-gray-300", "hover:bg-gray-700", "bg-gray-800 text-white"}
  defp platform_colors("facebook"), do: {"bg-gray-800 text-gray-300", "hover:bg-blue-600", "bg-blue-600 text-white hover:bg-blue-700"}
  defp platform_colors("linkedin"), do: {"bg-gray-800 text-gray-300", "hover:bg-blue-700", "bg-blue-700 text-white hover:bg-blue-800"}
  defp platform_colors("reddit"), do: {"bg-gray-800 text-gray-300", "hover:bg-orange-600", "bg-orange-600 text-white hover:bg-orange-700"}
  defp platform_colors("email"), do: {"bg-gray-800 text-gray-300", "hover:bg-gray-600", "bg-gray-600 text-white hover:bg-gray-700"}
  defp platform_colors("copy"), do: {"bg-gray-800 text-gray-300", "hover:bg-purple-600", "bg-purple-600 text-white hover:bg-purple-700"}
  defp platform_colors("pinterest"), do: {"bg-gray-800 text-gray-300", "hover:bg-red-600", "bg-red-600 text-white hover:bg-red-700"}
  defp platform_colors("whatsapp"), do: {"bg-gray-800 text-gray-300", "hover:bg-green-500", "bg-green-500 text-white hover:bg-green-600"}
  defp platform_colors("telegram"), do: {"bg-gray-800 text-gray-300", "hover:bg-blue-500", "bg-blue-500 text-white hover:bg-blue-600"}
  defp platform_colors("discord"), do: {"bg-gray-800 text-gray-300", "hover:bg-indigo-500", "bg-indigo-500 text-white hover:bg-indigo-600"}
  defp platform_colors("signal"), do: {"bg-gray-800 text-gray-300", "hover:bg-blue-600", "bg-blue-600 text-white hover:bg-blue-700"}
  defp platform_colors(_), do: {"bg-gray-800 text-gray-300", "hover:bg-gray-600", "bg-gray-600 text-white"}

  defp get_button_color(platform, colored) do
    {default, hover, colored_bg} = platform_colors(platform)
    if colored, do: colored_bg, else: "#{default} #{hover}"
  end

  defp render_button(assigns, "twitter", colored) do
    encoded_url = URI.encode_www_form(assigns.url)
    encoded_text = URI.encode_www_form(assigns.title)
    share_url = "https://twitter.com/intent/tweet?url=#{encoded_url}&text=#{encoded_text}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "Twitter/X")
    assigns = assign(assigns, :platform_color, get_button_color("twitter", colored))

    ~H"""
    <a
      href={@share_url}
      target="_blank"
      rel="noopener noreferrer"
      title={"Share on #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share on #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">X</span>
    </a>
    """
  end

  defp render_button(assigns, "facebook", colored) do
    encoded_url = URI.encode_www_form(assigns.url)
    share_url = "https://www.facebook.com/sharer/sharer.php?u=#{encoded_url}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "Facebook")
    assigns = assign(assigns, :platform_color, get_button_color("facebook", colored))

    ~H"""
    <a
      href={@share_url}
      target="_blank"
      rel="noopener noreferrer"
      title={"Share on #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share on #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">Facebook</span>
    </a>
    """
  end

  defp render_button(assigns, "linkedin", colored) do
    encoded_url = URI.encode_www_form(assigns.url)
    share_url = "https://www.linkedin.com/sharing/share-offsite/?url=#{encoded_url}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "LinkedIn")
    assigns = assign(assigns, :platform_color, get_button_color("linkedin", colored))

    ~H"""
    <a
      href={@share_url}
      target="_blank"
      rel="noopener noreferrer"
      title={"Share on #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share on #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">LinkedIn</span>
    </a>
    """
  end

  defp render_button(assigns, "reddit", colored) do
    encoded_url = URI.encode_www_form(assigns.url)
    encoded_title = URI.encode_www_form(assigns.title)
    share_url = "https://www.reddit.com/submit?url=#{encoded_url}&title=#{encoded_title}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "Reddit")
    assigns = assign(assigns, :platform_color, get_button_color("reddit", colored))

    ~H"""
    <a
      href={@share_url}
      target="_blank"
      rel="noopener noreferrer"
      title={"Share on #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share on #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M12 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0zm5.01 4.744c.688 0 1.25.561 1.25 1.249a1.25 1.25 0 0 1-2.498.056l-2.597-.547-.8 3.747c1.824.07 3.48.632 4.674 1.488.308-.309.73-.491 1.207-.491.968 0 1.754.786 1.754 1.754 0 .716-.435 1.333-1.01 1.614a3.111 3.111 0 0 1 .042.52c0 2.694-3.13 4.87-7.004 4.87-3.874 0-7.004-2.176-7.004-4.87 0-.183.015-.366.043-.534A1.748 1.748 0 0 1 4.028 12c0-.968.786-1.754 1.754-1.754.463 0 .898.196 1.207.49 1.207-.883 2.878-1.43 4.744-1.487l.885-4.182a.342.342 0 0 1 .14-.197.35.35 0 0 1 .238-.042l2.906.617a1.214 1.214 0 0 1 1.108-.701zM9.25 12C8.561 12 8 12.562 8 13.25c0 .687.561 1.248 1.25 1.248.687 0 1.248-.561 1.248-1.249 0-.688-.561-1.249-1.249-1.249zm5.5 0c-.687 0-1.248.561-1.248 1.25 0 .687.561 1.248 1.249 1.248.688 0 1.249-.561 1.249-1.249 0-.687-.562-1.249-1.25-1.249zm-5.466 3.99a.327.327 0 0 0-.231.094.33.33 0 0 0 0 .463c.842.842 2.484.913 2.961.913.477 0 2.105-.056 2.961-.913a.361.361 0 0 0 .029-.463.33.33 0 0 0-.464 0c-.547.533-1.684.73-2.512.73-.828 0-1.979-.196-2.512-.73a.326.326 0 0 0-.232-.095z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">Reddit</span>
    </a>
    """
  end

  defp render_button(assigns, "email", colored) do
    encoded_subject = URI.encode_www_form(assigns.title)
    body_text = if assigns.description do
      "#{assigns.description}\n\n#{assigns.url}"
    else
      "Check out this article: #{assigns.url}"
    end
    encoded_body = URI.encode_www_form(body_text)
    share_url = "mailto:?subject=#{encoded_subject}&body=#{encoded_body}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "Email")
    assigns = assign(assigns, :platform_color, get_button_color("email", colored))

    ~H"""
    <a
      href={@share_url}
      title={"Share via #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share via #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">Email</span>
    </a>
    """
  end

  defp render_button(assigns, "copy", colored) do
    assigns = assign(assigns, :platform_name, "Copy Link")
    assigns = assign(assigns, :platform_color, get_button_color("copy", colored))

    ~H"""
    <button
      type="button"
      phx-click={Phoenix.LiveView.JS.dispatch("phx:copy", to: "#copy-url-input-#{String.slice(@url, -10, 10) |> Base.encode16() |> String.downcase()}")}
      title="Copy link to clipboard"
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200 cursor-pointer", button_size(@size), @platform_color]}
      aria-label="Copy link to clipboard"
      data-url={@url}
      id={"copy-btn-#{String.slice(@url, -10, 10) |> Base.encode16() |> String.downcase()}"}
      onclick={"navigator.clipboard.writeText('#{@url}').then(() => { const btn = this; btn.classList.add('bg-green-600'); btn.querySelector('svg').innerHTML = '<path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M5 13l4 4L19 7\"/>'; setTimeout(() => { btn.classList.remove('bg-green-600'); btn.querySelector('svg').innerHTML = '<path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3\"/>'; }, 2000); })"}
    >
      <svg class={icon_size(@size)} fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">Copy</span>
    </button>
    """
  end

  defp render_button(assigns, "pinterest", colored) do
    encoded_url = URI.encode_www_form(assigns.url)
    encoded_description = URI.encode_www_form(assigns.title)
    image_param = if assigns.image_url do
      "&media=#{URI.encode_www_form(assigns.image_url)}"
    else
      ""
    end
    share_url = "https://pinterest.com/pin/create/button/?url=#{encoded_url}&description=#{encoded_description}#{image_param}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "Pinterest")
    assigns = assign(assigns, :platform_color, get_button_color("pinterest", colored))

    ~H"""
    <a
      href={@share_url}
      target="_blank"
      rel="noopener noreferrer"
      title={"Share on #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share on #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M12.017 0C5.396 0 .029 5.367.029 11.987c0 5.079 3.158 9.417 7.618 11.162-.105-.949-.199-2.403.041-3.439.219-.937 1.406-5.957 1.406-5.957s-.359-.72-.359-1.781c0-1.663.967-2.911 2.168-2.911 1.024 0 1.518.769 1.518 1.688 0 1.029-.653 2.567-.992 3.992-.285 1.193.6 2.165 1.775 2.165 2.128 0 3.768-2.245 3.768-5.487 0-2.861-2.063-4.869-5.008-4.869-3.41 0-5.409 2.562-5.409 5.199 0 1.033.394 2.143.889 2.741.099.12.112.225.085.345-.09.375-.293 1.199-.334 1.363-.053.225-.172.271-.401.165-1.495-.69-2.433-2.878-2.433-4.646 0-3.776 2.748-7.252 7.92-7.252 4.158 0 7.392 2.967 7.392 6.923 0 4.135-2.607 7.462-6.233 7.462-1.214 0-2.354-.629-2.758-1.379l-.749 2.848c-.269 1.045-1.004 2.352-1.498 3.146 1.123.345 2.306.535 3.55.535 6.607 0 11.985-5.365 11.985-11.987C23.97 5.39 18.592.026 11.985.026L12.017 0z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">Pinterest</span>
    </a>
    """
  end

  defp render_button(assigns, "whatsapp", colored) do
    text = "#{assigns.title} #{assigns.url}"
    encoded_text = URI.encode_www_form(text)
    share_url = "https://wa.me/?text=#{encoded_text}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "WhatsApp")
    assigns = assign(assigns, :platform_color, get_button_color("whatsapp", colored))

    ~H"""
    <a
      href={@share_url}
      target="_blank"
      rel="noopener noreferrer"
      title={"Share on #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share on #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">WhatsApp</span>
    </a>
    """
  end

  defp render_button(assigns, "telegram", colored) do
    encoded_url = URI.encode_www_form(assigns.url)
    encoded_text = URI.encode_www_form(assigns.title)
    share_url = "https://t.me/share/url?url=#{encoded_url}&text=#{encoded_text}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "Telegram")
    assigns = assign(assigns, :platform_color, get_button_color("telegram", colored))

    ~H"""
    <a
      href={@share_url}
      target="_blank"
      rel="noopener noreferrer"
      title={"Share on #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share on #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">Telegram</span>
    </a>
    """
  end

  defp render_button(assigns, "discord", colored) do
    # Discord doesn't have a direct share URL, but we can copy to clipboard for sharing
    # Using a webhook-style approach or just copying the link
    assigns = assign(assigns, :platform_name, "Discord")
    assigns = assign(assigns, :platform_color, get_button_color("discord", colored))

    ~H"""
    <button
      type="button"
      title="Copy link for Discord"
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200 cursor-pointer", button_size(@size), @platform_color]}
      aria-label="Copy link for Discord"
      data-url={@url}
      onclick={"navigator.clipboard.writeText('#{@title} #{@url}').then(() => { const btn = this; btn.classList.add('bg-green-600'); setTimeout(() => { btn.classList.remove('bg-green-600'); }, 2000); })"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189Z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">Discord</span>
    </button>
    """
  end

  defp render_button(assigns, "signal", colored) do
    # Signal uses signal.me links or sms: protocol for sharing
    text = "#{assigns.title} #{assigns.url}"
    encoded_text = URI.encode_www_form(text)
    # Signal doesn't have a web share URL, so we use SMS as fallback which Signal can intercept on mobile
    share_url = "sms:?body=#{encoded_text}"
    
    assigns = assign(assigns, :share_url, share_url)
    assigns = assign(assigns, :platform_name, "Signal")
    assigns = assign(assigns, :platform_color, get_button_color("signal", colored))

    ~H"""
    <a
      href={@share_url}
      title={"Share via #{@platform_name}"}
      class={["inline-flex items-center justify-center rounded-full transition-all duration-200", button_size(@size), @platform_color]}
      aria-label={"Share via #{@platform_name}"}
    >
      <svg class={icon_size(@size)} fill="currentColor" viewBox="0 0 24 24">
        <path d="M12 0C5.373 0 0 5.373 0 12s5.373 12 12 12 12-5.373 12-12S18.627 0 12 0zm0 2.4c5.302 0 9.6 4.298 9.6 9.6s-4.298 9.6-9.6 9.6S2.4 17.302 2.4 12 6.698 2.4 12 2.4zm0 1.2a8.4 8.4 0 100 16.8 8.4 8.4 0 000-16.8zm0 2.4a6 6 0 110 12 6 6 0 010-12zm0 1.2a4.8 4.8 0 100 9.6 4.8 4.8 0 000-9.6zm0 1.8a3 3 0 110 6 3 3 0 010-6z"/>
      </svg>
      <span :if={@show_labels} class="ml-2 hidden sm:inline">Signal</span>
    </a>
    """
  end

  # Fallback for unknown platforms
  defp render_button(_assigns, _platform, _colored), do: nil

  @doc """
  Returns the list of all supported platforms.
  """
  def supported_platforms do
    [
      %{id: "twitter", name: "Twitter/X", icon: "x"},
      %{id: "facebook", name: "Facebook", icon: "facebook"},
      %{id: "linkedin", name: "LinkedIn", icon: "linkedin"},
      %{id: "reddit", name: "Reddit", icon: "reddit"},
      %{id: "email", name: "Email", icon: "mail"},
      %{id: "copy", name: "Copy Link", icon: "clipboard"},
      %{id: "pinterest", name: "Pinterest", icon: "pinterest"},
      %{id: "whatsapp", name: "WhatsApp", icon: "whatsapp"},
      %{id: "telegram", name: "Telegram", icon: "telegram"},
      %{id: "discord", name: "Discord", icon: "discord"},
      %{id: "signal", name: "Signal", icon: "signal"}
    ]
  end

  @doc """
  Renders a settings panel for configuring share buttons.
  Used in admin/editor interfaces.
  """
  attr :show_share_buttons, :boolean, required: true
  attr :share_platforms, :list, required: true
  attr :share_buttons_colored, :boolean, default: false
  attr :on_toggle, :string, default: "toggle_share_buttons"
  attr :on_platform_toggle, :string, default: "toggle_share_platform"
  attr :on_colored_toggle, :string, default: "toggle_share_colored"
  attr :form, :any, default: nil
  attr :target, :any, default: nil

  def share_settings(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Show Share Buttons Toggle -->
      <div class="flex items-center justify-between">
        <label class="text-sm font-medium text-gray-300">Show Share Buttons</label>
        <button
          type="button"
          phx-click={@on_toggle}
          phx-target={@target}
          class={[
            "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
            if(@show_share_buttons, do: "bg-blue-600", else: "bg-gray-600")
          ]}
        >
          <span class={[
            "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
            if(@show_share_buttons, do: "translate-x-5", else: "translate-x-0")
          ]}></span>
        </button>
      </div>

      <div :if={@show_share_buttons} class="space-y-4">
        <!-- Colored Style Toggle -->
        <div class="flex items-center justify-between">
          <div>
            <label class="text-sm font-medium text-gray-300">Colored Icons</label>
            <p class="text-xs text-gray-500">Show brand colors or monochrome</p>
          </div>
          <button
            type="button"
            phx-click={@on_colored_toggle}
            phx-target={@target}
            class={[
              "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2",
              if(@share_buttons_colored, do: "bg-blue-600", else: "bg-gray-600")
            ]}
          >
            <span class={[
              "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
              if(@share_buttons_colored, do: "translate-x-5", else: "translate-x-0")
            ]}></span>
          </button>
        </div>

        <!-- Platform Selection -->
        <div class="space-y-2">
          <label class="text-sm font-medium text-gray-300 block">Enabled Platforms</label>
          <div class="grid grid-cols-2 gap-2">
            <%= for platform <- supported_platforms() do %>
              <label class="flex items-center gap-2 p-2 rounded-lg bg-gray-800 hover:bg-gray-700 cursor-pointer">
                <input
                  type="checkbox"
                  checked={platform.id in @share_platforms}
                  phx-click={@on_platform_toggle}
                  phx-value-platform={platform.id}
                  phx-target={@target}
                  class="rounded border-gray-600 bg-gray-700 text-blue-600 focus:ring-blue-500"
                />
                <span class="text-sm text-gray-300"><%= platform.name %></span>
              </label>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
