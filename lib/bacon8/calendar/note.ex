defmodule Bacon8.Calendar.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "calendar_notes" do
    field :date, :date
    field :content, :string
    belongs_to :user, Bacon8.Accounts.User

    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:date, :content, :user_id])
    |> validate_required([:date, :user_id])
    |> unique_constraint([:user_id, :date])
  end
end
