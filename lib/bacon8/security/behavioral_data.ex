defmodule Bacon8.Security.BehavioralData do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "behavioral_data" do
    field :session_id, :string
    field :mouse_movements, :integer, default: 0
    field :keystrokes, :integer, default: 0
    field :form_focus_time, :integer
    field :time_to_submit, :integer
    field :seems_human, :boolean, default: false
    field :timestamp, :utc_datetime
    
    belongs_to :device_fingerprint, Bacon8.Security.DeviceFingerprint

    timestamps(type: :utc_datetime)
  end

  def changeset(behavioral_data, attrs) do
    behavioral_data
    |> cast(attrs, [:session_id, :device_fingerprint_id, :mouse_movements, :keystrokes,
                    :form_focus_time, :time_to_submit, :seems_human, :timestamp])
    |> validate_required([:timestamp])
    |> validate_number(:mouse_movements, greater_than_or_equal_to: 0)
    |> validate_number(:keystrokes, greater_than_or_equal_to: 0)
  end
end
