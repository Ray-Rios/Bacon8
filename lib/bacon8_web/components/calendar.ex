defmodule Bacon8Web.Components.Calendar do
  use Bacon8Web, :html

  attr :show, :boolean, default: false
  attr :target, :any, default: nil

  def calendar_popup(assigns) do
    ~H"""
    <%= if @show do %>
      <div 
        class="fixed bottom-14 right-4 w-80 glass-menu rounded-lg shadow-2xl overflow-hidden z-50 animate-slide-up p-4"
      >
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-white font-semibold text-lg">
            <%= Calendar.strftime(DateTime.utc_now(), "%B %Y") %>
          </h3>
          <div class="flex space-x-2">
            <button class="text-gray-400 hover:text-white">←</button>
            <button class="text-gray-400 hover:text-white">→</button>
          </div>
        </div>

        <div class="grid grid-cols-7 gap-1 text-center text-sm mb-2">
          <div class="text-gray-500 font-medium">Su</div>
          <div class="text-gray-500 font-medium">Mo</div>
          <div class="text-gray-500 font-medium">Tu</div>
          <div class="text-gray-500 font-medium">We</div>
          <div class="text-gray-500 font-medium">Th</div>
          <div class="text-gray-500 font-medium">Fr</div>
          <div class="text-gray-500 font-medium">Sa</div>
        </div>

        <div class="grid grid-cols-7 gap-1 text-center text-sm">
          <!-- Placeholder calendar days -->
          <%= for _ <- 1..3 do %>
            <div class="p-2 text-gray-600"></div>
          <% end %>
          
          <%= for day <- 1..30 do %>
            <div class={"p-2 rounded hover:bg-gray-700 cursor-pointer " <> if(day == DateTime.utc_now().day, do: "bg-blue-600 text-white font-bold", else: "text-gray-300")}>
              <%= day %>
            </div>
          <% end %>
        </div>
        
        <div class="mt-4 pt-4 border-t border-gray-600">
          <div class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">Upcoming Events</div>
          <div class="space-y-2">
            <div class="text-sm text-gray-400 italic">No events scheduled</div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
