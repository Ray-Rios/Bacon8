defmodule Bacon8.Calendar do
  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.Calendar.Note

  def list_notes(user_id) do
    Repo.all(from n in Note, where: n.user_id == ^user_id)
  end

  def get_note(user_id, date) do
    Repo.get_by(Note, user_id: user_id, date: date)
  end

  def save_note(user_id, date, content) do
    case get_note(user_id, date) do
      nil ->
        %Note{}
        |> Note.changeset(%{user_id: user_id, date: date, content: content})
        |> Repo.insert()
      note ->
        note
        |> Note.changeset(%{content: content})
        |> Repo.update()
    end
  end
end
