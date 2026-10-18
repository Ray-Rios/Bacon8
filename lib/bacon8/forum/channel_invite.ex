defmodule Bacon8.Forum.ChannelInvite do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "channel_invites" do
    belongs_to :channel, Bacon8.Forum.Channel
    belongs_to :inviter, Bacon8.Accounts.User
    belongs_to :invitee, Bacon8.Accounts.User
    
    field :code, :string
    field :max_uses, :integer
    field :uses, :integer, default: 0
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :is_revoked, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:channel_id, :inviter_id, :invitee_id, :code, :max_uses, :uses, :expires_at, :accepted_at, :revoked_at, :is_revoked])
    |> maybe_generate_code()
    |> validate_required([:channel_id, :inviter_id, :code])
    |> unique_constraint(:code)
  end

  defp maybe_generate_code(changeset) do
    if is_nil(get_field(changeset, :code)) do
      put_change(changeset, :code, generate_code())
    else
      changeset
    end
  end

  defp generate_code do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false) |> binary_part(0, 10)
  end

  def is_valid?(%__MODULE__{} = invite) do
    # Check if not revoked
    not_revoked = invite.is_revoked != true && is_nil(invite.revoked_at)

    # Check if not expired
    not_expired = is_nil(invite.expires_at) || DateTime.compare(DateTime.utc_now(), invite.expires_at) == :lt
    
    # Check if not at max uses
    not_maxed = is_nil(invite.max_uses) || invite.uses < invite.max_uses
    
    not_revoked && not_expired && not_maxed
  end

  def revoke(invite) do
    # Truncate to :second to match Ecto :utc_datetime expectations
    Ecto.Changeset.change(invite, %{is_revoked: true, revoked_at: DateTime.truncate(DateTime.utc_now(), :second)})
  end

  def accept(invite) do
    # Truncate to :second to match Ecto :utc_datetime expectations
    Ecto.Changeset.change(invite, %{accepted_at: DateTime.truncate(DateTime.utc_now(), :second)})
  end
end
