defmodule FeedbackWeb.Components do
  @moduledoc "Pieces shared by the Suggestions & Bugs pages."
  use Phoenix.Component

  @labels %{
    "open" => {"Open", "bg-sky-500/15 text-sky-300 ring-sky-500/30"},
    "approved" => {"Approved", "bg-emerald-500/15 text-emerald-300 ring-emerald-500/30"},
    "rejected" => {"Declined", "bg-gray-500/15 text-gray-400 ring-gray-500/30"},
    "duplicate" => {"Duplicate", "bg-gray-500/15 text-gray-400 ring-gray-500/30"},
    "queued" => {"Queued for Claude", "bg-violet-500/15 text-violet-300 ring-violet-500/30"},
    "in_progress" => {"Claude is on it", "bg-violet-500/25 text-violet-200 ring-violet-400/40"},
    "needs_info" => {"Needs info", "bg-amber-500/15 text-amber-300 ring-amber-500/30"},
    "ready" => {"Ready to deploy", "bg-orange-500/15 text-orange-300 ring-orange-500/30"},
    "deploying" => {"Deploying", "bg-orange-500/25 text-orange-200 ring-orange-400/40"},
    "deployed" => {"Live", "bg-green-500/20 text-green-300 ring-green-500/40"},
    "failed" => {"Failed", "bg-red-500/15 text-red-300 ring-red-500/30"}
  }

  def status_label(status), do: @labels |> Map.get(status, {status, ""}) |> elem(0)

  attr(:status, :string, required: true)

  def status_pill(assigns) do
    {label, classes} =
      Map.get(
        @labels,
        assigns.status,
        {assigns.status, "bg-gray-500/15 text-gray-300 ring-gray-500/30"}
      )

    assigns = assign(assigns, label: label, classes: classes)

    ~H"""
    <span class={["inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset", @classes]}>
      <span :if={@status in ["in_progress", "deploying"]} class="h-1.5 w-1.5 animate-pulse rounded-full bg-current"></span>
      {@label}
    </span>
    """
  end

  attr(:kind, :string, required: true)

  def kind_badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-medium",
        if(@kind == "bug", do: "bg-red-500/10 text-red-300", else: "bg-yellow-500/10 text-yellow-200")
      ]}
      title={if @kind == "bug", do: "Bug", else: "Suggestion"}
    >
      {if @kind == "bug", do: "🐞 Bug", else: "💡 Suggestion"}
    </span>
    """
  end

  attr(:item, :map, required: true)
  attr(:can_vote, :boolean, default: true)
  attr(:size, :string, default: "md")

  def vote_box(assigns) do
    ~H"""
    <div class={["flex shrink-0 flex-col items-center rounded-lg border border-gray-800 bg-gray-950/70", if(@size == "lg", do: "w-16 py-2", else: "w-12 py-1")]}>
      <button
        type="button"
        phx-click="vote"
        phx-value-id={@item.id}
        phx-value-vote={if @item.my_vote == 1, do: "0", else: "1"}
        disabled={not @can_vote}
        aria-label="Vote up"
        aria-pressed={to_string(@item.my_vote == 1)}
        class={[
          "rounded px-2 leading-none transition disabled:cursor-not-allowed disabled:opacity-30",
          if(@item.my_vote == 1, do: "text-orange-400", else: "text-gray-500 hover:text-orange-300")
        ]}
      >
        ▲
      </button>
      <span class={["font-semibold tabular-nums", if(@size == "lg", do: "text-lg", else: "text-sm"), score_color(@item.score)]}>{@item.score}</span>
      <button
        type="button"
        phx-click="vote"
        phx-value-id={@item.id}
        phx-value-vote={if @item.my_vote == -1, do: "0", else: "-1"}
        disabled={not @can_vote}
        aria-label="Vote down"
        aria-pressed={to_string(@item.my_vote == -1)}
        class={[
          "rounded px-2 leading-none transition disabled:cursor-not-allowed disabled:opacity-30",
          if(@item.my_vote == -1, do: "text-sky-400", else: "text-gray-500 hover:text-sky-300")
        ]}
      >
        ▼
      </button>
      <span
        class="mt-1 flex items-center gap-1 whitespace-nowrap border-t border-gray-800/80 pt-1 text-[10px] leading-none tabular-nums text-gray-500"
        title={"#{@item.upvotes} upvote#{plural_s(@item.upvotes)}, #{@item.downvotes} downvote#{plural_s(@item.downvotes)}"}
      >
        <span class="text-orange-400/80">{@item.upvotes}▲</span>
        <span class="text-sky-400/80">{@item.downvotes}▼</span>
      </span>
    </div>
    """
  end

  defp plural_s(1), do: ""
  defp plural_s(_), do: "s"

  defp score_color(s) when s > 0, do: "text-white"
  defp score_color(s) when s < 0, do: "text-gray-500"
  defp score_color(_), do: "text-gray-300"

  @doc "\"3 hours ago\"."
  def ago(nil), do: ""

  def ago(%DateTime{} = t) do
    s = DateTime.diff(DateTime.utc_now(), t)

    cond do
      s < 60 -> "just now"
      s < 3600 -> plural(div(s, 60), "minute") <> " ago"
      s < 86_400 -> plural(div(s, 3600), "hour") <> " ago"
      s < 86_400 * 30 -> plural(div(s, 86_400), "day") <> " ago"
      true -> Calendar.strftime(t, "%b %-d, %Y")
    end
  end

  defp plural(1, word), do: "1 " <> word
  defp plural(n, word), do: "#{n} #{word}s"

  def name_of(nil), do: "a former member"
  def name_of(user), do: user.name || "member"

  @doc "Upload errors in words."
  def upload_error(:too_large), do: "That picture is over 10 MB."
  def upload_error(:not_accepted), do: "Only PNG, JPEG, WebP or GIF pictures."
  def upload_error(:too_many_files), do: "Up to #{Feedback.max_shots()} screenshots."
  def upload_error(other), do: "Upload failed (#{inspect(other)})."

  @doc "A reason from `Feedback` in words."
  def reason_text(:forbidden), do: "You can't do that."

  def reason_text(:rate_limited),
    do: "That's a lot of posts in an hour. Try again a little later."

  def reason_text(:too_many_shots), do: "Up to #{Feedback.max_shots()} screenshots."
  def reason_text(:not_an_image), do: "One of the files isn't a PNG, JPEG, WebP or GIF picture."
  def reason_text(:too_large), do: "One of the pictures is over 10 MB."
  def reason_text(:no_such_original), do: "There's no other item with that number."
  def reason_text(:stale), do: "Someone changed it just now. Have another look."
  def reason_text({:not_from, s}), do: "Not while it's #{String.downcase(status_label(s))}."
  def reason_text(other), do: "That didn't work (#{inspect(other)})."
end
