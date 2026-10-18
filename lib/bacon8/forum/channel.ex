defmodule Bacon8.Forum.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_channels" do
    field :name, :string
    field :description, :string
    field :topic, :string
    field :is_private, :boolean, default: false
    field :position, :integer, default: 0
    field :channel_type, :string, default: "text" # text, voice, video, stream

    # User ownership fields
    field :owner_id, :binary_id
    field :is_public, :boolean, default: true
    field :is_user_created, :boolean, default: false
    field :max_participants, :integer, default: 50
    field :invite_code, :string
    field :settings, :map, default: %{}
    field :icon_path, :string

    # Legacy field - keeping for backwards compatibility
    field :created_by_id, :binary_id
    
    belongs_to :owner, Bacon8.Accounts.User, define_field: false, foreign_key: :owner_id
    belongs_to :creator, Bacon8.Accounts.User, define_field: false, foreign_key: :created_by_id, type: :binary_id

    has_many :messages, Bacon8.Forum.Message
    has_many :members, Bacon8.Forum.ChannelMember
    has_many :streaming_sessions, Bacon8.Forum.StreamingSession

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :description, :topic, :is_private, :position, :channel_type, :created_by_id, :owner_id, :is_public, :is_user_created, :max_participants, :invite_code, :settings, :icon_path])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:channel_type, ["text", "voice", "video", "stream"])
    |> unique_constraint(:name)
    |> unique_constraint(:invite_code)
    |> validate_channel_limit()
    |> maybe_generate_invite_code()
  end

  # THE LIMIT IS PER USER AND LIVES ON THE USER ROW.
  #
  # Was a literal 5. /shop will sell channel slots, so the number has to be
  # something a purchase can increment - see users.channel_allowance.
  #
  # Games that build one thing per channel (a world, say) use this as their
  # limit too, rather than keeping a second counter: two limits on one thing
  # would mean the error names whichever tripped first, which is not
  # necessarily the one the player has to do something about.
  #
  # NOT A RACE-FREE CHECK, DELIBERATELY. Two simultaneous creates can both read
  # the count before either inserts, so a determined user can exceed their
  # allowance by one. The consequence is one extra channel; the fix is a
  # transaction with a row lock, and it is not worth taking a lock on every
  # channel create to prevent that. A game handing out a paid-for resource per
  # channel should take its own lock.
  defp validate_channel_limit(changeset) do
    case get_change(changeset, :owner_id) do
      nil ->
        changeset

      owner_id ->
        # Existing channels are being edited, not created - an owner at their
        # limit must still be able to rename what they already have.
        if get_field(changeset, :is_user_created) and is_nil(get_field(changeset, :id)) do
          import Ecto.Query

          allowance = Bacon8.Forum.channel_allowance(owner_id)

          count =
            Bacon8.Repo.aggregate(
              from(c in __MODULE__, where: c.owner_id == ^owner_id and c.is_user_created == true),
              :count
            )

          if count >= allowance do
            add_error(
              changeset,
              :owner_id,
              "You are using #{count} of #{allowance} channels. Delete one, or buy more slots."
            )
          else
            changeset
          end
        else
          changeset
        end
    end
  end

  defp maybe_generate_invite_code(changeset) do
    # Only generate invite code for private user-created channels
    if get_field(changeset, :is_user_created) && !get_field(changeset, :is_public) && is_nil(get_field(changeset, :invite_code)) do
      put_change(changeset, :invite_code, generate_invite_code())
    else
      changeset
    end
  end

  defp generate_invite_code do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false) |> binary_part(0, 10)
  end
end