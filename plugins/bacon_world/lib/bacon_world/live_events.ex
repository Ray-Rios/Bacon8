defmodule BaconWorld.LiveEvents do
  @moduledoc """
  XP & loot events (2026-11-03): windows of time when experience, loot chances or coins are
  multiplied ("Double XP weekend"), set on `/admin/bacon_world/bestiary?tab=events`.

  Rows of `bacon_world_defs` kind `"event"` (`BaconWorld.Defs`):

      %{name: "Double XP weekend", xp_mult: 2.0, loot_mult: 1.0, coin_mult: 1.0,
        starts_at: "2026-11-07T00:00:00Z", ends_at: "2026-11-09T08:00:00Z", announce: true}

  Times are ISO 8601 strings in UTC (the codec stores JSON). Events that overlap multiply, and the
  product is capped at `max_mult/0`. `BaconWorld.Progression.kill_xp/2` and `BaconWorld.Loot` read
  `mult/1` on every kill; it is a cached list and a few comparisons.
  """

  alias BaconWorld.Defs

  @kind "event"
  @max_mult 10.0
  @fields [xp: :xp_mult, loot: :loot_mult, coin: :coin_mult]

  def kind, do: @kind
  def max_mult, do: @max_mult

  @doc "Every event, `[{id, event}]`."
  def list, do: Defs.list(@kind)

  @doc "The events running at `now`."
  def active(now \\ DateTime.utc_now()) do
    for {id, e} <- list(), running?(e, now), do: {id, e}
  rescue
    _ -> []
  end

  @doc "`:upcoming`, `:running` or `:over`."
  def status(e, now \\ DateTime.utc_now()) do
    cond do
      running?(e, now) -> :running
      before?(now, parse(e[:starts_at])) -> :upcoming
      true -> :over
    end
  end

  @doc "The multiplier in force for `:xp`, `:loot` or `:coin` (1.0 with no event running)."
  def mult(what, now \\ DateTime.utc_now()) when what in [:xp, :loot, :coin] do
    field = Keyword.fetch!(@fields, what)

    active(now)
    |> Enum.reduce(1.0, fn {_id, e}, acc -> acc * num(e[field]) end)
    |> max(0.0)
    |> min(@max_mult)
  end

  defp running?(e, now) do
    with %DateTime{} = s <- parse(e[:starts_at]),
         %DateTime{} = t <- parse(e[:ends_at]) do
      not before?(now, s) and before?(now, t)
    else
      _ -> false
    end
  end

  defp before?(_a, nil), do: false
  defp before?(a, b), do: DateTime.compare(a, b) == :lt

  @doc false
  def parse(%DateTime{} = d), do: d

  def parse(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, d, _} -> d
      _ -> nil
    end
  end

  def parse(_), do: nil

  defp num(v) when is_number(v) and v >= 0, do: v * 1.0
  defp num(_), do: 1.0

  @doc """
  An event from the admin form: `"name"`, `"xp_mult"`, `"loot_mult"`, `"coin_mult"`, `"starts_at"`,
  `"ends_at"` (`datetime-local` values, read as UTC, or ISO 8601) and `"announce"`.
  `{:ok, event}` or `{:error, [message]}`.
  """
  def from_form(p) do
    name = p |> Map.get("name", "") |> to_string() |> String.trim() |> String.slice(0, 80)
    s = local(p["starts_at"])
    t = local(p["ends_at"])

    mults = for {_k, f} <- @fields, into: %{}, do: {f, clamp(p[Atom.to_string(f)])}

    errors =
      [
        name == "" && "Give the event a name.",
        is_nil(s) && "When does it start?",
        is_nil(t) && "When does it end?",
        s && t && DateTime.compare(t, s) != :gt && "It must end after it starts."
      ]
      |> Enum.filter(&is_binary/1)

    if errors == [] do
      {:ok, Map.merge(mults, %{name: name, starts_at: DateTime.to_iso8601(s), ends_at: DateTime.to_iso8601(t), announce: p["announce"] in ["true", "on", true]})}
    else
      {:error, errors}
    end
  end

  # "2026-11-07T18:00" (a datetime-local input) or ISO 8601 with a zone; read as UTC
  defp local(v) when is_binary(v) and v != "" do
    case parse(v) do
      %DateTime{} = d ->
        DateTime.truncate(d, :second)

      nil ->
        v = if String.length(v) == 16, do: v <> ":00", else: v

        case NaiveDateTime.from_iso8601(v) do
          {:ok, n} -> n |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
          _ -> nil
        end
    end
  end

  defp local(_), do: nil

  defp clamp(v) do
    case Float.parse(to_string(v || "1")) do
      {f, _} -> f |> max(0.0) |> min(@max_mult)
      :error -> 1.0
    end
  end
end
