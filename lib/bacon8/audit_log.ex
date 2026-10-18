defmodule Bacon8.AuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_logs" do
    field :actor_id, :binary_id
    field :action, :string
    field :target_type, :string
    field :target_id, :binary_id
    field :metadata, :map

    timestamps(type: :utc_datetime)
  end

  def changeset(audit, attrs) do
    audit
    |> cast(attrs, [:actor_id, :action, :target_type, :target_id, :metadata])
    |> validate_required([:action])
  end
end
