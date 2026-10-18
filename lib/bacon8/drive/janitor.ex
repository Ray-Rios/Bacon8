defmodule Bacon8.Drive.Janitor do
  @moduledoc """
  Hourly drive maintenance:

    1. `Bacon8.Drive.purge_due/0` - deletes files of users whose Guest/Banned
       30-day hold has expired.
    2. `Bacon8.Drive.gc_blobs/2` - deletes bodies no file references.

  Every node runs this process, but each pass first takes a Postgres advisory
  lock, so only one node does the work at a time.

  Disable with `config :bacon8, Bacon8.Drive.Janitor, enabled: false`
  (the test config does).
  """
  use GenServer
  require Logger

  # Arbitrary constant identifying this job's advisory lock.
  @lock_key 7_211_015_001

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Runs one pass now (e.g. from a remote console). Returns a summary."
  def run_now, do: GenServer.call(__MODULE__, :run, :timer.minutes(10))

  @impl true
  def init(opts) do
    conf = Application.get_env(:bacon8, __MODULE__, [])

    if Keyword.get(conf, :enabled, true) do
      interval = Keyword.get(opts, :interval_ms, Keyword.get(conf, :interval_ms, :timer.hours(1)))
      # First pass a few minutes after boot, not during it.
      Process.send_after(self(), :tick, Keyword.get(conf, :initial_delay_ms, :timer.minutes(5)))
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
          purged = Bacon8.Drive.purge_due()
          blobs = gc_all()
          if purged != [] or blobs > 0,
            do: Logger.info("Drive janitor: purged #{length(purged)} drive(s), removed #{blobs} blob(s)")

          %{purged_users: purged, blobs_removed: blobs}
        after
          Bacon8.Repo.query!("SELECT pg_advisory_unlock($1)", [@lock_key])
        end
      else
        :another_node_is_running
      end
    end)
  rescue
    e ->
      Logger.error("Drive janitor failed: " <> Exception.format(:error, e, __STACKTRACE__))
      {:error, e}
  end

  # GC in batches until a batch comes back short.
  defp gc_all(total \\ 0) do
    n = Bacon8.Drive.gc_blobs(3600, 500)
    if n == 500, do: gc_all(total + n), else: total + n
  end
end
