defmodule BaconWorld.Mobs.Keeper do
  @moduledoc """
  Runs on every node (a plugin child) and makes sure one `BaconWorld.Mobs.Zone`
  runs in the cluster: it starts it, linked, if nobody has; otherwise it watches
  the one that runs elsewhere and tries again when that one goes away (its node
  stopped, or it crashed). A crash of a zone it started takes the keeper down too,
  and the plugin's supervisor restarts both.
  """
  use GenServer

  alias BaconWorld.Mobs.Zone

  def start_link(slug), do: GenServer.start_link(__MODULE__, slug)

  def child_spec(slug), do: %{id: {__MODULE__, slug}, start: {__MODULE__, :start_link, [slug]}}

  @impl true
  def init(slug) do
    send(self(), :ensure)
    {:ok, %{slug: slug, ref: nil}}
  end

  @impl true
  def handle_info(:ensure, state) do
    case Zone.start_link(state.slug) do
      {:ok, _pid} ->
        {:noreply, %{state | ref: nil}}

      {:error, {:already_started, pid}} ->
        {:noreply, %{state | ref: Process.monitor(pid)}}

      {:error, _reason} ->
        Process.send_after(self(), :ensure, 5_000)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{ref: ref} = state) do
    # Several nodes may race for it; :global lets exactly one win.
    Process.send_after(self(), :ensure, Enum.random(100..1_500))
    {:noreply, %{state | ref: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
