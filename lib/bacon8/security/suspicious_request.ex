defmodule Bacon8.Security.SuspiciousRequest do
  @moduledoc """
  Tracks suspicious requests like vulnerability scans, 
  WordPress probes, and other malicious activity.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "suspicious_requests" do
    field :ip_address, :string
    field :path, :string
    field :method, :string
    field :user_agent, :string
    field :request_type, :string  # "wordpress_scan", "php_probe", "sql_injection", etc.
    field :status_code, :integer
    field :blocked, :boolean, default: false
    field :fingerprint_hash, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [:ip_address, :path, :method, :user_agent, :request_type, :status_code, :blocked, :fingerprint_hash])
    |> validate_required([:ip_address, :path, :method, :request_type])
  end
end
