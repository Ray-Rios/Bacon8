defmodule FeedbackWeb.Admin.AgentLive do
  @moduledoc """
  /admin/feedback/agent - Claude's runner: make or revoke its token (shown once), let it deploy
  on its own or not, pause it, and see when it last called and what it is doing.
  """
  use Bacon8Web, :live_view

  import FeedbackWeb.Components

  on_mount({Bacon8Web.UserAuth, :require_admin_user})

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Bacon8.PubSub, Feedback.topic())
    {:ok, socket |> assign(page_title: "Claude runner", new_token: nil) |> load()}
  end

  defp load(socket) do
    counts = Feedback.counts()

    queue =
      Feedback.list_items(socket.assigns.current_user, group: "claude", sort: "new", limit: 50)

    assign(socket, agent: Feedback.agent(), counts: counts, queue: queue)
  end

  @impl true
  def handle_event("new_token", _, socket) do
    {:ok, token} = Feedback.new_agent_token(socket.assigns.current_user)
    {:noreply, socket |> assign(new_token: token) |> load()}
  end

  def handle_event("revoke", _, socket) do
    :ok = Feedback.revoke_agent_token(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(new_token: nil)
     |> put_flash(:info, "Token revoked: the runner can't call any more.")
     |> load()}
  end

  def handle_event("toggle", %{"setting" => s}, socket) when s in ["auto_deploy", "paused"] do
    current = Map.get(socket.assigns.agent, String.to_existing_atom(s))
    {:ok, _} = Feedback.update_agent(socket.assigns.current_user, %{s => !current})
    {:noreply, load(socket)}
  end

  @impl true
  def handle_info({:feedback, _, _}, socket), do: {:noreply, load(socket)}
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="fixed inset-x-0 top-[30px] bottom-[35px] z-30 overflow-y-auto bg-black">
      <div class="mx-auto max-w-4xl px-4 py-8 sm:px-6">
        <.link navigate="/feedback" class="text-sm text-gray-400 hover:text-white">← Suggestions &amp; Bugs</.link>
        <h1 class="mt-3 text-3xl font-bold text-white">🤖 Claude runner</h1>
        <p class="mt-2 max-w-3xl text-gray-400">
          The runner is a program on the development PC (<code class="text-gray-300">plugins/feedback/agent/</code>, see its README).
          It calls this site every few minutes, takes the oldest item submitted to Claude, has Claude Code fix it in
          throwaway Docker containers, runs the tests itself, has a second Claude review the change, commits it, and
          reports back on the item. It only ever sees items submitted to Claude.
        </p>

        <section class="mt-6 grid gap-4 sm:grid-cols-3">
          <div class="rounded-xl border border-gray-800 bg-gray-950 p-4">
            <div class="text-xs uppercase tracking-wide text-gray-500">Status</div>
            <div class="mt-1 text-lg font-semibold text-white" id="runner-status">{status_line(@agent)}</div>
            <div :if={@agent.last_seen_note} class="mt-1 text-xs text-gray-500">{@agent.last_seen_note}</div>
          </div>
          <div class="rounded-xl border border-gray-800 bg-gray-950 p-4">
            <div class="text-xs uppercase tracking-wide text-gray-500">Queue</div>
            <div class="mt-1 text-lg font-semibold text-white">{Map.get(@counts, "queued", 0)} waiting</div>
            <div class="mt-1 text-xs text-gray-500">{Map.get(@counts, "ready", 0)} ready to deploy · {Map.get(@counts, "failed", 0)} failed</div>
          </div>
          <div class="rounded-xl border border-gray-800 bg-gray-950 p-4">
            <div class="text-xs uppercase tracking-wide text-gray-500">Token</div>
            <div class="mt-1 text-lg font-semibold text-white">{if @agent.token_hash, do: "…" <> (@agent.token_hint || ""), else: "none"}</div>
            <div :if={@agent.token_created_at} class="mt-1 text-xs text-gray-500">made {ago(@agent.token_created_at)}</div>
          </div>
        </section>

        <section class="mt-6 space-y-3 rounded-xl border border-gray-800 bg-gray-950 p-5">
          <.switch id="toggle-auto-deploy" setting="auto_deploy" on={@agent.auto_deploy} label="Deploy on its own">
            When a change passes the runner's own test run and the second review, and touches nothing
            security-sensitive (sign-in, uploads, payments, webhooks, deploy files, secrets, dependencies, migrations that
            drop data), the runner deploys it straight away. Anything else waits for an admin's Deploy on the item.
            Off: every change waits for Deploy.
          </.switch>
          <.switch id="toggle-paused" setting="paused" on={@agent.paused} label="Paused">
            The runner takes nothing new and deploys nothing while paused.
          </.switch>
        </section>

        <section class="mt-6 rounded-xl border border-gray-800 bg-gray-950 p-5">
          <h2 class="font-semibold text-white">Runner token</h2>
          <p class="mt-1 text-sm text-gray-400">
            The runner sends this token with every call. Only its fingerprint is kept here, so it's shown once:
            put it in the runner's token file on the PC (README). Making a new one stops the old one at once.
          </p>
          <div :if={@new_token} class="mt-3 rounded-lg border border-yellow-600/50 bg-yellow-500/10 p-3">
            <div class="text-xs text-yellow-200">Copy it now; it won't be shown again.</div>
            <code id="new-token" class="mt-1 block select-all break-all font-mono text-sm text-white">{@new_token}</code>
          </div>
          <div class="mt-3 flex gap-2">
            <button type="button" id="make-token" phx-click="new_token" data-confirm={@agent.token_hash && "Replace the runner's token? The old one stops working."} class="rounded-lg bg-violet-600 px-4 py-2 text-sm font-semibold text-white hover:bg-violet-500">
              {if @agent.token_hash, do: "Make a new token", else: "Make a token"}
            </button>
            <button :if={@agent.token_hash} type="button" id="revoke-token" phx-click="revoke" data-confirm="Revoke the token? The runner stops until it gets a new one." class="rounded-lg bg-gray-800 px-4 py-2 text-sm text-red-300 hover:bg-red-500/20">
              Revoke
            </button>
          </div>
        </section>

        <section class="mt-6">
          <h2 class="mb-2 font-semibold text-white">With Claude</h2>
          <ul class="space-y-2">
            <li :for={item <- @queue} class="flex items-center gap-3 rounded-lg border border-gray-800 bg-gray-950 px-3 py-2 text-sm">
              <.status_pill status={item.status} />
              <.link navigate={"/feedback/#{item.id}"} class="min-w-0 flex-1 truncate text-gray-200 hover:text-white">
                <span class="text-gray-500">#{item.number}</span> {item.title}
              </.link>
              <span class="text-xs text-gray-500">{ago(item.updated_at)}</span>
            </li>
          </ul>
          <p :if={@queue == []} class="text-sm text-gray-500">Nothing has been submitted to Claude yet.</p>
        </section>
      </div>
    </div>
    """
  end

  attr(:id, :string, required: true)
  attr(:setting, :string, required: true)
  attr(:on, :boolean, required: true)
  attr(:label, :string, required: true)
  slot(:inner_block)

  defp switch(assigns) do
    ~H"""
    <div class="flex items-start gap-4">
      <button
        type="button"
        id={@id}
        role="switch"
        aria-checked={to_string(@on)}
        phx-click="toggle"
        phx-value-setting={@setting}
        class={["relative mt-0.5 h-6 w-11 shrink-0 rounded-full transition", if(@on, do: "bg-orange-500", else: "bg-gray-700")]}
      >
        <span class={["absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all", if(@on, do: "left-[22px]", else: "left-0.5")]}></span>
      </button>
      <div>
        <div class="font-medium text-white">{@label} <span class="ml-1 text-xs text-gray-500">{if @on, do: "on", else: "off"}</span></div>
        <p class="text-sm text-gray-400">{render_slot(@inner_block)}</p>
      </div>
    </div>
    """
  end

  defp status_line(%{token_hash: nil}), do: "Not set up"
  defp status_line(%{paused: true}), do: "Paused"
  defp status_line(%{last_seen_at: nil}), do: "Never called"

  defp status_line(%{last_seen_at: t}) do
    if DateTime.diff(DateTime.utc_now(), t) > 3600,
      do: "Quiet since " <> ago(t),
      else: "Running (" <> ago(t) <> ")"
  end
end
