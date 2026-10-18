defmodule Bacon8Web.Components.EmojiPickerComponent do
  @moduledoc """
  Shared emoji picker component for message input and reactions.
  Includes built-in emojis organized by category plus custom emojis.
  """
  use Bacon8Web, :live_component

  alias Bacon8.Forum

  # Comprehensive emoji list organized by category
  @emoji_categories %{
    "Smileys" => ~w(😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🤫 🤔 🤐 🤨 😐 😑 😶 😏 😒 🙄 😬 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 🤯 🤠 🥳 🥸 😎 🤓 🧐),
    "Emotions" => ~w(😕 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖),
    "Gestures" => ~w(👋 🤚 🖐️ ✋ 🖖 👌 🤌 🤏 ✌️ 🤞 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪),
    "Hearts" => ~w(❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟),
    "Animals" => ~w(🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐻‍❄️ 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🐝 🪱 🐛 🦋 🐌 🐞 🐜 🪰 🪲 🪳 🦟 🦗 🕷️ 🦂 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🐊 🐅 🐆 🦓 🦍 🦧 🦣 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🦬 🐃 🐂 🐄 🐎 🐖 🐏 🐑 🦙 🐐 🦌 🐕 🐩 🦮 🐕‍🦺 🐈 🐈‍⬛ 🪶 🐓 🦃 🦤 🦚 🦜 🦢 🦩 🕊️ 🐇 🦝 🦨 🦡 🦫 🦦 🦥 🐁 🐀 🐿️ 🦔),
    "Food" => ~w(🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 🧄 🧅 🥔 🍠 🥐 🥯 🍞 🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🦴 🌭 🍔 🍟 🍕 🫓 🥪 🥙 🧆 🌮 🌯 🫔 🥗 🥘 🫕 🥫 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🦪 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🍯 🥛 🍼 🫖 ☕ 🍵 🧃 🥤 🧋 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧉 🍾 🧊 🥄 🍴 🍽️ 🥣 🥡 🥢 🧂),
    "Activities" => ~w(⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🪃 🥅 ⛳ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸️ 🥌 🎿 ⛷️ 🏂 🪂 🏋️ 🤼 🤸 ⛹️ 🤺 🤾 🏌️ 🏇 ⛑️ 🧘 🏄 🏊 🤽 🚣 🧗 🚴 🚵 🎖️ 🏆 🥇 🥈 🥉 🏅 🎪 🤹 🎭 🩰 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🪘 🎷 🎺 🎸 🪕 🎻 🎲 ♟️ 🎯 🎳 🎮 🎰 🧩),
    "Travel" => ~w(🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🦯 🦽 🦼 🛴 🚲 🛵 🏍️ 🛺 🚨 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓ 🪝 ⛽ 🚧 🚦 🚥 🚏 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 ⛲ ⛱️ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺ 🛖 🏠 🏡 🏘️ 🏚️ 🏗️ 🏭 🏢 🏬 🏣 🏤 🏥 🏦 🏨 🏪 🏫 🏩 💒 🏛️ ⛪ 🕌 🕍 🛕 🕋 ⛩️ 🛤️ 🛣️ 🗾 🎑 🏞️ 🌅 🌄 🌠 🎇 🎆 🌇 🌆 🏙️ 🌃 🌌 🌉 🌁),
    "Objects" => ~w(⌚ 📱 📲 💻 ⌨️ 🖥️ 🖨️ 🖱️ 🖲️ 🕹️ 🗜️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 🎞️ 📞 ☎️ 📟 📠 📺 📻 🎙️ 🎚️ 🎛️ 🧭 ⏱️ ⏲️ ⏰ 🕰️ ⌛ ⏳ 📡 🔋 🔌 💡 🔦 🕯️ 🪔 🧯 🛢️ 💸 💵 💴 💶 💷 🪙 💰 💳 💎 ⚖️ 🪜 🧰 🪛 🔧 🔨 ⚒️ 🛠️ ⛏️ 🪚 🔩 ⚙️ 🪤 🧱 ⛓️ 🧲 🔫 💣 🧨 🪓 🔪 🗡️ ⚔️ 🛡️ 🚬 ⚰️ 🪦 ⚱️ 🏺 🔮 📿 🧿 💈 ⚗️ 🔭 🔬 🕳️ 🩹 🩺 💊 💉 🩸 🧬 🦠 🧫 🧪 🌡️ 🧹 🪠 🧺 🧻 🚽 🚰 🚿 🛁 🛀 🧼 🪥 🪒 🧽 🪣 🧴 🛎️ 🔑 🗝️ 🚪 🪑 🛋️ 🛏️ 🛌 🧸 🪆 🖼️ 🪞 🪟 🛍️ 🛒 🎁 🎈 🎏 🎀 🪄 🪅 🎊 🎉 🎎 🏮 🎐 🧧 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷️ 📪 📫 📬 📭 📮 📯 📜 📃 📄 📑 🧾 📊 📈 📉 🗒️ 🗓️ 📆 📅 🗑️ 📇 🗃️ 🗳️ 🗄️ 📋 📁 📂 🗂️ 🗞️ 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🧷 🔗 📎 🖇️ 📐 📏 🧮 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓),
    "Symbols" => ~w(❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ☦️ 🛐 ⛎ ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓ 🆔 ⚛️ 🉑 ☢️ ☣️ 📴 📳 🈶 🈚 🈸 🈺 🈷️ ✴️ 🆚 💮 🉐 ㊙️ ㊗️ 🈴 🈵 🈹 🈲 🅰️ 🅱️ 🆎 🆑 🅾️ 🆘 ❌ ⭕ 🛑 ⛔ 📛 🚫 💯 💢 ♨️ 🚷 🚯 🚳 🚱 🔞 📵 🚭 ❗ ❕ ❓ ❔ ‼️ ⁉️ 🔅 🔆 〽️ ⚠️ 🚸 🔱 ⚜️ 🔰 ♻️ ✅ 🈯 💹 ❇️ ✳️ ❎ 🌐 💠 Ⓜ️ 🌀 💤 🏧 🚾 ♿ 🅿️ 🛗 🈳 🈂️ 🛂 🛃 🛄 🛅 🚹 🚺 🚼 ⚧ 🚻 🚮 🎦 📶 🈁 🔣 ℹ️ 🔤 🔡 🔠 🆖 🆗 🆙 🆒 🆕 🆓 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 🔢 #️⃣ *️⃣ ⏏️ ▶️ ⏸️ ⏯️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ ⏫ ⏬ ◀️ 🔼 🔽 ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ↪️ ↩️ ⤴️ ⤵️ 🔀 🔁 🔂 🔄 🔃 🎵 🎶 ➕ ➖ ➗ ✖️ ♾️ 💲 💱 ™️ ©️ ®️ 〰️ ➰ ➿ 🔚 🔙 🔛 🔝 🔜 ✔️ ☑️ 🔘 🔴 🟠 🟡 🟢 🔵 🟣 ⚫ ⚪ 🟤 🔺 🔻 🔸 🔹 🔶 🔷 🔳 🔲 ▪️ ▫️ ◾ ◽ ◼️ ◻️ 🟥 🟧 🟨 🟩 🟦 🟪 ⬛ ⬜ 🟫 🔈 🔇 🔉 🔊 🔔 🔕 📣 📢 💬 💭 🗯️ ♠️ ♣️ ♥️ ♦️ 🃏 🎴 🀄 🕐 🕑 🕒 🕓 🕔 🕕 🕖 🕗 🕘 🕙 🕚 🕛 🕜 🕝 🕞 🕟 🕠 🕡 🕢 🕣 🕤 🕥 🕦 🕧),
    "Flags" => ~w(🏳️ 🏴 🏴‍☠️ 🏁 🚩 🎌 🏳️‍🌈 🏳️‍⚧️)
  }

  @impl true
  def mount(socket) do
    custom_emojis = Forum.list_custom_emojis()
    
    {:ok, assign(socket, 
      custom_emojis: custom_emojis,
      emoji_categories: @emoji_categories,
      active_category: "Smileys",
      search_query: ""
    )}
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    
    # Refresh custom emojis if needed
    custom_emojis = Forum.list_custom_emojis()
    
    {:ok, assign(socket, custom_emojis: custom_emojis)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="relative inline-block" id={@id}>
      <button 
        type="button" 
        phx-click={Phoenix.LiveView.JS.toggle(to: "##{@id}-dropdown", in: "fade-in-scale", out: "fade-out-scale")}
        class="text-gray-500 hover:text-yellow-500 p-1 rounded transition-colors"
        title="Emoji picker"
      >
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
        </svg>
      </button>
      
      <div 
        id={"#{@id}-dropdown"}
        class="hidden absolute bottom-full right-0 mb-2 w-80 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-xl z-50"
      >
        <%!-- Search --%>
        <div class="p-2 border-b border-gray-200 dark:border-gray-700">
          <input 
            type="text" 
            placeholder="Search emojis..." 
            class="w-full px-3 py-1.5 text-sm bg-gray-100 dark:bg-gray-700 border-0 rounded focus:ring-2 focus:ring-blue-500"
            phx-keyup="search_emoji"
            phx-target={@myself}
            value={@search_query}
          />
        </div>
        
        <%!-- Category Tabs --%>
        <div class="flex border-b border-gray-200 dark:border-gray-700 overflow-x-auto px-1">
          <%= if length(@custom_emojis) > 0 do %>
            <button 
              type="button"
              phx-click="select_category"
              phx-value-category="Custom"
              phx-target={@myself}
              class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Custom", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
              title="Custom"
            >
              ⭐
            </button>
          <% end %>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Smileys"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Smileys", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Smileys"
          >
            😀
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Emotions"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Emotions", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Emotions"
          >
            😢
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Gestures"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Gestures", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Gestures"
          >
            👋
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Hearts"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Hearts", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Hearts"
          >
            ❤️
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Animals"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Animals", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Animals"
          >
            🐶
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Food"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Food", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Food"
          >
            🍕
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Activities"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Activities", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Activities"
          >
            ⚽
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Travel"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Travel", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Travel"
          >
            🚗
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Objects"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Objects", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Objects"
          >
            💡
          </button>
          <button 
            type="button"
            phx-click="select_category"
            phx-value-category="Symbols"
            phx-target={@myself}
            class={"px-2 py-1.5 text-lg hover:bg-gray-100 dark:hover:bg-gray-700 rounded-t #{if @active_category == "Symbols", do: "bg-gray-100 dark:bg-gray-700", else: ""}"}
            title="Symbols"
          >
            ✨
          </button>
        </div>
        
        <%!-- Emoji Grid --%>
        <div class="p-2 grid grid-cols-8 gap-1 max-h-48 overflow-y-auto">
          <%= if @search_query != "" do %>
            <%!-- Search results --%>
            <%= for emoji <- search_emojis(@emoji_categories, @search_query) do %>
              <button 
                type="button" 
                class="text-xl hover:bg-gray-100 dark:hover:bg-gray-700 p-1 rounded aspect-square flex items-center justify-center"
                phx-click="select_emoji"
                phx-value-emoji={emoji}
                phx-target={@myself}
              >
                <%= emoji %>
              </button>
            <% end %>
          <% else %>
            <%!-- Category emojis --%>
            <%= if @active_category == "Custom" do %>
              <%= for emoji <- @custom_emojis do %>
                <%= if emoji.image_url do %>
                  <button 
                    type="button" 
                    class="hover:bg-gray-100 dark:hover:bg-gray-700 p-1 rounded aspect-square flex items-center justify-center"
                    phx-click="select_emoji"
                    phx-value-emoji={":#{emoji.shortcode}:"}
                    phx-value-image_url={emoji.image_url}
                    phx-target={@myself}
                    title={":#{emoji.shortcode}:"}
                  >
                    <img src={emoji.image_url} class="w-6 h-6 object-contain" alt={emoji.shortcode} />
                  </button>
                <% else %>
                  <button 
                    type="button" 
                    class="text-xl hover:bg-gray-100 dark:hover:bg-gray-700 p-1 rounded aspect-square flex items-center justify-center"
                    phx-click="select_emoji"
                    phx-value-emoji={emoji.emoji}
                    phx-target={@myself}
                    title={":#{emoji.shortcode}:"}
                  >
                    <%= emoji.emoji %>
                  </button>
                <% end %>
              <% end %>
            <% else %>
              <%= for emoji <- Map.get(@emoji_categories, @active_category, []) do %>
                <button 
                  type="button" 
                  class="text-xl hover:bg-gray-100 dark:hover:bg-gray-700 p-1 rounded aspect-square flex items-center justify-center"
                  phx-click="select_emoji"
                  phx-value-emoji={emoji}
                  phx-target={@myself}
                >
                  <%= emoji %>
                </button>
              <% end %>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search_emoji", %{"value" => query}, socket) do
    {:noreply, assign(socket, search_query: query)}
  end

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    {:noreply, assign(socket, active_category: category, search_query: "")}
  end

  @impl true
  def handle_event("select_emoji", %{"emoji" => emoji} = params, socket) do
    # Send emoji to parent based on mode
    case socket.assigns[:mode] do
      "reaction" ->
        # For reactions, send to parent to handle
        send(self(), {:add_reaction, socket.assigns.message_id, emoji})
      
      _ ->
        # For text input, dispatch JS event
        image_url = Map.get(params, "image_url")
        if image_url do
          # Custom image emoji - insert shortcode
          send(self(), {:insert_emoji, emoji})
        else
          send(self(), {:insert_emoji, emoji})
        end
    end
    
    {:noreply, socket}
  end

  # Helper to search emojis across all categories
  defp search_emojis(categories, query) do
    query = String.downcase(query)
    
    categories
    |> Enum.flat_map(fn {_category, emojis} -> emojis end)
    |> Enum.filter(fn emoji -> 
      # Simple search - match on emoji itself
      String.contains?(emoji, query)
    end)
    |> Enum.take(32)
  end
end
