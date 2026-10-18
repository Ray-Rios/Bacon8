defmodule Bacon8.Schema.Mutations.Accounts do
  use Absinthe.Schema.Notation
  alias Bacon8.Resolvers.Accounts, as: AccountsResolver

  object :accounts_mutations do
    @desc "Register a new user"
    field :register, :auth_payload do
      arg :input, non_null(:register_input)
      resolve &AccountsResolver.register/3
    end

    @desc "Login a user"
    field :login, :auth_payload do
      arg :input, non_null(:login_input)
      resolve &AccountsResolver.login/3
    end

    @desc "Update a user avatar"
    field :update_avatar, :user do
      arg :input, non_null(:avatar_input)
      resolve &AccountsResolver.update_avatar/3
    end
  end
end
