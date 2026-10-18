defmodule Bacon8Web.PageLive.Index do
  use Bacon8Web, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, 
      page_title: "Pages",
      pages: []
    )}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(page_title: "Pages")
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(page_title: "New Page")
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900">
      <!-- Navigation -->
      <nav class="bg-black bg-opacity-50 backdrop-blur-sm border-b border-gray-700">
        <div class="container mx-auto px-4">
          <div class="flex justify-between items-center h-16">
            <.link navigate={~p"/"} class="text-2xl font-bold text-white hover:text-blue-400 transition-colors duration-300">Alabama</.link>
            <.link navigate={~p"/games"} class="text-white hover:text-blue-400 transition-colors duration-300">Back to Games</.link>
          </div>
        </div>
      </nav>

      <!-- Page Builder -->
      <div class="container mx-auto px-4 py-8">
        <div class="max-w-6xl mx-auto">
          <h1 class="text-4xl font-bold text-white text-center mb-8">Page Builder</h1>
          
          <div class="bg-white bg-opacity-10 backdrop-blur-sm rounded-xl p-8">
            <div class="text-center text-white">
              <h2 class="text-2xl font-bold mb-4">Coming Soon!</h2>
              <p class="text-lg mb-6">The WYSIWYG page builder is under development.</p>
              <p class="text-gray-300 mb-8">This will include drag-and-drop functionality, template selection, and real-time editing.</p>
              
              <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mt-8">
                <div class="bg-white bg-opacity-10 rounded-lg p-6">
                  <h3 class="text-xl font-bold mb-3">Service Business Template</h3>
                  <ul class="text-left text-gray-300 space-y-2">
                    <li>• Home page with hero section</li>
                    <li>• About page with team info</li>
                    <li>• Services showcase</li>
                    <li>• Contact form</li>
                    <li>• Blog/News section</li>
                  </ul>
                </div>
                
                <div class="bg-white bg-opacity-10 rounded-lg p-6">
                  <h3 class="text-xl font-bold mb-3">Product Business Template</h3>
                  <ul class="text-left text-gray-300 space-y-2">
                    <li>• Product showcase homepage</li>
                    <li>• Product catalog</li>
                    <li>• Individual product pages</li>
                    <li>• Shopping cart integration</li>
                    <li>• Customer testimonials</li>
                  </ul>
                </div>
              </div>
              
              <.link navigate={~p"/games"} class="inline-block mt-8 bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg transition-colors duration-300">
                Back to World
              </.link>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end