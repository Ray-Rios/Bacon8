defmodule Bacon8.DataCase do
  @moduledoc """
  Test case for anything that touches the database. Each test runs inside a
  sandboxed transaction on both repos, rolled back at the end.

      use Bacon8.DataCase, async: true
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Bacon8.Repo
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Bacon8.DataCase
    end
  end

  setup tags do
    Bacon8.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    for repo <- [Bacon8.Repo, Bacon8.GamesRepo] do
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(repo, shared: not tags[:async])
      ExUnit.Callbacks.on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    end
  end

  @doc "Changeset errors as %{field => [messages]}."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc "Inserts a user directly (no registration side effects)."
  def user_fixture(attrs \\ %{}) do
    n = System.unique_integer([:positive])

    %Bacon8.Accounts.User{
      email: "user#{n}@example.com",
      name: "user#{n}",
      password_hash: "not-a-real-hash",
      role: "member",
      status: "active"
    }
    |> Map.merge(Map.new(attrs))
    |> Bacon8.Repo.insert!()
  end

  @doc "Writes `contents` to a temp file and returns its path (like a LiveView upload)."
  def tmp_upload(contents) do
    path = Path.join(System.tmp_dir!(), "bacon8_upload_#{System.unique_integer([:positive])}")
    File.write!(path, contents)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    path
  end
end
