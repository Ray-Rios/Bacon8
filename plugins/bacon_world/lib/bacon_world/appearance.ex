defmodule BaconWorld.Appearance do
  @moduledoc """
  A character's look: body, height, shape sliders, colours, hair and facial hair.
  Stored in the character's `settings["appearance"]` and drawn by the client's
  `human-factory.ts`; `assets/js/appearance.ts` builds the same map.

  Clothes aren't part of the look (since 2026-10-23): they are items the character
  wears (`BaconWorld.Items`, `BaconWorld.Inventory`). An `"outfit"` saved in an older
  look is dropped.

  `normalize/3` never trusts what a player sends. Unknown keys are dropped,
  numbers are clamped to their slider ranges and rounded, colours must be
  `#RRGGBB`, hair styles must be short word-character ids (and, when the style
  manifest is installed, one of its styles), and garments come from a fixed
  A bad field falls back to its default; only a missing or unknown body type (and a
  value that isn't a map) is an error.

      %{
        "v" => 1, "body" => "male" | "female", "height" => 0.92..1.08,
        "shape" => %{"weight" => -1..1, "muscle" => 0..1, ...},
        "skin" => "#C68E6E", "eyes" => "#5A3D26", "brows" => nil | "#RRGGBB",
        "hair" => %{"style" => "Short" | "none", "color" => "#2B1E14"},
        "facial" => %{"style" => "none", "color" => "#2B1E14"}
      }
  """

  @bodies ~w(male female)
  @shapes [
    {"weight", -1.0, 1.0},
    {"muscle", 0.0, 1.0},
    # -1 (narrower than his look, Shoulders_Narrow) is the male's only; the female's stays 0..1
    {"shoulders", -1.0, 1.0},
    {"chest", -1.0, 1.0},
    {"belly", 0.0, 1.0},
    {"hips", 0.0, 1.0},
    {"glutes", -1.0, 1.0},
    # the female's Black Desert-style sliders (2026-10-23)
    {"waist", -1.0, 1.0},
    {"chest_height", -1.0, 1.0},
    {"chest_spacing", -1.0, 1.0},
    {"chest_shape", -1.0, 1.0},
    {"glute_lift", 0.0, 1.0},
    {"arms", -1.0, 1.0},
    {"thighs", -1.0, 1.0},
    {"calves", -1.0, 1.0},
    {"face", 0.0, 1.0},
    {"jaw", 0.0, 1.0},
    {"nose", 0.0, 1.0}
  ]
  @height {0.92, 1.08}
  @color ~r/\A#[0-9a-fA-F]{6}\z/
  @style ~r/\A[A-Za-z0-9_]{1,32}\z/
  @models %{"male" => "/models/Humans/Male.glb", "female" => "/models/Humans/Female.glb"}

  def bodies, do: @bodies

  @doc "The model file a body type is drawn with."
  def model_path(body) when body in @bodies, do: Map.fetch!(@models, body)

  @doc "True for the Bacon8 humans (the models an appearance applies to)."
  def human_model?(path) when is_binary(path), do: path in Map.values(@models)
  def human_model?(_), do: false

  @doc "The body type of a model path (the female model, else male)."
  def body_for_model(path) when is_binary(path), do: if(String.contains?(String.downcase(path), "female"), do: "female", else: "male")
  def body_for_model(_), do: "male"

  @doc "The default look for a body type."
  def default(body \\ "male") when body in @bodies do
    %{
      "v" => 1,
      "body" => body,
      "height" => 1.0,
      "shape" => Map.new(@shapes, fn {k, _, _} -> {k, 0.0} end),
      "skin" => "#C68E6E",
      "eyes" => "#5A3D26",
      "brows" => nil,
      "hair" => %{"style" => if(body == "male", do: "Short", else: "Lob"), "color" => "#2B1E14"},
      "facial" => %{"style" => "none", "color" => "#2B1E14"}
    }
  end

  @doc """
  `{:ok, look}` with every field valid, or `{:error, :invalid_appearance}`.

  `fallback_body` is used when `raw` has no valid `"body"`. `styles`, when given,
  is `%{"male" => %{"hair" => ids, "facial" => ids}, "female" => ...}` (from the
  hair manifest); a style id not in it becomes the body's default.
  """
  def normalize(raw, fallback_body \\ nil, styles \\ nil)

  def normalize(raw, fallback_body, styles) when is_map(raw) do
    raw = stringify(raw)

    body =
      case raw["body"] do
        b when b in @bodies -> b
        _ -> fallback_body
      end

    if body in @bodies, do: {:ok, build(raw, body, styles)}, else: {:error, :invalid_appearance}
  end

  def normalize(_raw, _fallback_body, _styles), do: {:error, :invalid_appearance}

  @doc """
  The look to draw for a character's stored settings: the saved appearance, or the
  default for its model's body type. `nil` for models that aren't Bacon8 humans.
  """
  def for_settings(settings, model_path) do
    settings = settings || %{}

    cond do
      not human_model?(model_path) ->
        nil

      is_map(settings["appearance"]) ->
        case normalize(settings["appearance"], body_for_model(model_path)) do
          {:ok, look} -> %{look | "body" => body_for_model(model_path)} |> fix_body()
          _ -> default(body_for_model(model_path))
        end

      true ->
        default(body_for_model(model_path))
    end
  end

  # ---------------------------------------------------------------------------

  defp build(raw, body, styles) do
    d = default(body)
    shape = map(raw["shape"])
    hair = map(raw["hair"])
    facial = map(raw["facial"])

    %{
      "v" => 1,
      "body" => body,
      "height" => number(raw["height"], 1.0, @height),
      "shape" => Map.new(@shapes, fn {k, lo, hi} -> {k, number(shape[k], 0.0, {lo, hi})} end),
      "skin" => color(raw["skin"], d["skin"]),
      "eyes" => color(raw["eyes"], d["eyes"]),
      "brows" => if(is_nil(raw["brows"]), do: nil, else: color(raw["brows"], d["hair"]["color"])),
      "hair" => %{"style" => style(hair["style"], d["hair"]["style"], styles, body, "hair"), "color" => color(hair["color"], d["hair"]["color"])},
      "facial" => %{
        "style" => if(body == "male", do: style(facial["style"], "none", styles, body, "facial"), else: "none"),
        "color" => color(facial["color"], d["facial"]["color"])
      }
    }
    |> fix_body()
  end

  # Sliders the male body has no morphs for: the chest's shaping (his chest size is the
  # pectorals; the waist, glute lift and limb sliders are his too since the 2026-10-24 rebuild).
  @female_only ~w(chest_height chest_spacing chest_shape)

  # The chest shaping sliders are for the female body; facial hair for the male.
  defp fix_body(%{"body" => "male"} = look),
    do: update_in(look, ["shape"], &Map.merge(&1, Map.new(@female_only, fn k -> {k, 0.0} end)))

  defp fix_body(%{"body" => "female"} = look) do
    look
    |> put_in(["facial", "style"], "none")
    |> update_in(["shape", "shoulders"], &max(&1, 0.0))
  end

  defp map(m) when is_map(m), do: stringify(m)
  defp map(_), do: %{}

  defp stringify(m), do: Map.new(m, fn {k, v} -> {to_string(k), v} end)

  defp number(v, default, {lo, hi}) do
    n =
      cond do
        is_integer(v) -> v * 1.0
        is_float(v) -> v
        is_binary(v) -> parse_float(v, default)
        true -> default
      end

    n |> max(lo) |> min(hi) |> Float.round(3)
  end

  defp parse_float(s, default) do
    case Float.parse(String.trim(s)) do
      {f, ""} -> f
      _ -> default
    end
  end

  defp color(v, default) when is_binary(v), do: if(Regex.match?(@color, v), do: String.upcase(v), else: default)
  defp color(_, default), do: default

  defp style("none", _default, _styles, _body, _kind), do: "none"

  defp style(v, default, styles, body, kind) when is_binary(v) do
    known = styles && get_in(styles, [body, kind])

    cond do
      not Regex.match?(@style, v) -> default
      is_list(known) and known != [] and v not in known -> replacement(v, styles, body, known) || default
      true -> v
    end
  end

  defp style(_, default, _styles, _body, _kind), do: default

  # A retired style id saved in an older look maps to the style that replaced it.
  defp replacement(v, styles, body, known) do
    with %{} = aliases <- get_in(styles, [body, "aliases"]),
         to when is_binary(to) <- aliases[v],
         true <- to in known do
      to
    else
      _ -> nil
    end
  end
end
