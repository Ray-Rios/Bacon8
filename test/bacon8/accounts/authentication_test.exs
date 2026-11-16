defmodule Bacon8.Accounts.AuthenticationTest do
  # Who may sign in, and what a new account may be (2026-11-15). Passwords are checked only through
  # Accounts.authenticate_user_secure/3 (BACON8.md §6, invariant 16); a new account's role is the
  # caller's choice, never the form's (§13).
  use Bacon8.DataCase, async: false

  alias Bacon8.Accounts
  alias Bacon8.Accounts.{RateLimit, User}

  @password "Correct-Horse-9!"

  defp account(attrs \\ %{}) do
    user_fixture(Map.merge(%{password_hash: Pbkdf2.hash_pwd_salt(@password), email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second)}, Map.new(attrs)))
  end

  describe "authenticate_user_secure/3" do
    test "the right password signs in, by email or by name" do
      user = account()
      assert {:ok, %User{id: id}} = Accounts.authenticate_user_secure(user.email, @password)
      assert id == user.id
      assert {:ok, %User{id: ^id}} = Accounts.authenticate_user_secure(user.name, @password)
    end

    test "a wrong password and an unknown account get the same answer" do
      user = account()
      assert Accounts.authenticate_user_secure(user.email, "wrong") == {:error, :invalid_credentials}
      assert Accounts.authenticate_user_secure("nobody-#{System.unique_integer([:positive])}@example.com", @password) == {:error, :invalid_credentials}
    end

    test "banned, disabled, locked and unverified accounts are refused even with the right password" do
      assert Accounts.authenticate_user_secure(account(%{role: "banned"}).email, @password) == {:error, :account_banned}
      assert Accounts.authenticate_user_secure(account(%{status: "disabled"}).email, @password) == {:error, :account_disabled}
      locked = account(%{locked_until: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)})
      assert Accounts.authenticate_user_secure(locked.email, @password) == {:error, :account_locked}
      assert Accounts.authenticate_user_secure(account(%{email_verified_at: nil}).email, @password) == {:error, :email_not_verified}
      # a lock that is over no longer holds
      was = account(%{locked_until: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)})
      assert {:ok, _} = Accounts.authenticate_user_secure(was.email, @password)
    end

    test "those accounts don't learn their state from a wrong password" do
      assert Accounts.authenticate_user_secure(account(%{role: "banned"}).email, "wrong") == {:error, :invalid_credentials}
    end

    test "twenty wrong tries from one address in an hour and the address is turned away, right password or not" do
      user = account()
      ip = "203.0.113.#{rem(System.unique_integer([:positive]), 250) + 1}"
      for _ <- 1..20, do: assert(Accounts.authenticate_user_secure(user.email, "wrong", ip_address: ip) == {:error, :invalid_credentials})
      assert {:error, message} = Accounts.authenticate_user_secure(user.email, @password, ip_address: ip)
      assert is_binary(message) and message =~ "Too many"
      # another address is not held up by it
      assert {:ok, _} = Accounts.authenticate_user_secure(user.email, @password, ip_address: "203.0.113.251")
      RateLimit.reset_all_limits()
    end

    test "behind an address that names no one, the tries are counted per account" do
      a = account()
      b = account()
      gateway = "192.168.65.3"
      for _ <- 1..20, do: Accounts.authenticate_user_secure(a.email, "wrong", ip_address: gateway)
      assert {:error, message} = Accounts.authenticate_user_secure(a.email, @password, ip_address: gateway)
      assert is_binary(message)
      assert {:ok, _} = Accounts.authenticate_user_secure(b.email, @password, ip_address: gateway)
      RateLimit.reset_all_limits()
    end
  end

  describe "a new account's role" do
    @attrs %{"email" => "new@example.com", "name" => "newcomer", "password" => "Str0ng-Enough-Pw!"}

    test "the form can't choose it: role and is_admin in the attrs are ignored" do
      cs = User.registration_changeset(%User{}, Map.merge(@attrs, %{"role" => "admin", "is_admin" => true}))
      assert Ecto.Changeset.get_field(cs, :role) == "member"
      assert Ecto.Changeset.get_field(cs, :is_admin) == false
      cs = User.registration_changeset(%User{}, %{email: "x@example.com", name: "atoms", password: "Str0ng-Enough-Pw!", role: "admin", is_admin: true})
      assert Ecto.Changeset.get_field(cs, :role) == "member"
      refute Ecto.Changeset.get_field(cs, :is_admin)
    end

    test "the caller chooses it, and is_admin follows the role" do
      cs = User.registration_changeset(%User{}, @attrs, role: "admin")
      assert Ecto.Changeset.get_field(cs, :role) == "admin"
      assert Ecto.Changeset.get_field(cs, :is_admin)
      cs = User.registration_changeset(%User{}, @attrs, role: "gm")
      assert Ecto.Changeset.get_field(cs, :role) == "gm"
      refute Ecto.Changeset.get_field(cs, :is_admin)
      # a role that isn't one becomes a member
      assert Ecto.Changeset.get_field(User.registration_changeset(%User{}, @attrs, role: "owner"), :role) == "member"
    end

    test "create_user/1 passes attrs straight through, and still makes a member" do
      n = System.unique_integer([:positive])
      assert {:ok, user} = Accounts.create_user(%{"email" => "made#{n}@example.com", "name" => "made#{n}", "password" => "Str0ng-Enough-Pw!", "role" => "admin", "is_admin" => true})
      assert user.role == "member"
      refute user.is_admin
      assert user.status == "pending"
    end
  end
end
