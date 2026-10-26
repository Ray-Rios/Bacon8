defmodule ChatChannelsWeb.ChatComponents do
  @moduledoc """
  The Chat page's function components: a message (with its replies, reactions and attachments)
  and the two emoji pickers. They were part of `ChatChannelsWeb.ChatLive`; they take everything
  they show as assigns and send their clicks to the page as ordinary events.
  """
  use Bacon8Web, :html
  alias Phoenix.LiveView.JS
  import Bacon8Web.AvatarHelpers

  attr :id, :string, default: nil
  attr :message, :map, required: true
  attr :current_user, :map, required: true
  attr :can_moderate, :boolean, required: true
  attr :replying_to_message_id, :string, default: nil
  attr :editing_message_id, :string, default: nil
  attr :editing_message_content, :string, default: ""
  attr :reply_message_content, :string, default: ""
  attr :last_read_message_id, :string, default: nil
  attr :depth, :integer, default: 0
  attr :uploads, :map, required: true

  def message_item(assigns) do
    assigns = Map.put_new(assigns, :depth, 0)
    ~H"""
    <div id={@id || "message-#{@message.id}"} class="flex flex-col mb-4 group relative">
      <div class="flex items-start">
        <div class="mr-4 relative group/avatar">
          <%= avatar_tag(@message.user, size_class: "w-10 h-10 cursor-pointer") %>
          
          <!-- User Hover Card -->
          <div class="absolute left-0 top-full mt-2 w-96 bg-gray-800 border border-gray-700 rounded-lg shadow-xl z-50 opacity-0 invisible group-hover/avatar:opacity-100 group-hover/avatar:visible transition-all duration-200 p-4 pointer-events-none group-hover/avatar:pointer-events-auto">
            <div class="flex items-start space-x-4 mb-3">
              <%= avatar_tag(@message.user, size_class: "w-32 h-32") %>
              <div class="flex-1 min-w-0">
                <div class="font-bold text-white text-lg truncate"><%= @message.user.name || @message.user.email %></div>
                <div class="text-xs text-gray-400">Joined <%= Calendar.strftime(@message.user.inserted_at, "%b %Y") %></div>
                <%= if @message.user.role do %>
                  <div class={[
                    "mt-1 inline-block px-2 py-0.5 rounded text-xs font-bold border",
                    case @message.user.role do
                      "admin" -> "bg-red-900 text-red-200 border-red-700"
                      "gm" -> "bg-purple-900 text-purple-200 border-purple-700"
                      "editor" -> "bg-blue-900 text-blue-200 border-blue-700"
                      "moderator" -> "bg-green-900 text-green-200 border-green-700"
                      "member" -> "bg-gray-700 text-gray-200 border-gray-600"
                      _ -> "bg-gray-700 text-gray-300 border-gray-600"
                    end
                  ]}>
                    <%= String.upcase(@message.user.role) %>
                  </div>
                <% end %>
              </div>
            </div>
            
            <%= if Map.get(@message.user, :bio) do %>
              <div class="text-sm text-gray-300 border-t border-gray-700 pt-2 break-words">
                <%= @message.user.bio %>
              </div>
            <% end %>
          </div>
        </div>
        <div class="flex-1">
          <div class="flex items-baseline">
            <span class="font-bold text-gray-800 dark:text-gray-200 mr-2"><%= @message.user.name || @message.user.email %></span>
            <time datetime={@message.inserted_at} class="text-xs text-gray-500 dark:text-gray-400"><%= Calendar.strftime(@message.inserted_at, "%b %d %Y %I:%M %p") %></time>
            <%= if @message.is_pinned do %>
              <span class="ml-2 text-xs bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200 px-1.5 py-0.5 rounded flex items-center gap-1">
                <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 24 24"><path d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"></path></svg>
                Pinned
              </span>
            <% end %>
            <%= if @last_read_message_id && @message.id == @last_read_message_id do %>
              <span class="text-xs text-green-500 ml-2">✓ read</span>
            <% end %>
            
            <%!-- Message actions --%>
            <div class="ml-auto opacity-0 group-hover:opacity-100 transition-opacity flex items-center space-x-2">
              <%!-- Reaction picker button (triggers dropdown near reactions) --%>
              <button 
                type="button" 
                phx-click={JS.toggle(to: "#reaction-dropdown-#{@message.id}", in: "fade-in-scale", out: "fade-out-scale")}
                class="text-gray-400 hover:text-yellow-500 text-xs" 
                title="Add reaction"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
              </button>
              
              <% 
                replies = if Ecto.assoc_loaded?(@message.replies), do: @message.replies, else: []
                has_replied = Enum.any?(replies, fn r -> r.user_id == @current_user.id end)
              %>
              <%= if @message.user_id != @current_user.id && !has_replied do %>
                <button type="button" phx-click="start_reply" phx-value-message_id={@message.id} class="text-gray-400 hover:text-green-500 text-xs" title="Reply">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"></path></svg>
                </button>
              <% end %>

              <%= if @can_moderate and is_nil(@message.reply_to_id) do %>
                <button 
                  type="button"
                  phx-click="toggle_pin" 
                  phx-value-message_id={@message.id}
                  class={"text-xs " <> if(@message.is_pinned, do: "text-yellow-500 hover:text-yellow-600", else: "text-gray-400 hover:text-yellow-500")}
                  title={if @message.is_pinned, do: "Unpin message", else: "Pin message"}
                >
                  <svg class="w-4 h-4" fill={if @message.is_pinned, do: "currentColor", else: "none"} stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 5a2 2 0 012-2h10a2 2 0 012 2v16l-7-3.5L5 21V5z"></path>
                  </svg>
                </button>
              <% end %>

              <%= if @message.user_id == @current_user.id or @can_moderate do %>
                <button 
                  type="button"
                  phx-click="start_edit_message" 
                  phx-value-message_id={@message.id}
                  class="text-gray-400 hover:text-blue-500 text-xs"
                  title="Edit message"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>
                  </svg>
                </button>
                <button 
                  type="button"
                  phx-click="delete_message" 
                  phx-value-message_id={@message.id}
                  class="text-gray-400 hover:text-red-500 text-xs"
                  title="Delete message"
                  data-confirm="Are you sure you want to delete this message?"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                  </svg>
                </button>
              <% end %>
            </div>
          </div>

          <%= if @editing_message_id == @message.id do %>
            <p class="text-gray-500 italic text-sm">(Editing in form below...)</p>
          <% else %>
            <p class="text-gray-700 dark:text-gray-300"><%= @message.content %></p>
          <% end %>

          <%!-- Attachments --%>
          <%= if Ecto.assoc_loaded?(@message.attachments) && length(@message.attachments) > 0 do %>
            <div class="mt-2 flex flex-wrap gap-2">
              <%= for attachment <- @message.attachments do %>
                <% is_video = String.starts_with?(Map.get(attachment, :content_type) || Map.get(attachment, :file_type) || "", "video") %>
                <div class="relative group/item">
                  <div class={if(is_video, do: "w-auto flex items-center justify-center rounded-lg overflow-hidden border border-transparent hover:border-gray-200 dark:hover:border-gray-700 bg-transparent", else: "h-48 w-auto flex items-center justify-center rounded-lg overflow-hidden border border-transparent hover:border-gray-200 dark:hover:border-gray-700 bg-transparent")}>
                    <Bacon8Web.Components.MediaPreview.media_preview attachment={attachment} class={if(is_video, do: "max-w-full", else: "max-h-48 max-w-xs object-contain")} show_filename={false} />
                  </div>
                  
                  <%= if @current_user && (@current_user.id == attachment.user_id || @current_user.id == @message.user_id || @current_user.role in ["admin", "gm", "editor"] || Map.get(@current_user, :is_admin, false)) do %>
                    <button 
                      phx-click="delete_attachment" 
                      phx-value-attachment_id={attachment.id} 
                      class="absolute top-1 right-1 bg-red-500 hover:bg-red-600 text-white rounded-full w-6 h-6 flex items-center justify-center shadow-md opacity-0 group-hover/item:opacity-100 transition-opacity z-10"
                      title="Delete attachment"
                      data-confirm="Delete this attachment?"
                    >
                      <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
          
          <div class="flex flex-wrap gap-1 mt-1">
            <%= for {emoji, count} <- group_reactions(@message.reactions) do %>
              <% 
                reactors = Enum.filter(@message.reactions, fn r -> r.emoji == emoji end)
                user_reacted = Enum.any?(reactors, fn r -> r.user_id == @current_user.id end)
                reactor_names = Enum.map_join(reactors, ", ", fn r -> 
                  if Ecto.assoc_loaded?(r.user) do
                    r.user.name || r.user.email || "Unknown"
                  else
                    "User"
                  end
                end)
              %>
              <button 
                type="button"
                phx-click="toggle_reaction"
                phx-value-message_id={@message.id}
                phx-value-emoji={emoji}
                class={"flex items-center px-2 py-0.5 rounded-full text-sm transition-colors cursor-pointer border #{if user_reacted, do: "bg-transparent border-transparent", else: "bg-transparent border-transparent hover:bg-gray-100 dark:hover:bg-gray-800"}"}
                title={reactor_names}
              >
                <span><%= emoji %></span>
                <span class="text-xs text-gray-600 dark:text-gray-400 ml-1"><%= count %></span>
              </button>
            <% end %>
            <%!-- Quick add reaction button (shows on message hover, hidden when user has 5 reactions) --%>
            <% user_reaction_count = Enum.count(@message.reactions, fn r -> r.user_id == @current_user.id end) %>
            <%= if user_reaction_count < 5 do %>
              <div class="relative opacity-0 group-hover:opacity-100 transition-opacity">
                <button 
                  type="button"
                  phx-click={JS.toggle(to: "#reaction-dropdown-#{@message.id}", in: "fade-in-scale", out: "fade-out-scale")}
                  class="flex items-center px-2 py-0.5 rounded-full text-sm hover:bg-gray-200 dark:hover:bg-gray-700 text-gray-500 transition-colors"
                  title="Add reaction"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>
                </svg>
              </button>
              <%!-- Full emoji reaction dropdown with categories --%>
              <.reaction_emoji_picker id={"reaction-dropdown-#{@message.id}"} message_id={@message.id} />
            </div>
            <% end %>
          </div>
          
          <%!-- Collapsible Replies removed (using recursive Nested Replies below) --%>

        </div>
      </div>

      <!-- Reply indicator (form is rendered outside the stream) -->
      <%= if @replying_to_message_id == @message.id do %>
        <div class="ml-14 mt-2 mb-4">
          <p class="text-gray-500 italic text-sm">(Replying in form below...)</p>
        </div>
      <% end %>

      <!-- Nested Replies (Collapsible) -->
      <% 
        replies = if Ecto.assoc_loaded?(@message.replies), do: @message.replies, else: []
      %>
      <%= if length(replies) > 0 && @depth < 10 do %>
        <div class="ml-14 mt-1">
          <button 
            type="button"
            phx-click={JS.toggle(to: "#replies-#{@message.id}", in: "fade-in", out: "fade-out") |> JS.toggle_class("rotate-90", to: "#chevron-#{@message.id}")}
            class="flex items-center text-xs text-blue-500 hover:text-blue-400 focus:outline-none mb-2"
          >
            <svg id={"chevron-#{@message.id}"} class="w-3 h-3 mr-1 transform transition-transform duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"></path>
            </svg>
            <%= length(replies) %> <%= if length(replies) == 1, do: "Reply", else: "Replies" %>
          </button>
          
          <div id={"replies-#{@message.id}"} class="hidden border-l-2 border-gray-200 dark:border-gray-700 pl-4">
            <%= for reply <- replies do %>
              <.message_item 
                id={"reply-#{reply.id}"}
                message={reply} 
                current_user={@current_user} 
                can_moderate={@can_moderate} 
                replying_to_message_id={@replying_to_message_id} 
                editing_message_id={@editing_message_id} 
                editing_message_content={@editing_message_content}
                reply_message_content={@reply_message_content}
                last_read_message_id={@last_read_message_id}
                depth={@depth + 1}
                uploads={@uploads}
              />
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :target, :string, required: true
  attr :id, :string, required: true
  def emoji_picker(assigns) do
    # Comprehensive emoji list organized by categories
    assigns = assign(assigns, :emoji_categories, %{
      "😀" => ~w(😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 🤯 🤠 🥳 🥸 😎 🤓 🧐),
      "😢" => ~w(😕 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖),
      "👋" => ~w(👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪),
      "❤️" => ~w(❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟),
      "🐶" => ~w(🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🪱 🐛 🦋 🐌 🐞 🐜 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🐊 🦓 🦍 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🦬 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🐐 🦌 🐕 🐈 🐓 🦃 🦚 🦜 🦢 🦩 🐇 🦔),
      "🍕" => ~w(🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🌽 🥕 🥔 🍠 🥐 🍞 🥖 🥨 🧀 🥚 🍳 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🥙 🌮 🌯 🥗 🥘 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 ☕ 🍵 🥤 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🍾),
      "⚽" => ~w(⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🥏 🎱 🏓 🏸 🏒 🏑 🥍 🏏 🥅 ⛳ 🏹 🎣 🥊 🥋 🎽 🛹 🛷 ⛸️ 🥌 🎿 ⛷️ 🏂 🏋️ 🤼 🤸 🤺 🤾 🏌️ 🏇 🧘 🏄 🏊 🤽 🚣 🧗 🚴 🚵 🏆 🥇 🥈 🥉 🏅 🎪 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🎻 🎲 🎯 🎳 🎮 🎰 🧩),
      "🚗" => ~w(🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🛴 🚲 🛵 🏍️ 🚨 🚔 🚍 🚘 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓ ⛽ 🚧 🚦 🚥 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 ⛲ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🏕️ ⛺ 🏠 🏡 🏢 🏬 🏣 🏥 🏦 🏨 🏪 🏫 💒 🏛️ ⛪ 🕌 🕍 🕋 ⛩️ 🏙️ 🌃 🌌 🌉 🌁),
      "💡" => ~w(⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 🕹️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 📞 ☎️ 📺 📻 🎙️ ⏱️ ⏲️ ⏰ 🕰️ ⌛ ⏳ 📡 🔋 🔌 💡 🔦 🕯️ 🧯 💸 💵 💴 💶 💷 💰 💳 💎 ⚖️ 🧰 🔧 🔨 🛠️ ⛏️ 🔩 ⚙️ 🔫 💣 🔪 🗡️ ⚔️ 🛡️ 🔮 💈 🔭 🔬 🩹 🩺 💊 💉 🧬 🦠 🧪 🌡️ 🧹 🧺 🧻 🚽 🚰 🚿 🛁 🧼 🔑 🗝️ 🚪 🛋️ 🛏️ 🧸 🖼️ 🛍️ 🛒 🎁 🎈 🎏 🎀 🎊 🎉 🎎 🏮 🎐 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷️ 📪 📫 📬 📭 📮 📯 📜 📃 📄 📊 📈 📉 📆 📅 🗑️ 📋 📁 📂 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🔗 📎 📐 📏 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔒 🔓),
      "✨" => ~w(❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ☦️ ⚛️ ☢️ ☣️ 🈚 🈸 🈺 🈷️ ✴️ 🆚 💮 🉐 🈴 🈵 🈹 🈲 🅰️ 🅱️ 🆎 🆑 🅾️ 🆘 ❌ ⭕ 🛑 ⛔ 📛 🚫 💯 💢 ♨️ 🚷 🚯 🚳 🚱 🔞 📵 🚭 ❗ ❕ ❓ ❔ ‼️ ⁉️ 🔅 🔆 ⚠️ 🚸 🔱 ⚜️ 🔰 ♻️ ✅ 💹 ❇️ ✳️ ❎ 🌐 💠 🌀 💤 🏧 🚾 ♿ 🅿️ 🈳 🈂️ 🛂 🛃 🛄 🛅 🚹 🚺 🚼 🚻 🚮 🎦 📶 🆖 🆗 🆙 🆒 🆕 🆓 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 #️⃣ *️⃣ ⏏️ ▶️ ⏸️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ ⏫ ⏬ ◀️ 🔼 🔽 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ↪️ ↩️ ⤴️ ⤵️ 🔀 🔁 🔂 🔄 🔃 🎵 🎶 ➕ ➖ ➗ ✖️ ♾️ 💲 ™️ ©️ ®️ ✔️ ☑️ 🔘 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔸 🔹 🔶 🔷 🔳 🔲 ▪️ ▫️ ◾ ◽ ◼️ ◻️ 🟥 🟧 🟨 🟩 🟦 🟪 ⬛ ⬜ 🟫 🔈 🔇 🔉 🔊 🔔 🔕 📣 📢 💬 💭 🗯️ ♠️ ♣️ ♥️ ♦️ 🃏 🎴)
    })

    ~H"""
    <div class="relative inline-block" id={@id}>
      <button 
        type="button" 
        phx-click={JS.toggle(to: "##{@id}-dropdown", in: "fade-in-scale", out: "fade-out-scale")}
        class="text-gray-500 hover:text-yellow-500 p-1 rounded transition-colors"
        title="Insert emoji"
      >
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      </button>
      
      <div 
        id={"#{@id}-dropdown"}
        class="hidden absolute bottom-full right-0 mb-2 w-80 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-xl z-50"
        phx-click-away={JS.hide(to: "##{@id}-dropdown")}
      >
        <%!-- Category tabs --%>
        <div class="flex border-b border-gray-200 dark:border-gray-700 overflow-x-auto px-1 py-1">
          <%= for {icon, _emojis} <- @emoji_categories do %>
            <button 
              type="button"
              class="px-2 py-1 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded"
              onclick={"
                document.querySelectorAll('##{@id}-dropdown .emoji-category').forEach(el => el.classList.add('hidden'));
                document.getElementById('#{@id}-cat-' + this.dataset.cat).classList.remove('hidden');
              "}
              data-cat={icon}
            >
              <%= icon %>
            </button>
          <% end %>
        </div>
        
        <%!-- Emoji grids by category --%>
        <div class="p-2 max-h-48 overflow-y-auto">
          <%= for {icon, emojis} <- @emoji_categories do %>
            <div 
              id={"#{@id}-cat-#{icon}"} 
              class={"emoji-category grid grid-cols-8 gap-1 #{if icon != "😀", do: "hidden", else: ""}"}
            >
              <%= for emoji <- emojis do %>
                <button 
                  type="button" 
                  class="text-xl hover:bg-gray-100 dark:hover:bg-gray-700 p-1 rounded"
                  phx-click={JS.dispatch("insert-text", to: @target, detail: %{text: emoji}) |> JS.hide(to: "##{@id}-dropdown")}
                >
                  <%= emoji %>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Reaction emoji picker - same categories as message input but triggers toggle_reaction
  attr :id, :string, required: true
  attr :message_id, :string, required: true
  def reaction_emoji_picker(assigns) do
    assigns = assign(assigns, :emoji_categories, %{
      "😀" => ~w(😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 🤯 🤠 🥳 🥸 😎 🤓 🧐),
      "😢" => ~w(😕 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖),
      "👋" => ~w(👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪),
      "❤️" => ~w(❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟),
      "🐶" => ~w(🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🪱 🐛 🦋 🐌 🐞 🐜 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🐊 🦓 🦍 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🦬 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🐐 🦌 🐕 🐈 🐓 🦃 🦚 🦜 🦢 🦩 🐇 🦔),
      "🍕" => ~w(🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🌽 🥕 🥔 🍠 🥐 🍞 🥖 🥨 🧀 🥚 🍳 🥞 🧇 🥓 🥩 🍗 🍖 🌭 🍔 🍟 🍕 🥪 🥙 🌮 🌯 🥗 🥘 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🍤 🍙 🍚 🍘 🍥 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 ☕ 🍵 🥤 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🍾),
      "⚽" => ~w(⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🥏 🎱 🏓 🏸 🏒 🏑 🥍 🏏 🥅 ⛳ 🏹 🎣 🥊 🥋 🎽 🛹 🛷 ⛸️ 🥌 🎿 ⛷️ 🏂 🏋️ 🤼 🤸 🤺 🤾 🏌️ 🏇 🧘 🏄 🏊 🤽 🚣 🧗 🚴 🚵 🏆 🥇 🥈 🥉 🏅 🎪 🎭 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🎷 🎺 🎸 🎻 🎲 🎯 🎳 🎮 🎰 🧩),
      "🚗" => ~w(🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🛴 🚲 🛵 🏍️ 🚨 🚔 🚍 🚘 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓ ⛽ 🚧 🚦 🚥 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 ⛲ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🏕️ ⛺ 🏠 🏡 🏢 🏬 🏣 🏥 🏦 🏨 🏪 🏫 💒 🏛️ ⛪ 🕌 🕍 🕋 ⛩️ 🏙️ 🌃 🌌 🌉 🌁),
      "💡" => ~w(⌚ 📱 💻 ⌨️ 🖥️ 🖨️ 🖱️ 🕹️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 📞 ☎️ 📺 📻 🎙️ ⏱️ ⏲️ ⏰ 🕰️ ⌛ ⏳ 📡 🔋 🔌 💡 🔦 🕯️ 🧯 💸 💵 💴 💶 💷 💰 💳 💎 ⚖️ 🧰 🔧 🔨 🛠️ ⛏️ 🔩 ⚙️ 🔫 💣 🔪 🗡️ ⚔️ 🛡️ 🔮 💈 🔭 🔬 🩹 🩺 💊 💉 🧬 🦠 🧪 🌡️ 🧹 🧺 🧻 🚽 🚰 🚿 🛁 🧼 🔑 🗝️ 🚪 🛋️ 🛏️ 🧸 🖼️ 🛍️ 🛒 🎁 🎈 🎏 🎀 🎊 🎉 🎎 🏮 🎐 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷️ 📪 📫 📬 📭 📮 📯 📜 📃 📄 📊 📈 📉 📆 📅 🗑️ 📋 📁 📂 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🔗 📎 📐 📏 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔒 🔓),
      "✨" => ~w(❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ☦️ ⚛️ ☢️ ☣️ ✴️ 🆚 💮 🉐 🅰️ 🅱️ 🆎 🆑 🅾️ 🆘 ❌ ⭕ 🛑 ⛔ 📛 🚫 💯 💢 ♨️ 🚷 🔞 ❗ ❕ ❓ ❔ ‼️ ⁉️ ⚠️ 🚸 🔱 ⚜️ 🔰 ♻️ ✅ 💹 ❇️ ✳️ ❎ 🌐 💠 🌀 💤 ▶️ ⏸️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ ◀️ 🔼 🔽 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ↪️ ↩️ 🔀 🔁 🔂 🔄 🔃 🎵 🎶 ➕ ➖ ➗ ✖️ ♾️ 💲 ™️ ©️ ®️ ✔️ ☑️ 🔘 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔸 🔹 🔶 🔷 🔳 🔲 ▪️ ▫️ 🟥 🟧 🟨 🟩 🟦 🟪 ⬛ ⬜ 🟫 🔈 🔇 🔉 🔊 🔔 🔕 📣 📢 💬 💭 🗯️ ♠️ ♣️ ♥️ ♦️ 🃏 🎴)
    })

    ~H"""
    <div 
      id={@id}
      class="hidden absolute bottom-full left-0 mb-2 w-80 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-xl z-50"
      phx-click-away={JS.hide(to: "##{@id}")}
    >
      <%!-- Category tabs --%>
      <div class="flex border-b border-gray-200 dark:border-gray-700 overflow-x-auto px-1 py-1">
        <%= for {icon, _emojis} <- @emoji_categories do %>
          <button 
            type="button"
            class="px-2 py-1 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded"
            onclick={"
              document.querySelectorAll('##{@id} .emoji-category').forEach(el => el.classList.add('hidden'));
              document.getElementById('#{@id}-cat-' + this.dataset.cat).classList.remove('hidden');
            "}
            data-cat={icon}
          >
            <%= icon %>
          </button>
        <% end %>
      </div>
      
      <%!-- Emoji grids by category --%>
      <div class="p-2 max-h-48 overflow-y-auto">
        <%= for {icon, emojis} <- @emoji_categories do %>
          <div 
            id={"#{@id}-cat-#{icon}"} 
            class={"emoji-category grid grid-cols-8 gap-1 #{if icon != "😀", do: "hidden", else: ""}"}
          >
            <%= for emoji <- emojis do %>
              <button 
                type="button" 
                class="text-xl hover:bg-gray-100 dark:hover:bg-gray-700 p-1 rounded"
                phx-click={JS.push("toggle_reaction") |> JS.hide(to: "##{@id}")}
                phx-value-message_id={@message_id}
                phx-value-emoji={emoji}
              >
                <%= emoji %>
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp group_reactions(reactions) do
    Enum.group_by(reactions, &(&1.emoji))
    |> Enum.map(fn {emoji, reactions} -> {emoji, length(reactions)} end)
  end

  @doc """
  The channel list: invitations, public and private channels, the invite switch.
  """
  attr :allow_invites, :any, required: true
  attr :current_channel, :any, required: true
  attr :current_user, :any, required: true
  attr :pending_invites, :any, required: true
  attr :private_channels, :any, required: true
  attr :public_channels, :any, required: true
  attr :sidebar_open, :any, required: true
  def chat_sidebar(assigns) do
    ~H"""
        <div 
          id="forum-sidebar" 
          phx-hook="SidebarResizer" 
          data-sidebar-open={@sidebar_open}
          class="dark-glass border-r border-cyan-500/30 flex flex-col flex-none overflow-hidden z-40 relative"
        >
          <div class="flex-1 overflow-y-auto p-4 overflow-x-hidden sidebar-content">
            <label id="allow-invites" class="mb-4 flex items-center gap-2 text-xs text-gray-400 cursor-pointer">
              <input type="checkbox" phx-click="toggle_invites" checked={@allow_invites} class="rounded" />
              Let people invite me to channels
            </label>

            <%!-- Invitations (they used to be in the desktop's notification panel) --%>
            <%= if @pending_invites != [] do %>
              <div class="mb-6" id="pending-invites">
                <h2 class="text-xs font-semibold text-amber-400 uppercase tracking-wide mb-2">
                  Invitations (<%= length(@pending_invites) %>)
                </h2>
                <ul class="space-y-2">
                  <%= for invite <- @pending_invites do %>
                    <li class="rounded-lg border border-amber-500/30 bg-amber-500/10 p-2 text-sm">
                      <div class="text-gray-200">
                        <span class="font-semibold text-cyan-300"><%= invite.inviter.name || invite.inviter.email %></span>
                        invited you to
                        <span class="font-semibold text-purple-300">#<%= invite.channel.name %></span>
                      </div>
                      <div class="mt-2 flex gap-2">
                        <button type="button" phx-click="accept_invite" phx-value-invite_id={invite.id}
                                class="flex-1 rounded bg-green-600 px-2 py-1 text-xs font-medium text-white hover:bg-green-700">Accept</button>
                        <button type="button" phx-click="decline_invite" phx-value-invite_id={invite.id}
                                class="flex-1 rounded bg-gray-600 px-2 py-1 text-xs font-medium text-white hover:bg-gray-700">Decline</button>
                      </div>
                    </li>
                  <% end %>
                </ul>
              </div>
            <% end %>

            <%!-- Public Channels Section --%>
            <div class="mb-6">
                <div class="flex items-center justify-between mb-2">
                  <h2 class="text-xs font-semibold text-gray-600 dark:text-gray-400 uppercase tracking-wide">Public Channels</h2>
                  <div class="flex items-center gap-2">
                    <button phx-click={if @current_user && (Map.get(@current_user, :is_admin, false) || @current_user.role in ["admin","gm"]), do: "show_create_channel", else: "show_create_user_channel"} class="flex items-center space-x-2 text-sm text-gray-700 dark:text-gray-200 bg-gray-100 dark:bg-gray-700 px-2 py-1 rounded hover:bg-gray-200 dark:hover:bg-gray-600">
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path></svg>
                      <span>Create new channel</span>
                    </button>
                  </div>
                </div>
              <ul class="space-y-0.5" id="public-channels-list" phx-hook="Sortable" data-group="public">
                <%= for channel <- @public_channels do %>
                  <li draggable="true" data-id={channel.id} class="cursor-move">
                    <a href="#" phx-click="switch_channel" phx-value-channel_id={channel.id} class={"flex items-center px-2 py-1.5 rounded text-sm hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors #{active_channel_class(channel, @current_channel)}"}>
                      <%= if channel.icon_path do %>
                        <img src={channel.icon_path} class="w-5 h-5 rounded-full object-cover mr-2 flex-shrink-0" />
                      <% else %>
                        <span class="mr-2 text-gray-500">#</span>
                      <% end %>
                      <span class="truncate"><%= channel.name %></span>
                    </a>
                  </li>
                <% end %>
              </ul>
            </div>

            <%!-- Private Channels Section --%>
            <div class="mb-6">
              <div class="flex items-center justify-between mb-2">
                <h2 class="text-xs font-semibold text-gray-600 dark:text-gray-400 uppercase tracking-wide">Private Channels</h2>
                <%!-- leave a small spacer to visually align --%>
                <div class="w-24"></div>
              </div>
              <ul class="space-y-0.5" id="private-channels-list" phx-hook="Sortable" data-group="private">
                <%= for channel <- @private_channels do %>
                  <li draggable="true" data-id={channel.id} class="cursor-move">
                    <a href="#" phx-click="switch_channel" phx-value-channel_id={channel.id} class={"flex items-center px-2 py-1.5 rounded text-sm hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors #{active_channel_class(channel, @current_channel)}"}>
                      <%= if channel.icon_path do %>
                        <img src={channel.icon_path} class="w-5 h-5 rounded-full object-cover mr-2 flex-shrink-0" />
                      <% else %>
                        <svg class="w-3 h-3 mr-2 flex-shrink-0 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"></path>
                        </svg>
                      <% end %>
                      <span class="truncate"><%= channel.name %></span>
                    </a>
                  </li>
                <% end %>
              </ul>
            </div>
          </div>
          <!-- Handle -->
          <div class="resize-handle absolute top-0 right-0 w-2 h-full cursor-col-resize hover:bg-blue-500/50 transition-colors z-20 flex items-center justify-center">
            <div class="w-1 h-8 bg-gray-400/50 rounded-full"></div>
          </div>
        </div>
    """
  end

  @doc """
  A channel's members: roles, bans, kicks, ownership.
  """
  attr :channel_members, :any, required: true
  attr :current_user, :any, required: true
  attr :editing_channel, :any, required: true
  attr :show_channel_modal, :any, required: true
  def members_modal(assigns) do
    ~H"""
    <%= if @show_channel_modal do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/50" phx-click="hide_members_modal"></div>
        <div class="relative bg-white dark:bg-gray-800 rounded-xl shadow-xl p-6 max-w-3xl w-full mx-4 border">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-semibold text-gray-900 dark:text-gray-100">Members — #<%= @editing_channel.name %></h3>
            <button phx-click="hide_members_modal" class="text-gray-500 hover:text-gray-700">✕</button>
          </div>

          <div class="space-y-3">
            <% can_manage = ChatChannels.can_manage_channel?(@current_user, @editing_channel) %>
            <% can_moderate = ChatChannels.can_moderate_channel?(@current_user, @editing_channel) %>
            <% show_actions = can_manage || can_moderate %>
            
            <div class={"grid gap-4 font-medium text-sm text-gray-500 dark:text-gray-300 border-b pb-2 " <> if(show_actions, do: "grid-cols-3", else: "grid-cols-2")}>
              <div>Member</div>
              <div>Role</div>
              <%= if show_actions do %>
                <div class="text-right">Actions</div>
              <% end %>
            </div>

            <%= for member <- (@channel_members || []) do %>
              <div class={"grid gap-4 items-center py-2 border-b " <> if(show_actions, do: "grid-cols-3", else: "grid-cols-2")}>
                <div class="flex items-center gap-3">
                  <%= if member.user do %>
                    <%= avatar_tag(member.user, size_class: "w-8 h-8") %>
                    <div class="text-sm flex items-center gap-1">
                      <%= member.user.name || member.user.email %>
                      <%= if @editing_channel.owner_id == member.user_id do %>
                        <span class="text-yellow-500" title="Channel Owner">👑</span>
                      <% end %>
                    </div>
                  <% else %>
                    <div class="w-8 h-8 rounded-full bg-gray-600 flex items-center justify-center text-white text-sm">?</div>
                    <div class="text-sm text-gray-400">Unknown user</div>
                  <% end %>
                </div>

                <div>
                  <%= if member.role == "invited" do %>
                    <div class="inline-flex items-center gap-2 text-xs text-gray-600 dark:text-gray-300">
                      <span class="px-2 py-0.5 rounded bg-yellow-100 dark:bg-yellow-700 text-yellow-800 dark:text-yellow-100">Invited</span>
                      <span class="text-xs text-gray-500">(pending)</span>
                    </div>
                  <% else %>
                    <%= if member.is_banned do %>
                      <div class="inline-flex items-center gap-2">
                        <span class="px-2 py-0.5 rounded bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-100 text-xs font-bold">BANNED</span>
                        <span class="text-sm text-gray-500 dark:text-gray-400"><%= String.capitalize(member.role) %></span>
                      </div>
                    <% else %>
                      <%= if is_nil(member.id) and member.role == "owner" do %>
                        <div class="inline-flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200">Owner</div>
                      <% else %>
                        <%= if member.user_id == @current_user.id do %>
                          <div class="inline-flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200"><%= String.capitalize(member.role) %></div>
                        <% else %>
                          <%= if can_manage do %>
                            <form phx-change="change_member_role" phx-submit="noop" class="inline-block">
                              <input type="hidden" name="member_id" value={member.id} />
                              <select name="new_role" class="p-1 rounded bg-gray-100 dark:bg-gray-700 text-sm border">
                                <option value="moderator" selected={member.role == "moderator"}>Moderator</option>
                                <option value="member" selected={member.role == "member"}>Member</option>
                              </select>
                            </form>
                          <% else %>
                            <div class="inline-flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200"><%= String.capitalize(member.role) %></div>
                          <% end %>
                        <% end %>
                      <% end %>
                    <% end %>
                  <% end %>
                </div>

                <%= if show_actions do %>
                  <div class="text-right">
                    <div class="inline-flex gap-2">
                      <%= if member.role == "invited" do %>
                        <button phx-click="revoke_invite" phx-value-invite_id={Map.get(member, :_invite_id)} class="px-2 py-1 bg-red-500 hover:bg-red-600 text-white rounded text-xs">Revoke Invite</button>
                      <% else %>
                        <%!-- Only show member-management actions for real ChannelMember records (member.id present). Owner pseudo entries don't get manage buttons here. --%>
                        <%= if member.id && member.user_id != @current_user.id do %>
                          <%!-- Moderators cannot ban/kick the Owner --%>
                          <%= if can_moderate && member.role != "owner" && member.user_id != @editing_channel.owner_id do %>
                            <%= if member.is_banned do %>
                              <button phx-click="unban_member" phx-value-member_id={member.id} class="px-2 py-1 bg-green-500 hover:bg-green-600 text-white rounded text-xs">Unban</button>
                            <% else %>
                              <button phx-click="ban_member" phx-value-member_id={member.id} class="px-2 py-1 bg-red-500 hover:bg-red-600 text-white rounded text-xs">Ban</button>
                            <% end %>
                            <button phx-click="kick_member" phx-value-member_id={member.id} class="px-2 py-1 bg-gray-500 hover:bg-gray-600 text-white rounded text-xs">Kick</button>
                          <% end %>
                        <% end %>

                        <%!-- Only show Make Owner button if member is not already the owner --%>
                        <%= if member.role != "owner" && @editing_channel.owner_id != member.user_id && member.user_id != @current_user.id do %>
                          <%= if can_manage do %>
                            <button phx-click="transfer_ownership" phx-value-new_owner_id={member.user_id} class="px-2 py-1 bg-blue-500 hover:bg-blue-600 text-white rounded text-xs">Make Owner</button>
                          <% end %>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Creates a channel (system channel for staff, private channel for a member).
  """
  attr :channel_form, :any, required: true
  attr :creating_user_channel, :any, required: true
  attr :current_channel, :any, required: true
  attr :show_create_channel_form, :any, required: true
  attr :show_delete_channel_confirm, :any, required: true
  def create_channel_modal(assigns) do
    ~H"""
    <%= if @show_create_channel_form do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/50" phx-click="hide_create_channel"></div>
        <div class="relative bg-gray-800 rounded-xl shadow-xl p-6 max-w-md w-full mx-4 border border-cyan-500/50">
          <h3 class="text-xl font-bold text-white mb-4"><%= if @creating_user_channel, do: "Create Private Channel", else: "Create Channel" %></h3>

          <.form for={@channel_form} phx-submit={if @creating_user_channel, do: "create_user_channel", else: "create_channel"} phx-change="validate_channel" class="space-y-3">
            <div>
              <.input field={@channel_form[:name]} label="Name" class="w-full mt-1 p-2 rounded bg-gray-900 text-white" />
            </div>

            <div>
              <.input field={@channel_form[:description]} type="textarea" label="Description (optional)" class="w-full mt-1 p-2 rounded bg-gray-900 text-white" rows="3" />
            </div>

            <div class="flex items-center gap-3">
              <.input field={@channel_form[:is_private]} type="checkbox" label="Private channel (only invited/members can view)" />
            </div>

            <div class="flex justify-end gap-3 mt-4">
              <button phx-click="hide_create_channel" type="button" class="px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded">Cancel</button>
              <button type="submit" class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded">Create</button>
            </div>
          </.form>

        </div>
      </div>
    <% end %>
    <%= if @show_delete_channel_confirm do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/50" phx-click="cancel_delete_channel"></div>
        <div class="relative bg-gray-800 rounded-xl shadow-xl p-6 max-w-md w-full mx-4 border border-red-500/50">
          <div class="flex items-start mb-4">
            <div class="flex-shrink-0">
              <svg class="h-10 w-10 text-red-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
            </div>
            <div class="ml-4">
              <h3 class="text-lg font-medium text-white mb-2">Delete Channel</h3>
              <p class="text-gray-300 text-sm mb-4">
                Are you sure you want to delete <span class="font-bold text-white">#<%= @current_channel.name %></span>?
              </p>
              <p class="text-red-400 text-sm font-medium">
                ⚠️ This will permanently delete:
              </p>
              <ul class="text-gray-300 text-sm mt-2 ml-4 space-y-1">
                <li>• All messages in this channel</li>
                <li>• All uploaded files and attachments</li>
                <li>• All reactions and threads</li>
              </ul>
              <p class="text-red-400 text-sm font-bold mt-3">
                This action cannot be undone!
              </p>
            </div>
          </div>
          
          <div class="flex justify-end gap-3">
            <button 
              phx-click="cancel_delete_channel" 
              class="px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors"
            >
              Cancel
            </button>
            <button 
              phx-click="confirm_delete_channel" 
              class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded transition-colors font-medium"
            >
              Delete Permanently
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  Full-size view of an attachment.
  """
  attr :show_image_viewer, :any, required: true
  attr :viewer_image_filename, :any, required: true
  attr :viewer_image_url, :any, required: true
  def image_viewer(assigns) do
    ~H"""
    <%= if @show_image_viewer do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/90" phx-click="close_image_viewer"></div>
        <div class="relative max-w-7xl max-h-screen w-full h-full p-8 flex flex-col">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-white font-medium"><%= @viewer_image_filename %></h3>
            <div class="flex gap-2">
              <a href={@viewer_image_url} download={@viewer_image_filename} class="p-2 bg-gray-800 hover:bg-gray-700 rounded-lg transition-colors">
                <svg class="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1M4 4h16v8H4z" />
                </svg>
              </a>
              <button phx-click="close_image_viewer" class="p-2 bg-gray-800 hover:bg-gray-700 rounded-lg transition-colors">
                <svg class="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>
          <div class="flex-1 flex items-center justify-center overflow-hidden">
            <img src={@viewer_image_url} alt={@viewer_image_filename} class="max-w-full max-h-full object-contain" />
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  @doc """
  The invite dialog: invite a person, or make a shareable code.
  """
  attr :current_channel, :any, required: true
  attr :show_invite_modal, :any, required: true
  def invite_modal(assigns) do
    ~H"""
    <%= if @show_invite_modal do %>
      <div class="fixed inset-0 z-50 flex items-center justify-center pointer-events-auto">
        <div class="absolute inset-0 bg-black/50" phx-click="hide_invite_modal"></div>
        <div class="relative bg-gray-800 rounded-xl shadow-xl p-6 max-w-md w-full mx-4 border border-cyan-500/50">
          <h3 class="text-xl font-bold text-white mb-4">Invite Users to <%= @current_channel.name %></h3>
          <p class="text-gray-300 text-sm mb-4">Invite people by username/email or create a shareable invite code.</p>

          <div class="grid grid-cols-1 gap-4">
            <%!-- Personal invite form (username or email) --%>
            <div class="bg-gray-900 rounded p-3">
              <h4 class="text-sm font-semibold text-white mb-2">Invite a specific user</h4>
              <.form phx-submit="create_personal_invite" for={%{}} class="flex gap-2 items-center">
                <input name="invitee_id" placeholder="username or email" class="flex-1 p-2 rounded bg-gray-800 text-white text-sm" />
                <button type="submit" class="px-3 py-2 bg-indigo-600 hover:bg-indigo-700 text-white text-sm rounded">Invite</button>
              </.form>
            </div>

            <%!-- Channel invite code form (creates server-side invite) --%>
            <div class="bg-gray-900 rounded p-3">
              <h4 class="text-sm font-semibold text-white mb-2">Create invite code</h4>
              <.form phx-submit="create_channel_invite" for={%{}} class="space-y-2">
                <div class="flex gap-2">
                  <input name="max_uses" placeholder="Max uses (optional)" class="flex-1 p-2 rounded bg-gray-800 text-white text-sm" />
                  <input name="expires_at" type="datetime-local" class="p-2 rounded bg-gray-800 text-white text-sm" />
                </div>
                <div class="flex justify-end gap-2">
                  <button type="submit" class="px-3 py-2 bg-cyan-600 hover:bg-cyan-700 text-white text-sm rounded">Create code</button>
                </div>
              </.form>
            </div>
          </div>
          <div class="flex justify-end gap-3">
            <button phx-click="hide_invite_modal" class="px-4 py-2 bg-gray-600 hover:bg-gray-500 text-white rounded transition-colors">
              Close
            </button>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp active_channel_class(channel, current_channel) do
    if channel.id == current_channel.id do
      "bg-blue-500 text-white"
    else
      "text-gray-600 dark:text-gray-400"
    end
  end
end
