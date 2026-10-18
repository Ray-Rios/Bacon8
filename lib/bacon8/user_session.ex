defmodule Bacon8.UserSession do
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def put_user(session_id, user) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, session_id, user)
    end)
  end

  def get_user(session_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state, session_id)
    end)
  end

  def remove_user(session_id) do
    Agent.update(__MODULE__, fn state ->
      Map.delete(state, session_id)
    end)
  end
end