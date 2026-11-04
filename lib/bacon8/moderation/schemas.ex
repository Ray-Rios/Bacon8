defmodule Bacon8.Moderation.Report do
  @moduledoc """
  A report of content that may be illegal or break the rules, or a takedown request
  (`kind`: `"report"`, `"ncii_takedown"` under the TAKE IT DOWN Act, `"dmca"`). See
  `Bacon8.Moderation`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @kinds ~w(report ncii_takedown dmca)
  @statuses ~w(open actioned dismissed)

  schema "moderation_reports" do
    field :kind, :string, default: "report"
    field :category, :string
    field :status, :string, default: "open"
    field :priority, :integer, default: 2
    field :due_at, :utc_datetime
    field :subject_type, :string
    field :subject_id, :string
    field :subject_url, :string
    field :subject_owner_id, :binary_id
    field :subject_snapshot, :map, default: %{}
    field :details, :string
    field :reporter_id, :binary_id
    field :reporter_name, :string
    field :reporter_email, :string
    field :reporter_ip, :string
    field :signature, :string
    field :sworn, :boolean, default: false
    field :ncmec_report_id, :string
    field :resolution, :string
    field :resolved_by, :binary_id
    field :resolved_at, :utc_datetime
    has_many :actions, Bacon8.Moderation.Action, preload_order: [asc: :inserted_at]
    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds
  def statuses, do: @statuses

  @doc false
  def changeset(report, attrs, categories) do
    report
    |> cast(attrs, [:kind, :category, :priority, :due_at, :subject_type, :subject_id, :subject_url, :subject_owner_id, :subject_snapshot, :details,
                    :reporter_id, :reporter_name, :reporter_email, :reporter_ip, :signature, :sworn])
    |> validate_required([:kind, :category])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:category, categories, message: "pick what's wrong")
    |> validate_length(:details, max: 5_000)
    |> validate_length(:subject_url, max: 2_000)
    |> validate_length(:reporter_name, max: 120)
    |> validate_length(:signature, max: 120)
    |> validate_format(:reporter_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "doesn't look like an email address")
    |> validate_subject()
    |> validate_request()
  end

  # something to act on: a link, or what the in-site Report button named
  defp validate_subject(cs) do
    if blank?(get_field(cs, :subject_url)) and blank?(get_field(cs, :subject_id)),
      do: add_error(cs, :subject_url, "say where it is (a link to it)"),
      else: cs
  end

  # TAKE IT DOWN Act and DMCA requests need who is asking, a signature and the sworn statement
  defp validate_request(cs) do
    case get_field(cs, :kind) do
      k when k in ["ncii_takedown", "dmca"] ->
        cs
        |> validate_required([:reporter_name, :reporter_email, :signature], message: "is required for this request")
        |> validate_acceptance(:sworn, message: "must be confirmed")
        |> then(&if(k == "dmca", do: validate_required(&1, [:details], message: "describe the work"), else: &1))

      _ ->
        cs
    end
  end

  defp blank?(v), do: v in [nil, ""]

  @doc false
  def status_changeset(report, attrs), do: cast(report, attrs, [:status, :ncmec_report_id, :resolution, :resolved_by, :resolved_at])
end

defmodule Bacon8.Moderation.Action do
  @moduledoc "Something staff (or the hub itself) did about a report: the case history."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "moderation_actions" do
    belongs_to :report, Bacon8.Moderation.Report
    field :actor_id, :binary_id
    field :action, :string
    field :note, :string
    field :metadata, :map, default: %{}
    timestamps(type: :utc_datetime, updated_at: false)
  end
end

defmodule Bacon8.Moderation.BlockedHash do
  @moduledoc "A file (by SHA-256) nobody may upload again: removed as illegal, or a known-bad hash."
  use Ecto.Schema

  @primary_key {:sha256, :string, autogenerate: false}
  schema "moderation_blocked_hashes" do
    field :reason, :string
    field :report_id, :binary_id
    field :added_by, :binary_id
    timestamps(type: :utc_datetime, updated_at: false)
  end
end

defmodule Bacon8.Moderation.Hold do
  @moduledoc """
  Evidence kept for the law: a file's body (`sha256` in `Bacon8.Storage`, kept from the drive's
  garbage collection) and what was known about it (`evidence`), until `preserve_until` and an
  admin's release. 18 U.S.C. § 2258A (as amended by the REPORT Act, 2024) asks a provider that
  reports to NCMEC to preserve the report's contents for a year.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "moderation_holds" do
    belongs_to :report, Bacon8.Moderation.Report
    field :sha256, :string
    field :subject_type, :string
    field :subject_id, :string
    field :owner_id, :binary_id
    field :evidence, :map, default: %{}
    field :preserve_until, :utc_datetime
    field :released_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
