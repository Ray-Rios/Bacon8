defmodule BaconStore.Store.Sweeper do
  @moduledoc """
  Store maintenance every 5 minutes:

    1. `BaconStore.Store.Fulfilment.expire/1` - ends passes and timed items
       whose time is up (a channel pass's membership goes with it).
    2. `BaconStore.Store.cancel_stale/2` - cancels card orders left unpaid for
       48 hours, returning reserved license keys to the pool.

  Every node runs this process; each pass takes a Postgres advisory lock so
  only one node does the work. Disable with
  `config :bacon8, BaconStore.Store.Sweeper, enabled: false` (the test config does).
  """
  use GenServer
  require Logger

  # Arbitrary constant identifying this job's advisory lock.
  @lock_key 7_211_015_002

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Runs one pass now. Returns a summary."
  def run_now, do: GenServer.call(__MODULE__, :run, :timer.minutes(5))

  @impl true
  def init(opts) do
    conf = Application.get_env(:bacon8, __MODULE__, [])

    if Keyword.get(conf, :enabled, true) do
      interval = Keyword.get(opts, :interval_ms, Keyword.get(conf, :interval_ms, :timer.minutes(5)))
      Process.send_after(self(), :tick, Keyword.get(conf, :initial_delay_ms, :timer.minutes(1)))
      {:ok, %{interval: interval}}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:tick, state) do
    run()
    Process.send_after(self(), :tick, state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:run, _from, state), do: {:reply, run(), state}

  defp run do
    Bacon8.Repo.checkout(fn ->
      %{rows: [[locked?]]} = Bacon8.Repo.query!("SELECT pg_try_advisory_lock($1)", [@lock_key])

      if locked? do
        try do
          expired = BaconStore.Store.Fulfilment.expire()
          cancelled = BaconStore.Store.cancel_stale()

          if expired > 0 or cancelled > 0,
            do: Logger.info("Store sweeper: #{expired} grant(s) ended, #{cancelled} stale order(s) cancelled")

          %{expired: expired, cancelled: cancelled}
        after
          Bacon8.Repo.query!("SELECT pg_advisory_unlock($1)", [@lock_key])
        end
      else
        :another_node_is_running
      end
    end)
  rescue
    e ->
      Logger.error("Store sweeper failed: " <> Exception.format(:error, e, __STACKTRACE__))
      {:error, e}
  end
end
