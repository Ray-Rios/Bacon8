defmodule Bacon8.NotificationsTest do
  # The hub's notification system knows nothing about chat, or any other plugin: a plugin
  # says what a notification came from (`source_kind`, `source_id`) and where clicking it
  # goes (`path` in its metadata). It used to hold the forum's @mention code and point at
  # forum channels.
  use Bacon8.DataCase, async: true

  alias Bacon8.Notifications
  alias Bacon8.Notifications.UserNotification

  defp attrs(user, extra \\ %{}), do: Map.merge(%{type: "system", title: "Hello", user_id: user.id}, extra)

  test "a notification keeps what it came from and where it goes" do
    u = user_fixture()
    source = Ecto.UUID.generate()

    {:ok, n} =
      Notifications.create_notification(
        attrs(u, %{
          type: "mention",
          source_kind: "some_plugin_thing",
          source_id: source,
          metadata: %{"path" => "/somewhere/else"}
        })
      )

    stored = Repo.get!(UserNotification, n.id)
    assert stored.source_kind == "some_plugin_thing"
    assert stored.source_id == source
    assert stored.metadata["path"] == "/somewhere/else"
  end

  test "the desktop is told about it as it is created" do
    u = user_fixture()
    Phoenix.PubSub.subscribe(Bacon8.PubSub, "user:#{u.id}:notifications")

    {:ok, n} = Notifications.create_notification(attrs(u))

    assert_receive {:new_notification, %{id: id}} when id == n.id
  end

  test "a notification that is refused is not announced" do
    u = user_fixture()
    Phoenix.PubSub.subscribe(Bacon8.PubSub, "user:#{u.id}:notifications")

    assert {:error, cs} = Notifications.create_notification(attrs(u, %{type: "gossip"}))
    assert %{type: [_]} = errors_on(cs)
    refute_receive {:new_notification, _}, 50
  end

  test "it needs a type and a user" do
    assert {:error, cs} = Notifications.create_notification(%{})
    assert %{type: ["can't be blank"], user_id: ["can't be blank"]} = errors_on(cs)
  end

  test "unread notifications are counted, listed newest first, and reading clears them" do
    u = user_fixture()
    {:ok, a} = Notifications.create_notification(attrs(u, %{title: "first"}))
    {:ok, b} = Notifications.create_notification(attrs(u, %{title: "second"}))
    # whole-second timestamps: make "second" the newer one
    Repo.update_all(from(n in UserNotification, where: n.id == ^a.id), set: [inserted_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)])

    assert Notifications.count_unread_notifications(u.id) == 2
    assert Enum.map(Notifications.list_user_notifications(u.id), & &1.title) == ["second", "first"]

    {:ok, _} = Notifications.mark_as_read(Notifications.get_notification(u.id, b.id))
    assert Notifications.count_unread_notifications(u.id) == 1

    Notifications.mark_all_as_read(u.id)
    assert Notifications.count_unread_notifications(u.id) == 0
  end

  test "\"mark all read\" reaches every unread one, for that user only" do
    u = user_fixture()
    other = user_fixture()
    for _ <- 1..3, do: {:ok, _} = Notifications.create_notification(attrs(u))
    {:ok, _} = Notifications.create_notification(attrs(other))

    assert {3, _} = Notifications.mark_all_as_read(u.id)
    assert Notifications.count_unread_notifications(u.id) == 0
    assert Notifications.count_unread_notifications(other.id) == 1
  end

  test "old read notifications are cleaned up, unread and recent ones are kept" do
    u = user_fixture()
    {:ok, old_read} = Notifications.create_notification(attrs(u, %{read: true}))
    {:ok, old_unread} = Notifications.create_notification(attrs(u))
    {:ok, recent_read} = Notifications.create_notification(attrs(u, %{read: true}))

    long_ago = DateTime.utc_now() |> DateTime.add(-40 * 24 * 3600, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(n in UserNotification, where: n.id in ^[old_read.id, old_unread.id]), set: [inserted_at: long_ago])

    Notifications.cleanup_old_notifications(30)

    assert Repo.get(UserNotification, old_read.id) == nil
    assert Repo.get(UserNotification, old_unread.id)
    assert Repo.get(UserNotification, recent_read.id)
  end

  test "one user can't open another's notification" do
    a = user_fixture()
    b = user_fixture()
    {:ok, n} = Notifications.create_notification(attrs(a))

    assert Notifications.get_notification(b.id, n.id) == nil
    assert Notifications.get_notification(a.id, n.id)
  end
end
