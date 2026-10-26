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
end
