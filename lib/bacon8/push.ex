defmodule Bacon8.Push do
  @moduledoc """
  Phone and desktop notifications through Web Push (2026-11-03).

  Everything that becomes a notification (`Bacon8.Notifications.create_notification/1`: chat
  mentions and invitations, replies to comments, feedback, reports for the admins, announcements
  from /admin/notifications) is also pushed to every device its person turned notifications on
  for: Android phones (Chrome, Firefox, Samsung Internet, Edge), iPhones and iPads once the site
  is on the Home Screen (iOS/iPadOS 16.4 or later), and desktop browsers. No app store, no
  Firebase or Apple account: the browser's own push service carries the message.

  The person says yes in the browser (`Bacon8Web.PushOptIn`, on /profile?tab=notifications and
  in the chat sidebar); the browser hands us a subscription, one row per device here
  (`Bacon8.Push.Subscription`). The worker that shows the notifications is served at
  /push/sw.js with the scope /push/, so it never meets Bacon World's game worker at /.

  ## Setting it up

  Three environment variables (with the other secrets, never in git):
  `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` (a P-256 pair, made by `mix bacon8.gen.vapid`) and
  `VAPID_SUBJECT` (`mailto:` an address the push services can write to). Without them the site
  offers no notifications and sends nothing. Changing the pair later stops every device until its
  person turns notifications on again.

  ## Safety

    * The server only ever calls the push services' own hosts (`allowed_endpoint?/1`). A
      subscription is a URL the browser gives us and the server POSTs to it, so any URL would let
      a visitor make the server call into the private network.
    * What we send is encrypted for the device (RFC 8291, `Bacon8.Push.WebPush`): the push
      service carries it but can't read it. A device with previews off gets only "something is
      new" on its lock screen.
    * A device that has gone away (404/410) is forgotten at once, one that keeps failing after
      five tries. Each person keeps at most 20 devices.
  """
  import Ecto.Query
  require Logger

  alias Bacon8.Repo
  alias Bacon8.Push.{Subscription, WebPush}

  @hosts ~w(fcm.googleapis.com android.googleapis.com updates.push.services.mozilla.com web.push.apple.com)
  @host_suffixes ~w(.push.apple.com .notify.windows.com .push.services.mozilla.com)
  @max_per_user 20
  @max_failures 5
  @ttl 24 * 3600

  # ---------------------------------------------------------------- configuration

  @doc "`:ok` when push is set up, `:off` when it isn't, `{:error, why}` when the keys are wrong."
  def status do
    case raw_config() do
      nil -> :off
      conf -> if valid_vapid?(conf), do: :ok, else: {:error, "VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY aren't a P-256 key pair (make one with mix bacon8.gen.vapid)."}
    end
  end

  @doc "True when push is set up and its keys are good."
  def configured?, do: status() == :ok

  @doc "The keys and contact (`%{public, private, subject}`), or nil when push isn't usable."
  def config, do: if(configured?(), do: raw_config())

  @doc "The public key browsers subscribe with (base64url), or nil."
  def public_key, do: (c = config()) && c.public

  defp opts, do: Application.get_env(:bacon8, __MODULE__, [])

  defp raw_config do
    o = opts()
    env = if Keyword.get(o, :read_env, true), do: &System.get_env/1, else: fn _ -> nil end
    public = Keyword.get(o, :public_key) || env.("VAPID_PUBLIC_KEY")
    private = Keyword.get(o, :private_key) || env.("VAPID_PRIVATE_KEY")
    subject = Keyword.get(o, :subject) || env.("VAPID_SUBJECT")

    if present?(public) and present?(private) and present?(subject),
      do: %{public: String.trim(public), private: String.trim(private), subject: String.trim(subject)}
  end

  defp valid_vapid?(%{public: public, private: private}) do
    with {:ok, <<4, _::binary-size(64)>> = pub} <- unb64(public),
         {:ok, <<_::binary-size(32)>> = priv} <- unb64(private) do
      # the private key must make the public one
      match?({^pub, _}, :crypto.generate_key(:ecdh, :prime256v1, priv))
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp present?(s), do: is_binary(s) and String.trim(s) != ""

  # ---------------------------------------------------------------- devices

  @doc """
  Saves the device `user` turned notifications on for: the browser's `PushSubscription.toJSON()`
  (`"endpoint"`, `"keys" => %{"p256dh", "auth"}`). A device belongs to whoever turned it on
  last (a shared tablet changes hands).
  """
  def subscribe(user, params, user_agent \\ nil)

  def subscribe(%{id: user_id}, %{"endpoint" => endpoint, "keys" => %{"p256dh" => p256dh, "auth" => auth}}, user_agent)
      when is_binary(endpoint) and is_binary(p256dh) and is_binary(auth) do
    p256dh = String.trim_trailing(p256dh, "=")
    auth = String.trim_trailing(auth, "=")

    cond do
      not allowed_endpoint?(endpoint) ->
        {:error, "That browser's push service isn't one this site sends to."}

      not valid_device_keys?(p256dh, auth) ->
        {:error, "That browser sent keys we can't use."}

      true ->
        attrs = %{user_id: user_id, endpoint: endpoint, p256dh: p256dh, auth: auth, user_agent: user_agent}

        result =
          case Repo.get_by(Subscription, endpoint: endpoint) do
            nil -> %Subscription{} |> Subscription.changeset(attrs) |> Repo.insert()
            sub -> sub |> Subscription.changeset(attrs) |> Ecto.Changeset.change(failures: 0) |> Repo.update()
          end

        with {:ok, sub} <- result do
          trim(user_id)
          {:ok, sub}
        end
    end
  end

  def subscribe(_user, _params, _user_agent), do: {:error, "That isn't a push subscription."}

  defp valid_device_keys?(p256dh, auth) do
    with {:ok, <<4, _::binary-size(64)>> = point} <- unb64(p256dh),
         {:ok, <<_::binary-size(16)>>} <- unb64(auth) do
      # a point that isn't on the curve would fail every send; find out now
      {_pub, priv} = :crypto.generate_key(:ecdh, :prime256v1)
      is_binary(:crypto.compute_key(:ecdh, point, priv, :prime256v1))
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp trim(user_id) do
    keep = from(s in Subscription, where: s.user_id == ^user_id, order_by: [desc: s.updated_at, desc: s.id], limit: @max_per_user, select: s.id)
    Repo.delete_all(from s in Subscription, where: s.user_id == ^user_id and s.id not in subquery(keep))
  end

  @doc "Forgets `user`'s device with this endpoint (the browser turned it off)."
  def unsubscribe(%{id: user_id}, endpoint) when is_binary(endpoint) do
    {n, _} = Repo.delete_all(from s in Subscription, where: s.user_id == ^user_id and s.endpoint == ^endpoint)
    n
  end

  def unsubscribe(_user, _endpoint), do: 0

  @doc "True when this endpoint is one of `user`'s devices."
  def registered?(%{id: user_id}, endpoint) when is_binary(endpoint),
    do: Repo.exists?(from s in Subscription, where: s.user_id == ^user_id and s.endpoint == ^endpoint)

  def registered?(_user, _endpoint), do: false

  @doc "A person's devices, newest first."
  def list_subscriptions(user_id), do: Repo.all(from s in Subscription, where: s.user_id == ^user_id, order_by: [desc: s.inserted_at])

  @doc "Removes one of `user`'s devices by id."
  def remove_subscription(%{id: user_id}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> elem(Repo.delete_all(from s in Subscription, where: s.user_id == ^user_id and s.id == ^id), 0)
      :error -> 0
    end
  end

  @doc "Turns lock-screen previews on or off for one of `user`'s devices."
  def set_previews(%{id: user_id}, id, on?) when is_boolean(on?) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> elem(Repo.update_all(from(s in Subscription, where: s.user_id == ^user_id and s.id == ^id), set: [previews: on?]), 0)
      :error -> 0
    end
  end

  @doc "How many devices and people have notifications on."
  def stats do
    %{
      devices: Repo.aggregate(Subscription, :count),
      people: Repo.one(from s in Subscription, select: count(s.user_id, :distinct)) || 0
    }
  end

  @doc "A short name for a device from its user agent (\"Chrome on Android\")."
  def device_label(nil), do: "A device"

  def device_label(ua) do
    os =
      cond do
        ua =~ "iPhone" -> "iPhone"
        ua =~ "iPad" -> "iPad"
        ua =~ "Android" -> "Android"
        ua =~ "Windows" -> "Windows"
        ua =~ "CrOS" -> "ChromeOS"
        ua =~ "Macintosh" or ua =~ "Mac OS X" -> "Mac"
        ua =~ "Linux" -> "Linux"
        true -> nil
      end

    browser =
      cond do
        ua =~ "Edg" -> "Edge"
        ua =~ "OPR/" -> "Opera"
        ua =~ "SamsungBrowser" -> "Samsung Internet"
        ua =~ "Firefox/" or ua =~ "FxiOS" -> "Firefox"
        ua =~ "CriOS" or ua =~ "Chrome/" -> "Chrome"
        ua =~ "Safari/" -> "Safari"
        os in ["iPhone", "iPad"] -> "Home Screen app"
        true -> "A browser"
      end

    if os, do: "#{browser} on #{os}", else: browser
  end

  # ---------------------------------------------------------------- sending

  @doc """
  Pushes a notification (`Bacon8.Notifications.UserNotification`) to its person's devices, in the
  background. Does nothing when push isn't set up.
  """
  def notify(%{user_id: user_id} = n) when not is_nil(user_id) do
    if configured?() do
      meta = n.metadata || %{}
      path = meta["path"] || meta[:path]
      tag = if n.source_kind && n.source_id, do: "#{n.source_kind}:#{n.source_id}", else: "n:#{n.id}"
      urgency = if (meta["urgent"] || meta[:urgent]) == true, do: "high", else: "normal"
      payload = payload(n.title, n.content, path, tag) |> Map.put(:urgency, urgency)
      background(fn -> send_to_user(user_id, payload) end)
    end

    :ok
  end

  def notify(_), do: :ok

  @doc "A payload: a title, a short message, the page to open (a path on this site) and a tag (same tag, one notification)."
  def payload(title, body, path, tag) do
    %{title: clip(title || "Bacon8", 80), body: clip(body || "", 240), url: safe_path(path), tag: clip(to_string(tag || "bacon8"), 64)}
  end

  @doc "Sends a test to all of `user`'s devices now; returns what happened to each."
  def send_test(%{id: user_id}) do
    send_to_user(user_id, payload("Bacon8", "Notifications work on this device.", "/profile?tab=notifications", "bacon8-test"))
  end

  @doc "Sends `payload` to all of a person's devices now; returns what happened to each."
  def send_to_user(user_id, payload) do
    case config() do
      nil -> []
      conf -> user_id |> list_subscriptions() |> Enum.map(&deliver(&1, payload, conf))
    end
  end

  @doc false
  def deliver(%Subscription{} = sub, payload, conf) do
    if allowed_endpoint?(sub.endpoint) do
      body =
        payload
        |> for_device(sub)
        |> Jason.encode!()
        |> WebPush.encrypt(WebPush.unb64(sub.p256dh), WebPush.unb64(sub.auth))

      headers = [
        {"ttl", Integer.to_string(@ttl)},
        {"urgency", Map.get(payload, :urgency, "normal")},
        {"content-encoding", "aes128gcm"},
        {"content-type", "application/octet-stream"},
        {"authorization", WebPush.vapid_header(sub.endpoint, conf, conf.subject)}
      ]

      record(sub, sender().(sub.endpoint, headers, body))
    else
      forget(sub)
      :forgotten
    end
  rescue
    e ->
      Logger.warning("push: couldn't send to a device: #{Exception.message(e)}")
      record(sub, {:error, :exception})
  end

  defp for_device(payload, %Subscription{previews: false}),
    do: %{title: "Bacon8", body: "You have a new notification.", url: payload.url, tag: payload.tag}

  defp for_device(payload, _sub), do: Map.delete(payload, :urgency)

  defp record(sub, {:ok, status}) when status in 200..299 do
    Repo.update_all(from(s in Subscription, where: s.id == ^sub.id), set: [failures: 0, last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)])
    :sent
  end

  defp record(sub, {:ok, status}) when status in [404, 410] do
    forget(sub)
    :gone
  end

  defp record(sub, result) do
    Logger.warning("push: #{host(sub.endpoint)} refused a message: #{inspect(result)}")

    if sub.failures + 1 >= @max_failures,
      do: forget(sub),
      else: Repo.update_all(from(s in Subscription, where: s.id == ^sub.id), inc: [failures: 1])

    {:failed, result}
  end

  defp forget(sub), do: Repo.delete_all(from s in Subscription, where: s.id == ^sub.id)

  defp host(endpoint), do: URI.parse(endpoint).host

  defp sender do
    case Keyword.get(opts(), :sender) do
      fun when is_function(fun, 3) -> fun
      _ -> &post/3
    end
  end

  # Finch follows no redirects, so a push service can't send us anywhere else.
  defp post(url, headers, body) do
    case Finch.request(Finch.build(:post, url, headers, body), Bacon8.Finch, receive_timeout: 15_000) do
      {:ok, %Finch.Response{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Runs `fun` in the background (inline when configured `async: false`, as in tests)."
  def background(fun) do
    cond do
      Keyword.get(opts(), :async, true) == false -> fun.()
      Process.whereis(Bacon8.PushTaskSupervisor) -> Task.Supervisor.start_child(Bacon8.PushTaskSupervisor, fun)
      true -> Task.start(fun)
    end
  end

  @doc """
  True for an https URL on a push service's own host (Google's for Chrome, Android, Samsung and
  Opera; Mozilla's; Apple's; Microsoft's for Edge), plus any `extra_hosts` configured.
  """
  def allowed_endpoint?(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: "https", host: host, port: port, userinfo: nil} when is_binary(host) and port in [nil, 443] ->
        host = String.downcase(host)
        host in @hosts or host in Keyword.get(opts(), :extra_hosts, []) or Enum.any?(@host_suffixes, &String.ends_with?(host, &1))

      _ ->
        false
    end
  end

  def allowed_endpoint?(_), do: false

  defp safe_path("/" <> rest = path) when is_binary(path) do
    if String.starts_with?(rest, ["/", "\\"]) or String.contains?(path, ["\\", "\n", "\r", " "]), do: "/", else: String.slice(path, 0, 300)
  end

  defp safe_path(_), do: "/"

  defp clip(s, n) do
    s = s |> to_string() |> String.replace(~r/\s+/u, " ") |> String.trim()
    if String.length(s) > n, do: String.slice(s, 0, n - 1) <> "…", else: s
  end

  defp unb64(s) when is_binary(s), do: Base.url_decode64(String.trim_trailing(s, "="), padding: false)
  defp unb64(_), do: :error
end
