defmodule Bacon8.PushTest do
  # Phone and desktop notifications (2026-11-03): RFC 8291 encryption and RFC 8292 VAPID, which
  # push services we'll call, devices saved and forgotten, notifications pushed, the pages.
  use Bacon8.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Bacon8.LiveHelpers

  alias Bacon8.Push
  alias Bacon8.Push.{Subscription, WebPush}

  @endpoint Bacon8Web.Endpoint

  # RFC 8291 Appendix A
  defp d(s), do: Base.url_decode64!(s, padding: false)
  @as_private "yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw"
  @as_public "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8"
  @ua_public "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
  @auth "BTBZMqHH6r4Tts7J_aSIgg"
  @salt "DGv6ra1nlYgDCS1FRnbzlw"
  @expected "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"

  # what a device does with what we send (RFC 8291 in reverse)
  defp decrypt(body, ua_public, ua_private, auth) do
    <<salt::binary-size(16), _rs::32, 65, as_public::binary-size(65), rest::binary>> = body
    ct_size = byte_size(rest) - 16
    <<ct::binary-size(ct_size), tag::binary-size(16)>> = rest
    hmac = &:crypto.mac(:hmac, :sha256, &1, &2)
    ecdh = :crypto.compute_key(:ecdh, as_public, ua_private, :prime256v1)
    ikm = hmac.(hmac.(auth, ecdh), "WebPush: info" <> <<0>> <> ua_public <> as_public <> <<1>>)
    prk = hmac.(salt, ikm)
    <<cek::binary-size(16), _::binary>> = hmac.(prk, "Content-Encoding: aes128gcm" <> <<0, 1>>)
    <<nonce::binary-size(12), _::binary>> = hmac.(prk, "Content-Encoding: nonce" <> <<0, 1>>)
    plain = :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, ct, <<>>, tag, false)
    String.trim_trailing(plain, <<2>>)
  end

  defp device do
    {pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)
    auth = :crypto.strong_rand_bytes(16)
    n = System.unique_integer([:positive])

    %{
      json: %{"endpoint" => "https://fcm.googleapis.com/fcm/send/device-#{n}", "keys" => %{"p256dh" => WebPush.b64(pub), "auth" => WebPush.b64(auth)}},
      pub: pub,
      priv: priv,
      auth: auth
    }
  end

  # push on, with a sender that hands each request to the test instead of the internet
  defp push_on(status \\ 201) do
    keys = WebPush.generate_keys()
    test = self()

    sender = fn url, headers, body ->
      send(test, {:pushed, url, Map.new(headers), body})
      {:ok, if(is_function(status), do: status.(url), else: status)}
    end

    Application.put_env(:bacon8, Push, read_env: false, public_key: keys.public, private_key: keys.private, subject: "mailto:admin@example.test", sender: sender, async: false)
    on_exit(fn -> Application.put_env(:bacon8, Push, read_env: false) end)
    keys
  end

  describe "the protocols" do
    test "encryption matches RFC 8291's own example" do
      body = WebPush.encrypt("When I grow up, I want to be a watermelon", d(@ua_public), d(@auth), salt: d(@salt), keys: {d(@as_public), d(@as_private)})
      assert WebPush.b64(body) == @expected
    end

    test "a VAPID header is an ES256 token for the push service's origin, signed by our key" do
      keys = WebPush.generate_keys()
      "vapid t=" <> rest = WebPush.vapid_header("https://fcm.googleapis.com/fcm/send/abc", keys, "mailto:a@example.test", 1_000_000)
      [jwt, "k=" <> k] = String.split(rest, ", ")
      assert k == keys.public
      assert WebPush.verify_jwt(jwt, keys.public)
      refute WebPush.verify_jwt(jwt, WebPush.generate_keys().public)
      [_, claims, _] = String.split(jwt, ".")
      assert %{"aud" => "https://fcm.googleapis.com", "exp" => 1_043_200, "sub" => "mailto:a@example.test"} = Jason.decode!(Base.url_decode64!(claims, padding: false))
    end
  end

  describe "setting it up" do
    test "off without keys; a pair that doesn't match is reported, not used" do
      assert Push.status() == :off
      refute Push.public_key()
      a = WebPush.generate_keys()
      b = WebPush.generate_keys()
      Application.put_env(:bacon8, Push, read_env: false, public_key: a.public, private_key: b.private, subject: "mailto:x@example.test")
      on_exit(fn -> Application.put_env(:bacon8, Push, read_env: false) end)
      assert {:error, _} = Push.status()
      refute Push.config()
      push_on()
      assert Push.status() == :ok and Push.public_key()
    end

    test "the server only calls push services' own hosts" do
      for ok <- ~w(https://fcm.googleapis.com/fcm/send/x https://updates.push.services.mozilla.com/wpush/v2/x https://web.push.apple.com/x https://wns2-bl2p.notify.windows.com/w/?token=x),
          do: assert(Push.allowed_endpoint?(ok), ok)

      for bad <- ~w(http://fcm.googleapis.com/x https://localhost/x https://127.0.0.1/x https://169.254.169.254/latest https://fcm.googleapis.com.evil.test/x
                    https://evilpush.apple.com/x https://fcm.googleapis.com:8443/x https://user@fcm.googleapis.com/x https://bacon8.example/push),
          do: refute(Push.allowed_endpoint?(bad), bad)

      refute Push.allowed_endpoint?(nil)
    end
  end

  describe "devices" do
    test "saved, owned by whoever turned them on last, at most 20 a person, forgotten on request" do
      push_on()
      alice = user_fixture()
      bob = user_fixture()
      dev = device()

      {:ok, sub} = Push.subscribe(alice, dev.json, "Mozilla/5.0 (Linux; Android 15) Chrome/131.0")
      assert Push.registered?(alice, sub.endpoint)
      assert Push.device_label(sub.user_agent) == "Chrome on Android"

      {:ok, _} = Push.subscribe(bob, dev.json)
      refute Push.registered?(alice, sub.endpoint)
      assert Push.registered?(bob, sub.endpoint)

      for _ <- 1..21, do: {:ok, _} = Push.subscribe(alice, device().json)
      assert length(Push.list_subscriptions(alice.id)) == 20

      assert Push.unsubscribe(bob, sub.endpoint) == 1
      refute Push.registered?(bob, sub.endpoint)
    end

    test "refuses a push service we don't know and keys that aren't keys" do
      user = user_fixture()
      dev = device()
      assert {:error, _} = Push.subscribe(user, Map.put(dev.json, "endpoint", "https://10.0.0.5/steal"))
      assert {:error, _} = Push.subscribe(user, put_in(dev.json, ["keys", "p256dh"], WebPush.b64(:crypto.strong_rand_bytes(65))))
      assert {:error, _} = Push.subscribe(user, put_in(dev.json, ["keys", "auth"], "short"))
      assert {:error, _} = Push.subscribe(user, %{"endpoint" => "https://fcm.googleapis.com/x"})
      assert Repo.aggregate(Subscription, :count) == 0
    end
  end

  describe "sending" do
    test "a notification reaches the person's devices, encrypted for each, and opens its page" do
      keys = push_on()
      user = user_fixture()
      dev = device()
      {:ok, _} = Push.subscribe(user, dev.json)

      {:ok, _} =
        Bacon8.Notifications.create_notification(%{
          type: "mention",
          title: "Sam mentioned you",
          content: "lunch?",
          user_id: user.id,
          source_kind: "chat_channel",
          source_id: Ecto.UUID.generate(),
          metadata: %{path: "/chat/abc"}
        })

      assert_received {:pushed, url, headers, body}
      assert url == dev.json["endpoint"]
      assert headers["content-encoding"] == "aes128gcm" and headers["ttl"] == "86400"
      "vapid t=" <> rest = headers["authorization"]
      [jwt, "k=" <> k] = String.split(rest, ", ")
      assert k == keys.public and WebPush.verify_jwt(jwt, keys.public)

      msg = body |> decrypt(dev.pub, dev.priv, dev.auth) |> Jason.decode!()
      assert %{"title" => "Sam mentioned you", "body" => "lunch?", "url" => "/chat/abc", "tag" => "chat_channel:" <> _} = msg
      assert Repo.one(Subscription).last_used_at
    end

    test "previews off: the lock screen only says something is new; links stay on this site" do
      push_on()
      user = user_fixture()
      dev = device()
      {:ok, sub} = Push.subscribe(user, dev.json)
      1 = Push.set_previews(user, sub.id, false)

      [:sent] = Push.send_to_user(user.id, Push.payload("Secret plans", "the password is…", "//evil.test/x", "t"))
      assert_received {:pushed, _, _, body}
      msg = body |> decrypt(dev.pub, dev.priv, dev.auth) |> Jason.decode!()
      assert msg["title"] == "Bacon8" and msg["body"] == "You have a new notification." and msg["url"] == "/"
    end

    @tag capture_log: true
    test "a device that's gone is forgotten; one that keeps failing is dropped after five tries" do
      push_on(fn url -> if url =~ "gone", do: 410, else: 500 end)
      user = user_fixture()
      {:ok, gone} = Push.subscribe(user, Map.put(device().json, "endpoint", "https://fcm.googleapis.com/fcm/send/gone"))
      {:ok, flaky} = Push.subscribe(user, device().json)

      Push.send_test(user)
      refute Repo.get(Subscription, gone.id)
      assert Repo.get(Subscription, flaky.id).failures == 1
      for _ <- 1..4, do: Push.send_test(user)
      refute Repo.get(Subscription, flaky.id)
    end

    test "with push off, notifications are only in the bell" do
      user = user_fixture()
      {:ok, _} = Bacon8.Notifications.create_notification(%{type: "system", title: "hi", user_id: user.id})
      refute_received {:pushed, _, _, _}
    end
  end

  describe "pages" do
    test "the worker is served from /push/ as JavaScript" do
      conn = get(build_conn(), "/push/sw.js")
      assert response(conn, 200) =~ "showNotification"
      assert hd(Plug.Conn.get_resp_header(conn, "content-type")) =~ "javascript"
    end

    test "the profile's Notifications tab turns a device on and off" do
      push_on()
      user = person("member")
      dev = device()
      {:ok, view, html} = live(signed_in(user), "/profile?tab=notifications")
      assert html =~ "Notifications on your phone and computer"

      el = element(view, "#profile-push")
      assert render_hook(el, "push_device", %{supported: true, ios: false, standalone: false, permission: "default", endpoint: nil}) =~ "Turn on notifications on this device"
      assert render_hook(el, "push_subscribed", %{subscription: dev.json, ua: "Mozilla/5.0 (iPhone) Mobile/15E148"}) =~ "On for this device"
      assert Push.registered?(user, dev.json["endpoint"])
      assert render(view) =~ "Home Screen app on iPhone"

      assert render_hook(el, "push_unsubscribed", %{endpoint: dev.json["endpoint"]}) =~ "off for this device"
      refute Push.registered?(user, dev.json["endpoint"])
    end

    test "an iPhone in Safari is told to add Bacon8 to the Home Screen" do
      push_on()
      {:ok, view, _} = live(signed_in(person("member")), "/profile?tab=notifications")
      assert render_hook(element(view, "#profile-push"), "push_device", %{supported: false, ios: true, standalone: false, permission: "unsupported"}) =~ "Add to Home Screen"
    end

    test "admins see the state, make a key pair once, and announce" do
      admin = person("admin")
      other_admin = person("admin")
      member = person("member")
      {:ok, view, html} = live(signed_in(admin), "/admin/notifications")
      assert html =~ "Not set up"
      assert render_click(view, "make_keys") =~ "VAPID_PRIVATE_KEY="

      push_on()
      {:ok, view, html} = live(signed_in(admin), "/admin/notifications")
      assert html =~ "On."

      view |> form("form[phx-submit=announce]", %{a: %{title: "Server moving tonight", body: "Back by 9.", path: "/blog", audience: "admins"}}) |> render_submit()
      assert render(view) =~ "Announced to"
      titles = for u <- [admin, other_admin, member], do: Repo.exists?(from n in Bacon8.Notifications.UserNotification, where: n.user_id == ^u.id and n.title == "Server moving tonight")
      assert titles == [true, true, false]
    end

    test "members can't open the admin page" do
      assert {:error, {_redirect, _}} = live(signed_in(person("member")), "/admin/notifications")
    end
  end
end
