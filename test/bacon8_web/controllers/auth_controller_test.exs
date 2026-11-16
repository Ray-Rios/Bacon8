defmodule Bacon8Web.AuthControllerTest do
  # GET /auth/login_success sets the browser's session after the sign-in page has checked the
  # password. Until 2026-11-15 it believed the user_id in the URL: anyone could be signed in as
  # anyone. Now it needs the sign-in page's hand-off token for that user, a minute old at most.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Bacon8.LiveHelpers

  alias Bacon8Web.AuthController

  @endpoint Bacon8Web.Endpoint

  defp visit(params), do: get(build_conn(), "/auth/login_success", params)
  defp signed_in_as(conn), do: Plug.Conn.get_session(conn, :user_id)

  test "a user id alone signs nobody in" do
    admin = person("admin")
    conn = visit(%{"user_id" => admin.id})
    assert redirected_to(conn) == "/login"
    assert signed_in_as(conn) == nil
    # nor with an API token of that user's: it is not the hand-off
    {:ok, jwt, _} = Bacon8.Auth.Guardian.encode_and_sign(admin)
    conn = visit(%{"user_id" => admin.id, "token" => jwt})
    assert redirected_to(conn) == "/login"
    assert signed_in_as(conn) == nil
  end

  test "the hand-off for that user signs them in, with a new session" do
    user = verified()
    conn = visit(%{"user_id" => user.id, "handoff" => AuthController.handoff_token(user.id)})
    assert redirected_to(conn) == "/games"
    assert signed_in_as(conn) == user.id
    # and the session it leaves is the one the pages read
    assert Bacon8Web.Auth.call(Plug.Test.init_test_session(build_conn(), %{"user_id" => user.id}), []).assigns.current_user.id == user.id
  end

  test "one user's hand-off is no use for another account" do
    user = verified()
    admin = person("admin")
    conn = visit(%{"user_id" => admin.id, "handoff" => AuthController.handoff_token(user.id)})
    assert redirected_to(conn) == "/login"
    assert signed_in_as(conn) == nil
  end

  test "a hand-off older than a minute, a forged one, or one for nobody is refused" do
    user = verified()
    old = Phoenix.Token.sign(@endpoint, "login handoff", user.id, signed_at: System.system_time(:second) - 120)
    assert redirected_to(visit(%{"user_id" => user.id, "handoff" => old})) == "/login"
    assert redirected_to(visit(%{"user_id" => user.id, "handoff" => AuthController.handoff_token(user.id) <> "x"})) == "/login"
    wrong_salt = Phoenix.Token.sign(@endpoint, "uploads", user.id)
    assert redirected_to(visit(%{"user_id" => user.id, "handoff" => wrong_salt})) == "/login"
    gone = Ecto.UUID.generate()
    assert redirected_to(visit(%{"user_id" => gone, "handoff" => AuthController.handoff_token(gone)})) == "/login"
    assert redirected_to(visit(%{})) == "/login"
  end

  test "the API token is kept for the page only when it is that user's" do
    user = verified()
    other = verified()
    {:ok, mine, _} = Bacon8.Auth.Guardian.encode_and_sign(user)
    {:ok, theirs, _} = Bacon8.Auth.Guardian.encode_and_sign(other)
    handoff = AuthController.handoff_token(user.id)
    assert Plug.Conn.get_session(visit(%{"user_id" => user.id, "handoff" => handoff, "token" => mine}), :jwt_token) == mine
    assert Plug.Conn.get_session(visit(%{"user_id" => user.id, "handoff" => handoff, "token" => theirs}), :jwt_token) == nil
    assert Plug.Conn.get_session(visit(%{"user_id" => user.id, "handoff" => handoff, "token" => "junk"}), :jwt_token) == nil
  end

  test "signing out empties the session" do
    user = verified()
    conn = get(signed_in(user), "/auth/logout")
    assert redirected_to(conn) == "/"
    assert signed_in_as(conn) == nil
  end
end
