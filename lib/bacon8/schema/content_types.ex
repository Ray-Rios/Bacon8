defmodule Bacon8.Schema.ContentTypes do
  use Absinthe.Schema.Notation

  # ========================
  # Objects
  # ========================
  object :page do
    field :id, :id
    field :title, :string
    field :slug, :string
    field :content, :string
    field :template_type, :string
    field :is_published, :boolean
    field :inserted_at, :utc_datetime
    field :updated_at, :utc_datetime
  end

  object :user do
    field :id, :id
    field :email, :string
    field :name, :string
    field :avatar_shape, :string
    field :avatar_color, :string
    field :avatar_url, :string
    field :is_online, :boolean
    field :is_admin, :boolean
    field :status, :string
    field :position_x, :float
    field :position_y, :float
    field :last_activity, :utc_datetime
    field :confirmed_at, :utc_datetime
  end

  object :auth_payload do
    field :token, :string
    field :user, :user
  end

  object :chat_message do
    field :id, :id
    field :content, :string
    field :user, :user
    field :inserted_at, :utc_datetime
  end

  object :presence_update do
    field :user_id, :id
    field :status, :string
    field :user, :user
  end

  object :file do
    field :id, non_null(:id)
    field :filename, :string
    field :url, :string
    field :content_type, :string
    field :size, :integer
    field :inserted_at, :utc_datetime
  end

  # ========================
  # Input Objects
  # ========================
  input_object :page_input do
    field :title, non_null(:string)
    field :slug, :string
    field :content, :string
    field :template_type, :string
    field :is_published, :boolean
  end

  input_object :register_input do
    field :email, non_null(:string)
    field :password, non_null(:string)
    field :name, :string
  end

  input_object :login_input do
    field :email, non_null(:string)
    field :password, non_null(:string)
  end

  input_object :chat_input do
    field :content, non_null(:string)
  end

  input_object :avatar_input do
    field :avatar_shape, :string
    field :avatar_color, :string
    field :avatar_file, :string
  end

  # ========================
  # Scalars
  # ========================
  scalar :utc_datetime, description: "UTC datetime" do
    parse &parse_datetime/1
    serialize &serialize_datetime/1
  end

  scalar :naive_datetime, description: "Naive datetime" do
    parse &parse_datetime/1
    serialize &serialize_datetime/1
  end

  # ========================
  # Scalar Helpers
  # ========================
  defp parse_datetime(%Absinthe.Blueprint.Input.String{value: value}) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, dt} -> {:ok, dt}
      _ -> :error
    end
  end

  defp serialize_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp serialize_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
