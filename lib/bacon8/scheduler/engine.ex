defmodule Bacon8.Scheduler.Engine do
  @moduledoc """
  Scheduling engine that computes earliest start times (simple DAG/topological scheduling).
  This initial implementation supports finish-to-start dependencies with an optional lag (seconds).
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Scheduler.{Task, TaskDependency, Project}

  @doc """
  Compute and persist schedule for a project.

  Returns {:ok, %{task_id => %{earliest_start_at, earliest_finish_at}}} or {:error, reason}
  """
  def compute_schedule(project_id) do
    project = Repo.get!(Project, project_id)

    tasks = Repo.all(from t in Task, where: t.project_id == ^project_id)
    deps = Repo.all(from d in TaskDependency, where: d.task_id in ^Enum.map(tasks, & &1.id))

    task_map = Map.new(tasks, &{&1.id, &1})

    # Build adjacency and indegree maps (depends_on -> [task])
    adj = %{}
    indegree = %{}

    {adj, indegree} = Enum.reduce(deps, {adj, indegree}, fn dep, {a, indeg} ->
      a = Map.update(a, dep.depends_on_task_id, [dep], fn cur -> [dep | cur] end)
      indeg = Map.update(indeg, dep.task_id, 1, &(&1 + 1))
      {a, indeg}
    end)

    # Initialize queue with nodes that have indegree 0
    zero_indegree = tasks |> Enum.filter(fn t -> Map.get(indegree, t.id, 0) == 0 end) |> Enum.map(& &1.id)

    queue = :queue.from_list(zero_indegree)

    # Initialize schedule map
    schedule = %{}

    # For tasks without duration set, assume 1 hour by default
    default_duration = 3600

    # Use project start date if available as a baseline
    project_start = project.start_date || DateTime.utc_now()

    # initialize earliest_start for zero indegree nodes
    schedule = Enum.reduce(zero_indegree, schedule, fn id, acc ->
      t = Map.get(task_map, id)
      start_at = t.start_at || project_start
      finish_at = add_seconds(start_at, t.duration_seconds || default_duration)
      Map.put(acc, id, %{earliest_start_at: start_at, earliest_finish_at: finish_at})
    end)

    # Kahn's algorithm
    {final_schedule, processed_count} = process_queue(queue, adj, indegree, schedule, task_map, default_duration)

    if processed_count != length(tasks) do
      {:error, :cycle_detected}
    else
      # Persist schedule times back to tasks
      Enum.each(final_schedule, fn {task_id, times} ->
        t = Map.get(task_map, task_id)
        changeset = Ecto.Changeset.change(t, %{earliest_start_at: times.earliest_start_at, earliest_finish_at: times.earliest_finish_at})
        Repo.update!(changeset)
      end)

      {:ok, final_schedule}
    end
  end

  defp process_queue(queue, adj, indegree, schedule, task_map, default_duration, processed \\ 0) do
    case :queue.out(queue) do
      {:empty, _} -> {schedule, processed}
      {{:value, node}, q_tail} ->
        # for each neighbor (task depending on node), reduce indegree and update earliest start
        neighbors = Map.get(adj, node, [])

        {q_tail, schedule} = Enum.reduce(neighbors, {q_tail, schedule}, fn dep, {q_acc, sched} ->
          task_id = dep.task_id

          # predecessor finish time
          pred_finish = sched[node].earliest_finish_at
          candidate_start = add_seconds(pred_finish, dep.lag_seconds || 0)

          existing = Map.get(sched, task_id)

          {new_start, new_finish} =
            if existing do
              # take max of existing earliest start and candidate_start
              s = if DateTime.compare(candidate_start, existing.earliest_start_at) == :gt, do: candidate_start, else: existing.earliest_start_at
              finish = add_seconds(s, (task_map[task_id].duration_seconds || default_duration))
              {s, finish}
            else
              s = candidate_start
              finish = add_seconds(s, (task_map[task_id].duration_seconds || default_duration))
              {s, finish}
            end

          sched = Map.put(sched, task_id, %{earliest_start_at: new_start, earliest_finish_at: new_finish})

          indeg = Map.update!(indegree, task_id, &(&1 - 1))

          if Map.get(indeg, task_id) == 0 do
            { :queue.in(task_id, q_acc), sched }
          else
            { q_acc, sched }
          end
        end)

        process_queue(q_tail, adj, indegree, schedule, task_map, default_duration, processed + 1)
    end
  end

  defp add_seconds(%DateTime{} = dt, secs) when is_integer(secs) do
    DateTime.add(dt, secs, :second)
  end
  defp add_seconds(nil, secs), do: DateTime.add(DateTime.utc_now(), secs, :second)
end
