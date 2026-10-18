defmodule Bacon8.EmailLogging.EmailLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "email_logs" do
    field :to, :string
    field :from, :string
    field :subject, :string
    field :html_body, :string
    field :text_body, :string
    field :provider, :string
    field :status, :string
    field :error, :string
    field :sent_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(email_log, attrs) do
    email_log
    |> cast(attrs, [:to, :from, :subject, :html_body, :text_body, :provider, :status, :error, :sent_at])
    |> validate_required([:to, :subject, :status])
  end
end
