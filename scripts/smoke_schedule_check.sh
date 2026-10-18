#!/usr/bin/env bash
set -euo pipefail

# This runs a small script inside the cluster that creates a test project and triggers the scheduler compute
POD=$(kubectl get pods -n bacon8 -l app=bacon8-web -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n bacon8 $POD -- /app/bin/bacon8 eval '
{:ok, _} = Application.ensure_all_started(:bacon8)
alias Bacon8.Scheduler
alias Bacon8.Scheduler.Engine
start = DateTime.utc_now()
{:ok, project} = Scheduler.create_project(%{name: "engine-smoke-$(System.os_time())", start_date: start})
{:ok, a} = Scheduler.create_task(%{project_id: project.id, title: "A", duration_seconds: 3600})
{:ok, b} = Scheduler.create_task(%{project_id: project.id, title: "B", duration_seconds: 7200})
{:ok, _} = Scheduler.create_task_dependency(%{task_id: b.id, depends_on_task_id: a.id})
res = Engine.compute_schedule(project.id)
IO.inspect(res)
'
