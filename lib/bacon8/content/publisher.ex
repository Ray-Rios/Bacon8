defmodule Bacon8.Content.Publisher do
  @moduledoc """
  Publishes scheduled pages and posts when their time comes.

  A draft with a `scheduled_at` in the past is published (`Bacon8.Content.publish_due/0`) by the
  next pass, once a minute. Every node runs this process, but each pass first takes a Postgres
  advisory lock, so only one does the work at a time (and a record is published once either way:
  publishing clears `scheduled_at`).

  Disable with `config :bacon8, Bacon8.Content.Publisher, enabled: false` (the test config does).
  """
  use GenServer
  require Logger

  @lock_key 7_211_015_002

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    conf = Application.get_env(:bacon8, __MODULE__, [])

    if Keyword.get(conf, :enabled, true) do
      interval = Keyword.get(opts, :interval_ms, Keyword.get(conf, :interval_ms, :timer.minutes(1)))
      Process.send_after(self(), :tick, Keyword.get(conf, :initial_delay_ms, :timer.seconds(30)))
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

  defp run do
    Bacon8.Repo.checkout(fn ->
      %{rows: [[locked?]]} = Bacon8.Repo.query!("SELECT pg_try_advisory_lock($1)", [@lock_key])

      if locked? do
        try do
          case Bacon8.Content.publish_due() do
            0 -> :ok
            n -> Logger.info("Content publisher: published #{n} scheduled item(s)")
          end
        rescue
          e -> Logger.error("Content publisher failed: #{Exception.message(e)}")
        after
          Bacon8.Repo.query!("SELECT pg_advisory_unlock($1)", [@lock_key])
        end
      end
    end)
  end
end
