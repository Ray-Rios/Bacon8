defmodule Bacon8.Scheduler.EngineTest do
  use Bacon8.DataCase

  alias Bacon8.Scheduler
  alias Bacon8.Scheduler.Engine

  describe "compute_schedule/1" do
    test "computes earliest start times honoring dependencies" do
      {:ok, project} = Scheduler.create_project(%{name: "Engine Test Project", start_date: DateTime.utc_now()})

      # Create tasks: A -> B -> C
      {:ok, a} = Scheduler.create_task(%{project_id: project.id, title: "Task A", duration_seconds: 3600})
      {:ok, b} = Scheduler.create_task(%{project_id: project.id, title: "Task B", duration_seconds: 7200})
      {:ok, c} = Scheduler.create_task(%{project_id: project.id, title: "Task C", duration_seconds: 1800})

      # B depends on A, C depends on B
      {:ok, _} = Scheduler.create_task_dependency(%{task_id: b.id, depends_on_task_id: a.id, lag_seconds: 0})
      {:ok, _} = Scheduler.create_task_dependency(%{task_id: c.id, depends_on_task_id: b.id, lag_seconds: 0})

      {:ok, schedule} = Engine.compute_schedule(project.id)

      a_times = schedule[a.id]
      b_times = schedule[b.id]
      c_times = schedule[c.id]

      assert a_times.earliest_start_at
      assert a_times.earliest_finish_at

      assert DateTime.compare(b_times.earliest_start_at, a_times.earliest_finish_at) in [:gt, :eq]
      assert DateTime.compare(c_times.earliest_start_at, b_times.earliest_finish_at) in [:gt, :eq]
    end
  end
end
