defmodule Bacon8.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Create ETS tables for sessions and rate limiting
    :ets.new(:user_sessions, [:set, :public, :named_table])
    :ets.new(:rate_limit_table, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(:blocked_ips, [:set, :public, :named_table])
    :ets.new(:honeypot_tracker, [:set, :public, :named_table])
    
    # Create ETS table for Y.js collaborative editing documents
    :ets.new(:yjs_documents, [:set, :public, :named_table])
    
    # Configure PubSub - just use standard adapter, Redis bridging is handled separately
    pubsub_child = {Phoenix.PubSub, name: Bacon8.PubSub}

    # Get libcluster topologies
    topologies = Application.get_env(:libcluster, :topologies) || []

    children = [
      # Start the Cluster Supervisor
      {Cluster.Supervisor, [topologies, [name: Bacon8.ClusterSupervisor]]},
      # Log buffer must start early to capture startup logs
      Bacon8.LogBuffer,
      Bacon8.Repo,
      Bacon8.GamesRepo,
      pubsub_child,
      Bacon8Web.Presence,
      {Finch, name: Bacon8.Finch},
      # Task.Supervisor for async email sending
      {Task.Supervisor, name: Bacon8.EmailTaskSupervisor},
      Bacon8.UserSession,
      Bacon8.PresenceTracker,
      Bacon8.Accounts.RateLimit,
      Bacon8.RateLimiter,
      Bacon8.NotFoundTracker,
      # Scheduler Worker for cron-like event execution
      Bacon8.Scheduler.Worker,
      # Drive maintenance: 30-day purge + blob GC (BACON8.md §7)
      Bacon8.Drive.Janitor,
      # Publishes scheduled pages and posts when their time comes
      Bacon8.Content.Publisher,
      # Plugins (BACON8.md §9): active plugins' processes, kept in step with
      # /admin/plugins across the cluster by Plugins.Runtime.
      {DynamicSupervisor, name: Bacon8.PluginSupervisor, strategy: :one_for_one},
      Bacon8.Plugins.Runtime,
      Bacon8Web.Endpoint
    ] ++ redis_children()

    # Attach Email Logger
    Bacon8.EmailLogging.TelemetryHandler.attach()

    opts = [strategy: :one_for_one, name: Bacon8.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  defp redis_url do
    Application.get_env(:bacon8, :redis_url) || "redis://localhost:6379/0"
  end

  defp redis_children do
    enable_redis = Application.get_env(:bacon8, :enable_redis, false)
    
    if enable_redis do
      [
        # Redis connection for MMO scaling
        {Redix, {redis_url(), [name: :redix]}},
        %{
          id: Redix.PubSub,
          start: {Redix.PubSub, :start_link, [redis_url(), [name: :redix_pubsub]]}
        },
        # Start GenServer that listens for Redis pubsub messages and forwards into Phoenix.PubSub
        Bacon8.RedisPubSub
      ]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    Bacon8Web.Endpoint.config_change(changed, removed)
    :ok
  end
end