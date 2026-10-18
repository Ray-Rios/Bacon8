defmodule Bacon8Web.AdminLive.SQL do
  use Bacon8Web, :live_view
  alias Bacon8.Repo
  alias Bacon8Web.Components.AdminSidebar

  on_mount {Bacon8Web.UserAuth, :require_admin_user}

  def mount(_params, _session, socket) do
    # on_mount already verified admin access
    {:ok, assign(socket,
      query: "",
      results: nil,
      error: nil,
      history: [],
      tables: get_tables(),
      selected_table: nil,
      table_info: nil,
      saved_queries: get_saved_queries(),
      current_tab: "console",
      page_title: "SQL Management Console"
    )}
  end

  def handle_event("execute_query", %{"query" => query}, socket) do
    query = String.trim(query)
    
    if query == "" do
      {:noreply, socket}
    else
      case execute_safe_query(query) do
        {:ok, results} ->
          history = [%{query: query, results: results, timestamp: DateTime.utc_now()} | socket.assigns.history]
          |> Enum.take(20)
          
          {:noreply, assign(socket,
            results: results,
            error: nil,
            history: history
          )}
        
        {:error, error} ->
          {:noreply, assign(socket,
            results: nil,
            error: error
          )}
      end
    end
  end

  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, current_tab: tab)}
  end

  def handle_event("clear_results", _params, socket) do
    {:noreply, assign(socket, results: nil, error: nil)}
  end

  def handle_event("load_query", %{"query" => query}, socket) do
    {:noreply, assign(socket, query: query, current_tab: "console")}
  end

  def handle_event("inspect_table", %{"table" => table}, socket) do
    case get_table_info(table) do
      {:ok, table_info} ->
        {:noreply, assign(socket, 
          selected_table: table,
          table_info: table_info,
          current_tab: "schema"
        )}
      
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to inspect table: #{error}")}
    end
  end

  def handle_event("export_csv", _params, socket) do
    if socket.assigns.results do
      csv_data = results_to_csv(socket.assigns.results)
      {:noreply, push_event(socket, "download_csv", %{data: csv_data, filename: "query_results.csv"})}
    else
      {:noreply, put_flash(socket, :error, "No results to export")}
    end
  end

  def handle_event("save_query", %{"name" => name, "query" => query}, socket) do
    if String.trim(name) != "" and String.trim(query) != "" do
      # In a real app, you'd save this to the database
      saved_query = %{name: String.trim(name), query: String.trim(query), created_at: DateTime.utc_now()}
      saved_queries = [saved_query | socket.assigns.saved_queries] |> Enum.take(50)
      
      {:noreply, assign(socket, 
        saved_queries: saved_queries,
        current_tab: "saved"
      ) |> put_flash(:info, "Query saved successfully")}
    else
      {:noreply, put_flash(socket, :error, "Name and query cannot be empty")}
    end
  end

  defp get_tables do
    try do
      result = Ecto.Adapters.SQL.query!(Repo, """
        SELECT table_name, table_type 
        FROM information_schema.tables 
        WHERE table_schema = 'public' 
        ORDER BY table_name
      """, [])
      
      result.rows
      |> Enum.map(fn [name, type] -> %{name: name, type: type} end)
    rescue
      _ -> []
    end
  end

  defp get_table_info(table_name) do
    try do
      # Get columns info
      columns_result = Ecto.Adapters.SQL.query!(Repo, """
        SELECT column_name, data_type, is_nullable, column_default, character_maximum_length
        FROM information_schema.columns 
        WHERE table_name = $1 AND table_schema = 'public'
        ORDER BY ordinal_position
      """, [table_name])
      
      # Get indexes info
      indexes_result = Ecto.Adapters.SQL.query!(Repo, """
        SELECT indexname, indexdef
        FROM pg_indexes 
        WHERE tablename = $1 AND schemaname = 'public'
      """, [table_name])
      
      # Get constraints info
      constraints_result = Ecto.Adapters.SQL.query!(Repo, """
        SELECT constraint_name, constraint_type
        FROM information_schema.table_constraints 
        WHERE table_name = $1 AND table_schema = 'public'
      """, [table_name])
      
      # Get row count
      count_result = Ecto.Adapters.SQL.query!(Repo, "SELECT COUNT(*) FROM \"#{table_name}\"", [])
      row_count = count_result.rows |> List.first() |> List.first()
      
      table_info = %{
        columns: columns_result.rows |> Enum.map(fn [name, type, nullable, default, max_length] -> 
          %{name: name, type: type, nullable: nullable == "YES", default: default, max_length: max_length}
        end),
        indexes: indexes_result.rows |> Enum.map(fn [name, def] -> %{name: name, definition: def} end),
        constraints: constraints_result.rows |> Enum.map(fn [name, type] -> %{name: name, type: type} end),
        row_count: row_count
      }
      
      {:ok, table_info}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp get_saved_queries do
    # In a real app, you'd load these from the database
    [
      %{name: "User Stats", query: "SELECT COUNT(*) as total_users, COUNT(CASE WHEN is_admin THEN 1 END) as admins FROM users;", created_at: DateTime.utc_now()},
      %{name: "Recent Activity", query: "SELECT * FROM users ORDER BY last_activity DESC LIMIT 10;", created_at: DateTime.utc_now()}
    ]
  end

  defp results_to_csv(results) do
    header = Enum.join(results.columns, ",")
    rows = results.rows
    |> Enum.map(fn row -> 
      Enum.map(row, fn cell -> 
        case cell do
          nil -> ""
          value when is_binary(value) -> "\"#{String.replace(value, "\"", "\"\"")}\""
          value -> "\"#{inspect(value)}\""
        end
      end)
      |> Enum.join(",")
    end)
    
    ([header] ++ rows) |> Enum.join("\n")
  end

  defp execute_safe_query(query_string) do
    # Only allow SELECT queries for safety
    normalized_query = String.downcase(String.trim(query_string))
    
    cond do
      String.starts_with?(normalized_query, "select") ->
        try do
          result = Ecto.Adapters.SQL.query!(Repo, query_string, [])
          
          formatted_results = %{
            columns: result.columns,
            rows: result.rows,
            num_rows: result.num_rows
          }
          
          {:ok, formatted_results}
        rescue
          e -> {:error, Exception.message(e)}
        end
      
      String.starts_with?(normalized_query, "show") ->
        # Allow SHOW commands for PostgreSQL
        try do
          result = Ecto.Adapters.SQL.query!(Repo, query_string, [])
          
          formatted_results = %{
            columns: result.columns,
            rows: result.rows,
            num_rows: result.num_rows
          }
          
          {:ok, formatted_results}
        rescue
          e -> {:error, Exception.message(e)}
        end
      
      String.starts_with?(normalized_query, "describe") or String.starts_with?(normalized_query, "\\d") ->
        # Allow table descriptions
        try do
          result = Ecto.Adapters.SQL.query!(Repo, query_string, [])
          
          formatted_results = %{
            columns: result.columns,
            rows: result.rows,
            num_rows: result.num_rows
          }
          
          {:ok, formatted_results}
        rescue
          e -> {:error, Exception.message(e)}
        end
      
      true ->
        {:error, "Only SELECT, SHOW, and DESCRIBE queries are allowed for security reasons"}
    end
  end

  def render(assigns) do
    ~H"""
    <AdminSidebar.admin_layout current_path="/admin/sql">
      <div class="max-w-7xl mx-auto">
          <div class="flex justify-between items-center mb-8">
            <h1 class="text-3xl font-bold text-white">SQL Management Console</h1>
            <div class="text-sm text-gray-400">
              ⚠️ Only SELECT, SHOW, and DESCRIBE queries allowed
            </div>
          </div>
          
          <!-- Navigation Tabs -->
          <div class="glass-dark rounded-lg mb-6">
            <div class="border-b border-gray-700">
              <nav class="flex space-x-8 px-6">
                <button phx-click="change_tab" phx-value-tab="console"
                        class={"py-4 px-2 border-b-2 font-medium text-sm transition-colors " <>
                               if(@current_tab == "console", do: "border-blue-500 text-blue-400", else: "border-transparent text-gray-400 hover:text-gray-300")}>
                  🖥️ SQL Console
                </button>
                <button phx-click="change_tab" phx-value-tab="schema"
                        class={"py-4 px-2 border-b-2 font-medium text-sm transition-colors " <>
                               if(@current_tab == "schema", do: "border-blue-500 text-blue-400", else: "border-transparent text-gray-400 hover:text-gray-300")}>
                  🗂️ Database Schema
                </button>
                <button phx-click="change_tab" phx-value-tab="saved"
                        class={"py-4 px-2 border-b-2 font-medium text-sm transition-colors " <>
                               if(@current_tab == "saved", do: "border-blue-500 text-blue-400", else: "border-transparent text-gray-400 hover:text-gray-300")}>
                  💾 Saved Queries
                </button>
              </nav>
            </div>
            
            <div class="p-6">
              <%= case @current_tab do %>
                <% "console" -> %>
                  <!-- Query Input -->
                  <form phx-submit="execute_query">
                    <div class="mb-4">
                      <label class="block text-sm font-medium text-gray-300 mb-2">SQL Query</label>
                      <textarea name="query" rows="6" 
                                class="w-full bg-gray-900 text-white font-mono text-sm p-4 rounded border border-gray-600 focus:border-blue-500 focus:outline-none"
                                placeholder="SELECT * FROM users LIMIT 10;"
                                value={@query}></textarea>
                    </div>
                    
                    <div class="flex flex-wrap gap-4">
                      <button type="submit" 
                              class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded transition-colors">
                        Execute Query
                      </button>
                      <button type="button" phx-click="clear_results"
                              class="bg-gray-600 hover:bg-gray-700 text-white px-6 py-2 rounded transition-colors">
                        Clear Results
                      </button>
                      <%= if @results do %>
                        <button type="button" phx-click="export_csv"
                                class="bg-green-600 hover:bg-green-700 text-white px-6 py-2 rounded transition-colors">
                          Export CSV
                        </button>
                      <% end %>
                    </div>
                  </form>

                  <!-- Quick Query Templates -->
                  <div class="mt-6">
                    <h3 class="text-lg font-semibold text-gray-300 mb-3">Quick Queries</h3>
                    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                      <button phx-click="load_query" phx-value-query="SELECT * FROM users LIMIT 10;"
                              class="text-left bg-gray-700 hover:bg-gray-600 text-gray-300 p-3 rounded transition-colors">
                        <div class="font-mono text-sm">Show recent users</div>
                      </button>
                      <button phx-click="load_query" phx-value-query="SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;"
                              class="text-left bg-gray-700 hover:bg-gray-600 text-gray-300 p-3 rounded transition-colors">
                        <div class="font-mono text-sm">List all tables</div>
                      </button>
                      <button phx-click="load_query" phx-value-query="SELECT COUNT(*) FROM users;"
                              class="text-left bg-gray-700 hover:bg-gray-600 text-gray-300 p-3 rounded transition-colors">
                        <div class="font-mono text-sm">Count users</div>
                      </button>
                    </div>
                  </div>
                  
                <% "schema" -> %>
                  <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
                    <!-- Tables List -->
                    <div class="bg-gray-900 rounded-lg p-4">
                      <h3 class="text-lg font-semibold text-gray-300 mb-4">Database Tables</h3>
                      <div class="space-y-2 max-h-96 overflow-y-auto">
                        <%= for table <- @tables do %>
                          <button phx-click="inspect_table" phx-value-table={table.name}
                                  class={"w-full text-left p-3 rounded transition-colors " <>
                                         if(@selected_table == table.name, do: "bg-blue-600 text-white", else: "bg-gray-700 hover:bg-gray-600 text-gray-300")}>
                            <div class="font-mono text-sm"><%= table.name %></div>
                            <div class="text-xs opacity-75"><%= table.type %></div>
                          </button>
                        <% end %>
                      </div>
                    </div>

                    <!-- Table Details -->
                    <div class="lg:col-span-2">
                      <%= if @table_info do %>
                        <div class="bg-gray-900 rounded-lg p-4">
                          <div class="flex items-center justify-between mb-4">
                            <h3 class="text-lg font-semibold text-gray-300">
                              Table: <span class="font-mono text-blue-400"><%= @selected_table %></span>
                            </h3>
                            <div class="text-sm text-gray-400">
                              <%= @table_info.row_count %> rows
                            </div>
                          </div>
                          
                          <!-- Columns -->
                          <div class="mb-6">
                            <h4 class="font-medium text-gray-300 mb-3">Columns</h4>
                            <div class="overflow-x-auto">
                              <table class="w-full text-sm">
                                <thead>
                                  <tr class="border-b border-gray-700">
                                    <th class="text-left py-2 px-3 text-gray-400">Name</th>
                                    <th class="text-left py-2 px-3 text-gray-400">Type</th>
                                    <th class="text-left py-2 px-3 text-gray-400">Nullable</th>
                                    <th class="text-left py-2 px-3 text-gray-400">Default</th>
                                  </tr>
                                </thead>
                                <tbody>
                                  <%= for column <- @table_info.columns do %>
                                    <tr class="border-b border-gray-800">
                                      <td class="py-2 px-3 font-mono text-blue-400"><%= column.name %></td>
                                      <td class="py-2 px-3 text-gray-300"><%= column.type %></td>
                                      <td class="py-2 px-3 text-gray-300">
                                        <span class={"px-2 py-1 rounded text-xs " <>
                                                   if(column.nullable, do: "bg-yellow-900 text-yellow-300", else: "bg-red-900 text-red-300")}>
                                          <%= if column.nullable, do: "YES", else: "NO" %>
                                        </span>
                                      </td>
                                      <td class="py-2 px-3 text-gray-300 font-mono text-xs">
                                        <%= if column.default, do: column.default, else: "-" %>
                                      </td>
                                    </tr>
                                  <% end %>
                                </tbody>
                              </table>
                            </div>
                          </div>

                          <!-- Indexes -->
                          <%= if length(@table_info.indexes) > 0 do %>
                            <div class="mb-6">
                              <h4 class="font-medium text-gray-300 mb-3">Indexes</h4>
                              <div class="space-y-2">
                                <%= for index <- @table_info.indexes do %>
                                  <div class="glass-dark p-3 rounded">
                                    <div class="font-mono text-sm text-blue-400"><%= index.name %></div>
                                    <div class="text-xs text-gray-400 mt-1"><%= index.definition %></div>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                          <% end %>

                          <!-- Constraints -->
                          <%= if length(@table_info.constraints) > 0 do %>
                            <div>
                              <h4 class="font-medium text-gray-300 mb-3">Constraints</h4>
                              <div class="flex flex-wrap gap-2">
                                <%= for constraint <- @table_info.constraints do %>
                                  <div class="bg-purple-900 text-purple-300 px-3 py-1 rounded text-sm">
                                    <%= constraint.type %>: <%= constraint.name %>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                          <% end %>
                        </div>
                      <% else %>
                        <div class="bg-gray-900 rounded-lg p-8 text-center">
                          <div class="text-gray-500 text-lg mb-2">🗂️</div>
                          <div class="text-gray-400">Select a table to inspect its structure</div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                  
                <% "saved" -> %>
                  <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                    <!-- Save New Query -->
                    <div class="bg-gray-900 rounded-lg p-4">
                      <h3 class="text-lg font-semibold text-gray-300 mb-4">Save Current Query</h3>
                      <form phx-submit="save_query">
                        <div class="mb-4">
                          <label class="block text-sm font-medium text-gray-300 mb-2">Query Name</label>
                          <input type="text" name="name" required
                                 class="w-full glass-dark text-white p-3 rounded border border-gray-600 focus:border-blue-500 focus:outline-none"
                                 placeholder="My useful query">
                        </div>
                        <div class="mb-4">
                          <label class="block text-sm font-medium text-gray-300 mb-2">SQL Query</label>
                          <textarea name="query" rows="4" required
                                    class="w-full glass-dark text-white font-mono text-sm p-3 rounded border border-gray-600 focus:border-blue-500 focus:outline-none"
                                    value={@query}></textarea>
                        </div>
                        <button type="submit" 
                                class="w-full bg-green-600 hover:bg-green-700 text-white py-2 px-4 rounded transition-colors">
                          💾 Save Query
                        </button>
                      </form>
                    </div>

                    <!-- Saved Queries List -->
                    <div class="bg-gray-900 rounded-lg p-4">
                      <h3 class="text-lg font-semibold text-gray-300 mb-4">Saved Queries</h3>
                      <div class="space-y-3 max-h-96 overflow-y-auto">
                        <%= for query <- @saved_queries do %>
                          <div class="glass-dark rounded p-3">
                            <div class="flex items-center justify-between mb-2">
                              <h4 class="font-medium text-gray-300"><%= query.name %></h4>
                              <button phx-click="load_query" phx-value-query={query.query}
                                      class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded text-sm transition-colors">
                                Load
                              </button>
                            </div>
                            <div class="font-mono text-xs text-gray-400 bg-gray-900 p-2 rounded">
                              <%= String.slice(query.query, 0, 100) %><%= if String.length(query.query) > 100, do: "..." %>
                            </div>
                            <div class="text-xs text-gray-500 mt-2">
                              Created: <%= Calendar.strftime(query.created_at, "%Y-%m-%d %H:%M") %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
              <% end %>
            </div>
          </div>

          <!-- Results Display -->
          <%= if @error do %>
            <div class="bg-red-900/50 border border-red-500 rounded-lg p-4 mb-6">
              <div class="flex items-center">
                <div class="text-red-400 mr-2">❌</div>
                <div class="text-red-300">
                  <strong>Error:</strong> <%= @error %>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @results do %>
            <div class="glass-dark rounded-lg p-6 mb-6">
              <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-semibold text-gray-300">Query Results</h3>
                <div class="text-sm text-gray-400">
                  <%= @results.num_rows %> row(s)
                </div>
              </div>
              
              <%= if @results.num_rows > 0 do %>
                <div class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="border-b border-gray-700">
                        <%= for column <- @results.columns do %>
                          <th class="text-left py-3 px-4 font-medium text-gray-400">
                            <%= column %>
                          </th>
                        <% end %>
                      </tr>
                    </thead>
                    <tbody>
                      <%= for {row, index} <- Enum.with_index(@results.rows) do %>
                        <tr class={"border-b border-gray-800 " <> if(rem(index, 2) == 0, do: "bg-gray-900", else: "")}>
                          <%= for cell <- row do %>
                            <td class="py-2 px-4 text-gray-300 font-mono text-xs">
                              <%= if cell == nil do %>
                                <span class="text-gray-500 italic">NULL</span>
                              <% else %>
                                <%= inspect(cell) |> String.slice(0, 100) %>
                                <%= if String.length(inspect(cell)) > 100, do: "..." %>
                              <% end %>
                            </td>
                          <% end %>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% else %>
                <div class="text-center py-8 text-gray-400">
                  No results returned
                </div>
              <% end %>
            </div>
          <% end %>

          <!-- Query History -->
          <%= if length(@history) > 0 do %>
            <div class="glass-dark rounded-lg p-6">
              <h3 class="text-lg font-semibold text-gray-300 mb-4">Recent Queries</h3>
              <div class="space-y-3 max-h-64 overflow-y-auto">
                <%= for {query_item, _index} <- Enum.with_index(@history) do %>
                  <div class="bg-gray-900 rounded p-4">
                    <div class="flex items-center justify-between mb-2">
                      <span class="text-xs text-gray-500">
                        <%= Calendar.strftime(query_item.timestamp, "%H:%M:%S") %>
                      </span>
                      <button phx-click="load_query" phx-value-query={query_item.query}
                              class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded text-xs transition-colors">
                        Rerun
                      </button>
                    </div>
                    <div class="font-mono text-sm text-gray-300 mb-2">
                      <%= query_item.query %>
                    </div>
                    <div class="text-xs text-gray-500">
                      <%= query_item.results.num_rows %> row(s) returned
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </AdminSidebar.admin_layout>

    <script>
      window.addEventListener('phx:download_csv', (e) => {
        const { data, filename } = e.detail;
        const blob = new Blob([data], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        window.URL.revokeObjectURL(url);
      });
    </script>
    """
  end
end