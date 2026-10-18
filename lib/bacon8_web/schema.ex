defmodule Bacon8Web.Schema do
  use Absinthe.Schema
  alias Bacon8.{Accounts}

  import_types Absinthe.Type.Custom

  # Types
  object :user do
    field :id, :id
    field :email, :string
    field :name, :string
    field :is_admin, :boolean
    field :role, :string
    field :inserted_at, :datetime
    field :updated_at, :datetime
  end

  # Queries
  query do
    field :current_user, :user do
      resolve fn _, %{context: %{current_user: user}} ->
        {:ok, user}
      end
    end
  end

  # Mutations
  mutation do
    field :login, :user do
      arg :email, non_null(:string)
      arg :password, non_null(:string)

      resolve fn %{email: email, password: password}, _context ->
        case Accounts.authenticate_user(email, password) do
          {:ok, user} -> {:ok, user}
          {:error, _} -> {:error, "Invalid credentials"}
        end
      end
    end

    field :register, :user do
      arg :email, non_null(:string)
      arg :password, non_null(:string)
      arg :name, :string

      resolve fn args, _context ->
        user_params = %{
          "email" => args.email,
          "password" => args.password,
          "name" => args[:name] || args.email
        }

        case Accounts.register_user(user_params) do
          {:ok, user} -> {:ok, user}
          {:error, changeset} -> 
            errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
            {:error, "Registration failed: #{inspect(errors)}"}
        end
      end
    end
  end

  # Context function to add current user to resolution context
  def context(ctx) do
    loader = Dataloader.new()
    |> Dataloader.add_source(:db, Dataloader.Ecto.new(Bacon8.Repo))

    Map.put(ctx, :loader, loader)
  end

  def plugins do
    [Absinthe.Middleware.Dataloader] ++ Absinthe.Plugin.defaults()
  end
end