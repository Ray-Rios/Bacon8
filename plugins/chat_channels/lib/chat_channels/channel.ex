defmodule ChatChannels.Channel do
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

    has_many :messages, ChatChannels.Message
    has_many :members, ChatChannels.ChannelMember
    has_many :streaming_sessions, ChatChannels.StreamingSession

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    # Not :icon_path: an icon is set only through put_icon/2 (see there).
    |> cast(attrs, [:name, :description, :topic, :is_private, :position, :channel_type, :created_by_id, :owner_id, :is_public, :is_user_created, :max_participants, :invite_code, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_inclusion(:channel_type, ["text", "voice", "video", "stream"])
    # Names have to be unique, but the table has no unique index (adding one could fail on
    # a site that already has two), so check in the app; the constraint is kept for when
    # an index exists.
    |> unsafe_validate_unique([:name], Bacon8.Repo)
    |> unique_constraint(:name)
    |> unique_constraint(:invite_code)
    |> validate_channel_limit()
    |> maybe_generate_invite_code()
  end

  # THE LIMIT IS PER USER AND LIVES ON THE USER ROW.
  #
  # Was a literal 5. /shop will sell channel slots, so the number has to be
  # something a purchase can increment - see ChatChannels.UserSettings.
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

          allowance = ChatChannels.channel_allowance(owner_id)

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

  @doc """
  Applies an icon change from `attrs` (`:icon_path` or `"icon_path"`), when it has one: nil, or a
  file in this channel's own icon folder (`icon_path?/2`); anything else is a changeset error.

  The icon is never cast from a form. Until 2026-10-25 it was, so a member creating a channel
  could name any file under uploads/, and deleting the channel then removed that file's whole
  folder (and changing the icon removed the file).
  """
  def put_icon(changeset, attrs) when is_map(attrs) do
    case fetch_icon(attrs) do
      :none ->
        changeset

      {:ok, nil} ->
        put_change(changeset, :icon_path, nil)

      {:ok, path} ->
        if icon_path?(changeset.data, path),
          do: put_change(changeset, :icon_path, path),
          else: add_error(changeset, :icon_path, "is not this channel's icon")
    end
  end

  defp fetch_icon(attrs) do
    cond do
      Map.has_key?(attrs, :icon_path) -> {:ok, Map.get(attrs, :icon_path)}
      Map.has_key?(attrs, "icon_path") -> {:ok, Map.get(attrs, "icon_path")}
      true -> :none
    end
  end

  @doc """
  True when `path` is a file in the channel's own icon folder, the way
  `Bacon8.Uploads.upload_file/4` names it: `/uploads/<uploader id>/channel_icons/<channel id>/<file>`.
  Checked before an icon is saved, and again before one is deleted, because a row saved before
  this check existed may hold any string.
  """
  def icon_path?(%{id: id}, "/uploads/" <> rest) when is_binary(id) do
    case String.split(rest, "/") do
      [uploader, "channel_icons", ^id, file] -> plain_segment?(uploader) and plain_segment?(file)
      _ -> false
    end
  end

  def icon_path?(_channel, _path), do: false

  # One path segment: letters, digits, dot, dash, underscore; not . or .., and not a reserved
  # folder such as _drive.
  defp plain_segment?(segment) do
    segment not in [".", ".."] and not String.starts_with?(segment, "_") and
      Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, segment)
  end
end