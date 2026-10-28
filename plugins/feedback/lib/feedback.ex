defmodule Feedback do
  @moduledoc """
  Suggestions & Bugs (the `feedback` plugin, 2026-10-27).

  Members write suggestions and bug reports about the site or one of its games, with
  screenshots; members vote them up or down; admins edit, approve, reject or mark duplicates,
  and **submit** approved items to Claude. Claude's runner, a program on the owner's PC, takes
  submitted items one at a time through the agent API (`FeedbackWeb.AgentController`), has
  Claude Code fix them, test them and commit, and reports back here; with auto-deploy on it
  also deploys, otherwise an admin presses Deploy. README.md has the whole loop.

  Who may do what:

    * **Guests** (no account, or the `guest` role), banned and inactive accounts: nothing, not
      even read. The page is for members.
    * **Members**: read, write, vote; edit or delete their own item while it is still open.
    * **Admins** (`Bacon8.Permissions.admin?/1`, the account flag): everything else.

  Statuses:

      open -> approved -> queued -> in_progress -> ready -> deploying -> deployed
                                              \\-> deployed (auto-deploy)
                                              \\-> needs_info / failed  (an admin can submit again)
      open/approved -> rejected | duplicate   (an admin can reopen)
  """

  import Ecto.Query, warn: false

  alias Bacon8.{Notifications, Permissions, Repo, Storage}
  alias Bacon8.Drive.{Blob, Sniff}
  alias Feedback.{Agent, Event, Item, Shot, Vote}

  @topic "feedback"
  @image_types ~w(image/png image/jpeg image/webp image/gif)
  @max_shots 6
  @max_shot_bytes 10_000_000

  # Statuses Claude's runner may see (and whose screenshots it may fetch).
  @agent_visible ~w(queued in_progress needs_info ready deploying)
  # While any item is in one of these the runner takes nothing new: one change at a time, so a
  # deploy ships exactly what was reviewed.
  @busy ~w(in_progress ready deploying)

  def topic, do: @topic
  def image_types, do: @image_types
  def max_shots, do: @max_shots
  def max_shot_bytes, do: @max_shot_bytes

  # ---------------------------------------------------------------------------
  # Who
  # ---------------------------------------------------------------------------

  @doc "True for a signed-in, active account that is not a guest or banned. Admins always."
  def member?(nil), do: false

  def member?(%{} = user),
    do:
      admin?(user) or
        (Map.get(user, :role) not in ["guest", "banned"] and Map.get(user, :status) == "active")

  @doc "True for an admin (the account flag)."
  def admin?(user), do: Permissions.admin?(user)

  @doc "True when `user` may change the item's text and screenshots."
  def can_edit?(%Item{} = item, user) do
    cond do
      not member?(user) -> false
      admin?(user) -> item.status not in ["in_progress", "deploying"]
      true -> item.author_id == user.id and item.status == "open"
    end
  end

  @doc "True when `user` may vote on the item."
  def can_vote?(%Item{status: status}, user),
    do: member?(user) and status not in ["rejected", "duplicate"]

  # ---------------------------------------------------------------------------
  # Reading
  # ---------------------------------------------------------------------------

  @status_groups %{
    "active" => ~w(open approved queued in_progress needs_info ready deploying),
    "live" => ~w(deployed),
    "closed" => ~w(rejected duplicate failed),
    "review" => ~w(open),
    "claude" => ~w(queued in_progress needs_info ready deploying failed)
  }

  def status_groups, do: Map.keys(@status_groups)

  @doc """
  Items for the list. Options: `:kind` ("suggestion", "bug" or nil for both), `:area`, `:group`
  ("active" (default), "live", "closed", "review", "claude", "all"), `:sort` ("top" (default) or
  "new"), `:q` (words in the title or body), `:limit` (default 100).
  """
  def list_items(viewer, opts \\ []) do
    if member?(viewer) do
      limit = opts |> Keyword.get(:limit, 100) |> min(500)

      Item
      |> filter_kind(opts[:kind])
      |> filter_area(opts[:area])
      |> filter_group(Keyword.get(opts, :group, "active"))
      |> filter_q(opts[:q])
      |> order(Keyword.get(opts, :sort, "top"))
      |> limit(^limit)
      |> preload([:author, :shots])
      |> Repo.all()
      |> with_vote_info(viewer)
    else
      []
    end
  end

  defp filter_kind(q, kind) when kind in ["suggestion", "bug"], do: where(q, [i], i.kind == ^kind)
  defp filter_kind(q, _), do: q

  defp filter_area(q, area) when is_binary(area) and area not in ["", "all"],
    do: where(q, [i], i.area == ^area)

  defp filter_area(q, _), do: q

  defp filter_group(q, group) do
    case Map.fetch(@status_groups, group) do
      {:ok, statuses} -> where(q, [i], i.status in ^statuses)
      :error -> q
    end
  end

  defp filter_q(q, text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        q

      t ->
        like = "%" <> String.replace(t, ~r/[\\%_]/, "\\\\\\0") <> "%"
        where(q, [i], ilike(i.title, ^like) or ilike(i.body, ^like))
    end
  end

  defp filter_q(q, _), do: q

  defp order(q, "new"), do: order_by(q, [i], desc: i.inserted_at)
  defp order(q, _), do: order_by(q, [i], desc: i.score, desc: i.inserted_at)

  # Fills in each item's viewer vote and up/down counts, read together from one query.
  defp with_vote_info([], _), do: []

  defp with_vote_info(items, %{id: user_id}) do
    ids = Enum.map(items, & &1.id)

    by_item =
      Repo.all(
        from(v in Vote,
          where: v.item_id in ^ids,
          select: {v.item_id, v.user_id, v.value}
        )
      )
      |> Enum.group_by(fn {item_id, _, _} -> item_id end)

    Enum.map(items, fn item ->
      votes = Map.get(by_item, item.id, [])

      %{
        item
        | my_vote: Enum.find_value(votes, fn {_, uid, value} -> uid == user_id && value end),
          upvotes: Enum.count(votes, fn {_, _, value} -> value == 1 end),
          downvotes: Enum.count(votes, fn {_, _, value} -> value == -1 end)
      }
    end)
  end

  @doc "One item with its screenshots, history, the viewer's vote and the vote counts, or nil (also for a non-member)."
  def get_item(id, viewer) do
    with true <- member?(viewer),
         {:ok, _} <- Ecto.UUID.cast(id),
         %Item{} = item <- Repo.get(Item, id) do
      item
      |> Repo.preload([
        :author,
        :approved_by,
        :submitted_by,
        :duplicate_of,
        :shots,
        events: :actor
      ])
      |> List.wrap()
      |> with_vote_info(viewer)
      |> hd()
    else
      _ -> nil
    end
  end

  @doc "An item by its number (#12), or nil."
  def get_by_number(number) when is_integer(number), do: Repo.get_by(Item, number: number)

  def get_by_number(number) when is_binary(number) do
    case Integer.parse(String.trim_leading(String.trim(number), "#")) do
      {n, ""} -> get_by_number(n)
      _ -> nil
    end
  end

  @doc "A screenshot `viewer` may see (members see every item's), or nil."
  def get_shot(id, viewer) do
    with true <- member?(viewer),
         {:ok, _} <- Ecto.UUID.cast(id) do
      Repo.get(Shot, id)
    else
      _ -> nil
    end
  end

  @doc "Counts by status, for the admin dashboard and the page's tabs."
  def counts do
    Repo.all(from(i in Item, group_by: i.status, select: {i.status, count(i.id)})) |> Map.new()
  end

  @doc "Where an item can be about: the site, then each active game."
  def areas do
    games =
      for g <- Bacon8.Plugins.active_games(),
          slug = Map.get(g, :slug) || Map.get(g, :plugin_slug),
          is_binary(slug),
          uniq: true do
        {slug, g.name}
      end

    [{"site", "The site"} | Enum.sort_by(games, &elem(&1, 1))]
  end

  @doc "A readable name for an area slug."
  def area_name(area) do
    case List.keyfind(areas(), area, 0) do
      {_, name} -> name
      nil -> area |> to_string() |> String.replace("_", " ") |> String.capitalize()
    end
  end

  # ---------------------------------------------------------------------------
  # Writing
  # ---------------------------------------------------------------------------

  @doc """
  A member writes a suggestion or bug. `uploads` is a list of `{path, filename}` (LiveView
  upload temp files); each must be a PNG, JPEG, WebP or GIF by its bytes. The author's own
  vote counts (+1). Returns `{:ok, item}` or `{:error, changeset | reason}`.
  """
  def create_item(user, attrs, uploads \\ []) do
    cond do
      not member?(user) ->
        {:error, :forbidden}

      length(uploads) > @max_shots ->
        {:error, :too_many_shots}

      rate_limited?(user) ->
        {:error, :rate_limited}

      true ->
        Repo.transaction(fn ->
          item =
            %Item{author_id: user.id, status: "open", score: 1}
            |> Item.content_changeset(attrs)
            |> Repo.insert()
            |> case do
              {:ok, item} -> item
              {:error, cs} -> Repo.rollback(cs)
            end

          Repo.insert!(%Vote{item_id: item.id, user_id: user.id, value: 1})

          for {{path, name}, pos} <- Enum.with_index(uploads) do
            case store_shot(item, path, name, pos) do
              {:ok, _} -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end
          end

          event!(item, user, nil, "open", nil)
          item
        end)
        |> broadcast(:created)
    end
  end

  defp rate_limited?(user) do
    if admin?(user) do
      false
    else
      Bacon8.RateLimiter.check_and_increment_rate(
        {:feedback_create, user.id},
        10,
        :timer.hours(1)
      ) != :ok
    end
  rescue
    # The limiter's table isn't there (a test without the app's processes): don't block.
    ArgumentError -> false
  end

  @doc "Changes the text (and, for an admin, the notes for Claude)."
  def update_item(%Item{} = item, user, attrs) do
    if can_edit?(item, user) do
      cs =
        if admin?(user),
          do: Item.admin_changeset(item, attrs),
          else: Item.content_changeset(item, attrs)

      Repo.transaction(fn ->
        case Repo.update(cs) do
          {:ok, updated} ->
            if cs.changes != %{},
              do:
                event!(
                  updated,
                  user,
                  nil,
                  nil,
                  "edited " <> Enum.map_join(Map.keys(cs.changes), ", ", &to_string/1)
                )

            updated

          {:error, cs} ->
            Repo.rollback(cs)
        end
      end)
      |> broadcast(:updated)
    else
      {:error, :forbidden}
    end
  end

  @doc "Adds screenshots (`{path, filename}`), up to #{@max_shots} in all."
  def add_shots(%Item{} = item, user, uploads) do
    have = Repo.aggregate(from(s in Shot, where: s.item_id == ^item.id), :count)

    cond do
      not can_edit?(item, user) ->
        {:error, :forbidden}

      have + length(uploads) > @max_shots ->
        {:error, :too_many_shots}

      true ->
        Repo.transaction(fn ->
          for {{path, name}, i} <- Enum.with_index(uploads) do
            case store_shot(item, path, name, have + i) do
              {:ok, shot} -> shot
              {:error, reason} -> Repo.rollback(reason)
            end
          end
        end)
        |> broadcast_item(item, :updated)
    end
  end

  @doc "Removes a screenshot (its body is collected later by blob GC if nothing else uses it)."
  def delete_shot(%Shot{} = shot, user) do
    item = Repo.get!(Item, shot.item_id)

    if can_edit?(item, user) do
      now = DateTime.utc_now()

      Repo.update_all(from(b in Blob, where: b.sha256 == ^shot.sha256),
        set: [last_referenced_at: now]
      )

      Repo.delete(shot) |> broadcast_item(item, :updated)
    else
      {:error, :forbidden}
    end
  end

  defp store_shot(item, path, name, position) do
    sniffed = Sniff.sniff_file(path)
    size = File.stat!(path).size

    cond do
      sniffed not in @image_types ->
        {:error, :not_an_image}

      size > @max_shot_bytes ->
        {:error, :too_large}

      true ->
        sha = Storage.sha256_file(path)
        now = DateTime.utc_now()

        Repo.insert_all(
          Blob,
          [
            %{
              sha256: sha,
              size: size,
              content_type: sniffed,
              last_referenced_at: now,
              inserted_at: now
            }
          ],
          on_conflict: [set: [last_referenced_at: now]],
          conflict_target: :sha256
        )

        case Storage.put_new(sha, path) do
          {:ok, _} ->
            Repo.insert(%Shot{
              item_id: item.id,
              sha256: sha,
              filename: clean_filename(name),
              content_type: sniffed,
              byte_size: size,
              position: position
            })

          {:error, reason} ->
            {:error, {:storage_failed, reason}}
        end
    end
  end

  defp clean_filename(name) do
    name
    |> to_string()
    |> String.replace("\\", "/")
    |> Path.basename()
    |> String.replace(~r/[\x00-\x1F\x7F]/u, "")
    |> String.slice(0, 120)
    |> case do
      "" -> "screenshot"
      n -> n
    end
  end

  @doc "Deletes an item: its author while it is open, an admin unless Claude is busy with it."
  def delete_item(%Item{} = item, user) do
    if can_edit?(item, user) do
      Repo.delete(item) |> broadcast(:deleted)
    else
      {:error, :forbidden}
    end
  end

  @doc "Votes +1, -1, or 0 (takes the vote back). Returns `{:ok, item}` with the new score."
  def vote(%Item{} = item, user, value) when value in [-1, 0, 1] do
    if can_vote?(item, user) do
      Repo.transaction(fn ->
        if value == 0 do
          Repo.delete_all(from(v in Vote, where: v.item_id == ^item.id and v.user_id == ^user.id))
        else
          now = DateTime.utc_now()

          Repo.insert_all(
            Vote,
            [
              %{
                item_id: item.id,
                user_id: user.id,
                value: value,
                inserted_at: now,
                updated_at: now
              }
            ],
            on_conflict: [set: [value: value, updated_at: now]],
            conflict_target: [:item_id, :user_id]
          )
        end

        rescore!(item.id)
        %{Repo.get!(Item, item.id) | my_vote: if(value == 0, do: nil, else: value)}
      end)
      |> broadcast(:voted)
    else
      {:error, :forbidden}
    end
  end

  defp rescore!(item_id) do
    score =
      Repo.one(from(v in Vote, where: v.item_id == ^item_id, select: coalesce(sum(v.value), 0))) ||
        0

    Repo.update_all(from(i in Item, where: i.id == ^item_id), set: [score: score])
  end

  # ---------------------------------------------------------------------------
  # Admin: moderating and submitting to Claude
  # ---------------------------------------------------------------------------

  # action => {statuses it may start from, status it leads to}
  @moves %{
    "approve" => {~w(open rejected duplicate), "approved"},
    "reject" => {~w(open approved needs_info failed), "rejected"},
    "duplicate" => {~w(open approved), "duplicate"},
    "reopen" => {~w(approved rejected duplicate), "open"},
    "submit" => {~w(approved needs_info failed), "queued"},
    "withdraw" => {~w(queued), "approved"},
    "deploy" => {~w(ready), "deploying"},
    "mark_live" => {~w(ready deploying failed), "deployed"}
  }

  @doc "Admin actions open to an item in its current status."
  def actions_for(%Item{status: status}),
    do:
      for({action, {from, _}} <- @moves, status in from, do: action)
      |> Enum.sort_by(&action_order/1)

  defp action_order(a),
    do:
      Enum.find_index(
        ~w(submit approve deploy mark_live withdraw reopen duplicate reject),
        &(&1 == a)
      ) || 99

  @doc """
  An admin moves an item: "approve", "reject", "duplicate" (`opts[:of]`: the original's number),
  "reopen", "submit" (to Claude), "withdraw" (from Claude's queue), "deploy" (a held change),
  "mark_live" (deployed some other way). `opts[:note]` goes in the history (and, for a
  rejection, tells the author why).
  """
  def moderate(%Item{} = item, admin, action, opts \\ []) do
    note = opts |> Keyword.get(:note) |> blank_to_nil()

    with true <- admin?(admin) || {:error, :forbidden},
         {:ok, {from, to}} <- Map.fetch(@moves, action) |> ok_or(:unknown_action),
         true <- item.status in from || {:error, {:not_from, item.status}},
         {:ok, extra} <- move_fields(action, item, admin, opts) do
      Repo.transaction(fn ->
        {1, _} =
          Repo.update_all(from(i in Item, where: i.id == ^item.id and i.status == ^item.status),
            set: [status: to, updated_at: DateTime.utc_now()] ++ extra
          )

        updated = Repo.get!(Item, item.id)
        event!(updated, admin, item.status, to, note)
        notify_author(updated, admin, to, note)
        updated
      end)
      |> broadcast(:moved)
    end
  rescue
    # Someone else moved it first (the guarded update matched nothing).
    MatchError -> {:error, :stale}
  end

  defp move_fields("approve", _item, admin, _),
    do: {:ok, approved_by_id: admin.id, approved_at: DateTime.utc_now()}

  defp move_fields("submit", _item, admin, _),
    do: {:ok, submitted_by_id: admin.id, submitted_at: DateTime.utc_now(), hold_reason: nil}

  defp move_fields("reopen", _item, _admin, _), do: {:ok, duplicate_of_id: nil}

  defp move_fields("mark_live", _item, _admin, _),
    do: {:ok, deployed_at: DateTime.utc_now(), hold_reason: nil}

  defp move_fields("duplicate", item, _admin, opts) do
    case get_by_number(to_string(opts[:of] || "")) do
      %Item{id: id} when id != item.id -> {:ok, duplicate_of_id: id}
      _ -> {:error, :no_such_original}
    end
  end

  defp move_fields(_action, _item, _admin, _), do: {:ok, []}

  defp ok_or({:ok, v}, _), do: {:ok, v}
  defp ok_or(:error, reason), do: {:error, reason}

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(s) do
    case s |> to_string() |> String.trim() do
      "" -> nil
      t -> String.slice(t, 0, 10_000)
    end
  end

  # ---------------------------------------------------------------------------
  # Claude's runner (the agent API)
  # ---------------------------------------------------------------------------

  @doc "The runner's settings row (made on first use)."
  def agent do
    Repo.get(Agent, 1) ||
      Repo.insert!(%Agent{id: 1}, on_conflict: :nothing, conflict_target: :id)
      |> then(fn _ -> Repo.get!(Agent, 1) end)
  end

  @doc """
  An admin makes a new token for the runner (any old one stops working). Returns
  `{:ok, token}`; only its SHA-256 is kept, so this is the one time it can be seen.
  """
  def new_agent_token(admin) do
    if admin?(admin) do
      token = "b8fb_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      agent()
      |> Ecto.Changeset.change(
        token_hash: hash(token),
        token_hint: String.slice(token, -4, 4),
        token_created_at: DateTime.utc_now()
      )
      |> Repo.update!()

      Bacon8.Audit.log(admin.id, "feedback.agent_token_created", "feedback_agent", nil, %{})
      {:ok, token}
    else
      {:error, :forbidden}
    end
  end

  @doc "An admin revokes the runner's token."
  def revoke_agent_token(admin) do
    if admin?(admin) do
      agent()
      |> Ecto.Changeset.change(token_hash: nil, token_hint: nil, token_created_at: nil)
      |> Repo.update!()

      Bacon8.Audit.log(admin.id, "feedback.agent_token_revoked", "feedback_agent", nil, %{})
      :ok
    else
      {:error, :forbidden}
    end
  end

  @doc "An admin sets `auto_deploy` and/or `paused`."
  def update_agent(admin, attrs) do
    if admin?(admin) do
      changes =
        for {k, v} <- attrs, k in [:auto_deploy, :paused, "auto_deploy", "paused"], into: %{} do
          {to_atom(k), v in [true, "true", "on"]}
        end

      agent = agent() |> Ecto.Changeset.change(changes) |> Repo.update!()
      Bacon8.Audit.log(admin.id, "feedback.agent_settings", "feedback_agent", nil, changes)
      Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, {:feedback, :agent, nil})
      {:ok, agent}
    else
      {:error, :forbidden}
    end
  end

  defp to_atom(k) when is_atom(k), do: k
  defp to_atom("auto_deploy"), do: :auto_deploy
  defp to_atom("paused"), do: :paused

  @doc "True when `token` is the runner's current token (compared in constant time)."
  def agent_token_valid?(token) when is_binary(token) and byte_size(token) in 20..200 do
    case agent() do
      %Agent{token_hash: h} when is_binary(h) -> Plug.Crypto.secure_compare(h, hash(token))
      _ -> false
    end
  end

  def agent_token_valid?(_), do: false

  defp hash(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  @doc "Records that the runner called (and what it said it was doing)."
  def touch_agent(note \\ nil) do
    note = if is_binary(note), do: String.slice(note, 0, 200), else: nil

    Repo.update_all(from(a in Agent, where: a.id == 1),
      set: [last_seen_at: DateTime.utc_now(), last_seen_note: note]
    )

    :ok
  end

  @doc """
  What the runner should do next:

    * `{:paused, agent}` - an admin paused it;
    * `{:busy, item}` - an item is already in progress, ready (waiting for Deploy) or being
      deployed: the runner deals with that one (or waits) and takes nothing new;
    * `{:ok, item}` - it now has the oldest submitted item, moved to `in_progress`;
    * `:empty` - nothing to do.

  With `peek: true` nothing is claimed: `{:queued, n}` says how many wait (the runner asks this
  way when it can't start, e.g. the working copy has uncommitted changes).
  """
  def agent_next(opts \\ []) do
    agent = agent()

    cond do
      agent.paused ->
        {:paused, agent}

      busy =
          Repo.one(
            from(i in Item, where: i.status in ^@busy, order_by: [asc: i.updated_at], limit: 1)
          ) ->
        {:busy, agent_preload(busy)}

      opts[:peek] ->
        case Repo.aggregate(from(i in Item, where: i.status == "queued"), :count) do
          0 -> :empty
          n -> {:queued, n}
        end

      true ->
        Repo.transaction(fn ->
          case Repo.one(
                 from(i in Item,
                   where: i.status == "queued",
                   order_by: [asc: i.submitted_at],
                   limit: 1,
                   lock: "FOR UPDATE SKIP LOCKED"
                 )
               ) do
            nil ->
              :empty

            item ->
              {1, _} =
                Repo.update_all(from(i in Item, where: i.id == ^item.id),
                  set: [
                    status: "in_progress",
                    claimed_at: DateTime.utc_now(),
                    updated_at: DateTime.utc_now()
                  ]
                )

              item = Repo.get!(Item, item.id)
              event!(item, nil, "queued", "in_progress", "Claude started on it.")
              {:ok, agent_preload(item)}
          end
        end)
        |> case do
          {:ok, {:ok, item}} ->
            broadcast_item({:ok, item}, item, :moved)

          {:ok, :empty} ->
            :empty
        end
    end
  end

  defp agent_preload(item), do: Repo.preload(item, [:author, :shots, :submitted_by])

  @doc "An item the runner may see, or nil."
  def agent_item(id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         %Item{status: s} = item when s in @agent_visible <- Repo.get(Item, id) do
      agent_preload(item)
    else
      _ -> nil
    end
  end

  @doc "A screenshot of an item the runner may see, or nil."
  def agent_shot(id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         %Shot{} = shot <- Repo.get(Shot, id),
         %Item{} <- agent_item(shot.item_id) do
      shot
    else
      _ -> nil
    end
  end

  # What the runner may report, from each status.
  @agent_moves %{
    "in_progress" => ~w(in_progress needs_info ready deployed failed),
    # back to ready: the deploy itself failed; the change waits for another Deploy
    "deploying" => ~w(deploying ready deployed failed),
    "ready" => ~w(ready)
  }

  @doc """
  The runner reports on an item: `status` (where it is now), `summary` (what Claude did, shown on
  the item), `commit` (the commit's hash), `hold_reason` (why a change waits for Deploy) and
  `note` (one line for the history). Returns `{:ok, item}` or `{:error, reason}`.
  """
  def agent_report(id, params) do
    status = params["status"]
    commit = params["commit"] |> blank_to_nil()

    with %Item{} = item <- agent_item(id) || {:error, :not_found},
         true <-
           status in Map.get(@agent_moves, item.status, []) || {:error, {:not_from, item.status}},
         true <-
           (is_nil(commit) or Regex.match?(~r/\A[0-9a-f]{7,40}\z/, commit)) ||
             {:error, :bad_commit} do
      set =
        [status: status, updated_at: DateTime.utc_now()] ++
          maybe(:agent_summary, blank_to_nil(params["summary"])) ++
          maybe(:commit_sha, commit) ++
          if(status == "ready", do: [hold_reason: blank_to_nil(params["hold_reason"])], else: []) ++
          if(status == "deployed",
            do: [deployed_at: DateTime.utc_now(), hold_reason: nil],
            else: []
          )

      Repo.transaction(fn ->
        {1, _} =
          Repo.update_all(from(i in Item, where: i.id == ^item.id and i.status == ^item.status),
            set: set
          )

        updated = Repo.get!(Item, item.id)
        note = blank_to_nil(params["note"]) || default_note(status, updated)

        event!(
          updated,
          nil,
          if(status == item.status, do: nil, else: item.status),
          if(status == item.status, do: nil, else: status),
          note
        )

        if status != item.status, do: notify_author(updated, nil, status, nil)
        updated
      end)
      |> broadcast(:moved)
    end
  rescue
    MatchError -> {:error, :stale}
  end

  defp maybe(_k, nil), do: []
  defp maybe(k, v), do: [{k, v}]

  defp default_note("ready", %{hold_reason: r}) when is_binary(r),
    do: "Fixed and tested; waiting for Deploy: " <> r

  defp default_note("ready", _), do: "Fixed and tested; waiting for Deploy."
  defp default_note("deployed", _), do: "Deployed: it's live."
  defp default_note("needs_info", _), do: "Claude needs more information."
  defp default_note("failed", _), do: "Claude couldn't finish this."
  defp default_note(_, _), do: nil

  @doc "The item as the runner sees it (JSON-ready)."
  def agent_view(%Item{} = item, shot_url) do
    %{
      id: item.id,
      number: item.number,
      kind: item.kind,
      area: item.area,
      area_name: area_name(item.area),
      title: item.title,
      body: item.body,
      admin_note: item.admin_note,
      status: item.status,
      score: item.score,
      author: item.author && (item.author.name || "member"),
      submitted_by: item.submitted_by && (item.submitted_by.name || "admin"),
      submitted_at: item.submitted_at,
      commit: item.commit_sha,
      hold_reason: item.hold_reason,
      summary: item.agent_summary,
      shots:
        for(
          s <- item.shots,
          do: %{
            id: s.id,
            filename: s.filename,
            content_type: s.content_type,
            bytes: s.byte_size,
            url: shot_url.(s)
          }
        )
    }
  end

  # ---------------------------------------------------------------------------
  # Plumbing
  # ---------------------------------------------------------------------------

  defp event!(item, actor, from, to, note) do
    Repo.insert!(%Event{
      item_id: item.id,
      actor_id: actor && actor.id,
      actor_kind: if(actor, do: "user", else: "agent"),
      from_status: from,
      to_status: to,
      note: note
    })
  end

  @notify %{
    "approved" => "Your suggestion was approved",
    "rejected" => "Your suggestion was declined",
    "duplicate" => "Your suggestion was marked as a duplicate",
    "needs_info" => "Claude needs more information about your report",
    "deployed" => "Your suggestion is live"
  }

  defp notify_author(%Item{author_id: author_id} = item, actor, to, note)
       when is_binary(author_id) do
    with title when is_binary(title) <- Map.get(@notify, to),
         true <- is_nil(actor) or actor.id != author_id do
      title =
        if item.kind == "bug",
          do: String.replace(title, ["suggestion", "report"], "bug report"),
          else: title

      Notifications.create_notification(%{
        type: "system",
        user_id: author_id,
        actor_id: actor && actor.id,
        title: title,
        content:
          "##{item.number} #{item.title}" <>
            if(note, do: " - " <> String.slice(note, 0, 300), else: ""),
        source_kind: "feedback_item",
        source_id: item.id,
        metadata: %{"path" => "/feedback/#{item.id}"}
      })
    end

    :ok
  end

  defp notify_author(_, _, _, _), do: :ok

  defp broadcast({:ok, %Item{} = item} = result, what) do
    Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, {:feedback, what, item.id})
    result
  end

  defp broadcast(other, _what), do: other

  defp broadcast_item({:ok, _} = result, %Item{id: id}, what) do
    Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, {:feedback, what, id})
    result
  end

  defp broadcast_item(other, _item, _what), do: other

  @doc "Storage keys of every screenshot (for blob GC)."
  def storage_refs, do: Repo.all(from(s in Shot, distinct: true, select: s.sha256))

  @doc """
  A user was banned or deleted: their items still open for discussion go, with their votes.
  Items an admin already took up (approved and beyond) stay, without an author.
  """
  def remove_user_content(user_id) do
    affected = Repo.all(from(v in Vote, where: v.user_id == ^user_id, select: v.item_id))
    Repo.delete_all(from(v in Vote, where: v.user_id == ^user_id))

    Repo.delete_all(
      from(i in Item,
        where: i.author_id == ^user_id and i.status in ["open", "rejected", "duplicate"]
      )
    )

    for id <- Enum.uniq(affected), do: rescore!(id)
    :ok
  end
end
