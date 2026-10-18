defmodule Bacon8.Drive.Names do
  @moduledoc """
  File and folder names in the drive. Names are display strings stored in the
  database - they never become filesystem paths (bodies are stored by SHA-256) -
  but they still must be a single, printable path segment so that downloads,
  zip exports and the legacy import behave.
  """
  import Ecto.Changeset

  @max 255

  def validate_name(changeset, field) do
    changeset
    |> update_change(field, &normalize/1)
    |> validate_required([field])
    |> validate_length(field, max: @max)
    |> validate_change(field, fn ^field, name ->
      case problem(name) do
        nil -> []
        msg -> [{field, msg}]
      end
    end)
  end

  @doc "Trim surrounding whitespace; nil stays nil."
  def normalize(nil), do: nil
  def normalize(name) when is_binary(name), do: String.trim(name)

  @doc "Returns nil when `name` is acceptable, otherwise a message."
  def problem(name) when is_binary(name) do
    cond do
      name in ["", ".", ".."] -> "is not a valid name"
      String.contains?(name, ["/", "\\"]) -> "cannot contain / or \\"
      String.match?(name, ~r/[\x00-\x1F\x7F]/u) -> "cannot contain control characters"
      not String.valid?(name) -> "must be valid UTF-8"
      true -> nil
    end
  end

  def problem(_), do: "is not a valid name"

  @doc """
  Given a desired name and the names already taken in a folder, returns a free
  one: "photo.png" -> "photo (1).png" -> "photo (2).png" ...
  """
  def dedupe(name, taken) do
    taken = MapSet.new(taken, &String.downcase/1)

    if MapSet.member?(taken, String.downcase(name)) do
      ext = Path.extname(name)
      base = Path.rootname(name)

      Stream.iterate(1, &(&1 + 1))
      |> Stream.map(&"#{base} (#{&1})#{ext}")
      |> Enum.find(&(not MapSet.member?(taken, String.downcase(&1))))
    else
      name
    end
  end
end
