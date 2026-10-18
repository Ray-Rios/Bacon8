defmodule Bacon8Web.CollaborativeEditorChannel do
  @moduledoc """
  Phoenix Channel for real-time collaborative editing using Y.js CRDT.
  
  This channel handles:
  - Document synchronization via Y.js updates
  - Presence tracking (who's editing)
  - Cursor positions and selections
  - User awareness (names, colors)
  """
  
  use Bacon8Web, :channel
  alias Bacon8.Accounts

  @impl true
  def join("collab:" <> document_id, %{"user_id" => user_id} = _payload, socket) do
    # Verify user has access to this document
    # For now, we'll allow any authenticated user
    # TODO: Add permission checking based on document type (blog post, page, etc.)
    
    user = Accounts.get_user!(user_id)
    
    # Track presence
    send(self(), {:after_join, document_id})
    
    socket = 
      socket
      |> assign(:document_id, document_id)
      |> assign(:user, user)
      |> assign(:user_id, user_id)
    
    {:ok, %{document_id: document_id}, socket}
  end

  @impl true
  def join("collab:" <> _document_id, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_info({:after_join, _document_id}, socket) do
    # Track user presence
    {:ok, _} = Bacon8Web.Presence.track(
      socket,
      socket.assigns.user_id,
      %{
        user_id: socket.assigns.user_id,
        name: socket.assigns.user.name || socket.assigns.user.email,
        email: socket.assigns.user.email,
        avatar_url: socket.assigns.user.avatar_url,
        avatar_color: socket.assigns.user.avatar_color || "#3B82F6",
        online_at: System.system_time(:second)
      }
    )
    
    # Send current presence list to the user
    push(socket, "presence_state", Bacon8Web.Presence.list(socket))
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(%{event: "presence_diff", payload: diff}, socket) do
    # Notify client of presence changes (users joining/leaving)
    push(socket, "presence_diff", diff)
    {:noreply, socket}
  end

  @impl true
  def handle_in("sync_step1", %{"vector" => vector}, socket) do
    # Y.js sync step 1: Client sends state vector, server responds with missing updates
    document_id = socket.assigns.document_id
    
    # Get missing updates from persistent storage
    # For now, we'll use ETS/Redis for ephemeral storage
    missing_updates = get_missing_updates(document_id, vector)
    
    {:reply, {:ok, %{updates: missing_updates}}, socket}
  end

  @impl true
  def handle_in("sync_step2", %{"update" => update}, socket) do
    # Y.js sync step 2: Client sends an update, server broadcasts to other clients
    document_id = socket.assigns.document_id
    user_id = socket.assigns.user_id
    
    # Store update for persistence and sync
    store_update(document_id, update)
    
    # Broadcast to all other users editing this document (except sender)
    broadcast_from(socket, "sync_update", %{
      update: update,
      user_id: user_id
    })
    
    {:noreply, socket}
  end

  @impl true
  def handle_in("awareness", %{"state" => awareness_state}, socket) do
    # Y.js awareness: Track cursor position, selection, and user state
    user_id = socket.assigns.user_id
    
    # Broadcast awareness to all users
    broadcast(socket, "awareness_update", %{
      user_id: user_id,
      state: awareness_state
    })
    
    {:noreply, socket}
  end

  @impl true
  def handle_in("cursor", %{"position" => position, "selection" => selection}, socket) do
    # Track cursor position and text selection for live cursor indicators
    user_id = socket.assigns.user_id
    user = socket.assigns.user
    
    broadcast_from(socket, "cursor_update", %{
      user_id: user_id,
      name: user.name || user.email,
      color: user.avatar_color || "#3B82F6",
      position: position,
      selection: selection
    })
    
    {:noreply, socket}
  end

  @impl true
  def handle_in("typing", _payload, socket) do
    # Broadcast typing indicator
    user_id = socket.assigns.user_id
    user = socket.assigns.user
    
    broadcast_from(socket, "user_typing", %{
      user_id: user_id,
      name: user.name || user.email
    })
    
    {:noreply, socket}
  end

  # Private helper functions

  defp get_missing_updates(document_id, _vector) do
    # TODO: Implement persistent storage (PostgreSQL or Redis)
    # For now, return empty - full sync on join
    case :ets.lookup(:yjs_documents, document_id) do
      [{^document_id, updates}] -> updates
      [] -> []
    end
  end

  defp store_update(document_id, update) do
    # TODO: Implement persistent storage
    # Store in ETS for ephemeral session storage
    :ets.insert(:yjs_documents, {document_id, update})
    
    # TODO: Periodically persist to PostgreSQL for long-term storage
    # Store as binary blob with timestamp
  end
end
