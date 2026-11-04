defmodule Bacon8.Moderation do
  @moduledoc """
  Trust & safety (2026-11-03; the plan, in plain words, is the owner's "How Bacon8 handles illegal
  content" document). It was a placeholder until then.

  * **Reports** (`Bacon8.Moderation.Report`): anyone, signed in or not, reports something at
    `/report` (or with a Report button beside it). Three kinds: an ordinary report; a
    **TAKE IT DOWN Act** request for intimate images shared without consent (signed, sworn, with a
    way to reach the person: due within 48 hours); a **DMCA** notice. Each has a category and from
    it a priority (`categories/0`).
  * **Hidden at once**: a report of sexual content involving a minor, of child exploitation or of
    an intimate image shared without consent hides what it names immediately (`quarantine/3`),
    before anyone looks; staff can restore it after review.
  * **The queue**, `/admin/moderation` (`Bacon8Web.AdminLive.Moderation`): open reports by priority
    and due time, what the subject is (without showing a suspected abuse image), and the actions
    (`act/4`): keep the evidence and remove, remove, block the file's hash, note the NCMEC
    CyberTipline report number, ban the account, restore, dismiss. Every one is written to the
    report's history and the audit log.
  * **Blocked hashes** (`Bacon8.Moderation.BlockedHash`): a file removed this way can't be uploaded
    again, to the drive (`Bacon8.Drive.add_file/5`) or anywhere else (`Bacon8.Uploads.upload_file/4`):
    exact SHA-256 matches. Matching known abuse imagery by perceptual hash needs a provider
    (PhotoDNA, Cloudflare's CSAM Scanning Tool); `scan_file/1` is where one plugs in.
  * **Holds** (`Bacon8.Moderation.Hold`): evidence kept a year (the REPORT Act's period) in the blob
    store, out of the drive's garbage collection (`held_shas/0`) and out of reach of the site.

  What gets reported and removed is described by its **subject**: `"drive_file"` (a drive file's
  id), `"upload"` (an `/uploads/...` path), `"user"`, `"url"` (anything else, for staff to find), or
  a plugin's own type through its `moderation_subject/2` and `moderation_remove/2` hooks (the forum's
  `"chat_message"`), so core knows nothing about plugins.
  """

  import Ecto.Query
  require Logger

  alias Bacon8.{Drive, Repo, Storage, Uploads}
  alias Bacon8.Accounts.User
  alias Bacon8.Drive.File, as: DFile
  alias Bacon8.Moderation.{Action, BlockedHash, Hold, Report}

  @categories [
    %{id: "csam", label: "Sexual content involving a minor", priority: 0},
    %{id: "child_exploitation", label: "Grooming, enticement or trafficking of a minor", priority: 0},
    %{id: "ncii", label: "Intimate images shared without consent (real or fake)", priority: 1},
    %{id: "threat", label: "Threats of violence or terrorism", priority: 1},
    %{id: "self_harm", label: "Someone at risk of hurting themselves", priority: 1},
    %{id: "malware", label: "Malware, phishing or a scam", priority: 1},
    %{id: "privacy", label: "Someone's private information (doxxing)", priority: 2},
    %{id: "harassment", label: "Harassment or bullying", priority: 2},
    %{id: "hate", label: "Hate speech", priority: 2},
    %{id: "copyright", label: "Copyright infringement", priority: 2},
    %{id: "illegal_goods", label: "Illegal goods or services", priority: 2},
    %{id: "spam", label: "Spam", priority: 3},
    %{id: "other", label: "Something else", priority: 3}
  ]
  @hide_on_report ~w(csam child_exploitation ncii)
  @hold_days 365
  @takedown_hours 48
  @topic "bacon8:moderation"

  def categories, do: @categories
  def category_ids, do: Enum.map(@categories, & &1.id)
  def category(id), do: Enum.find(@categories, &(&1.id == id))
  def topic, do: @topic
  def takedown_hours, do: @takedown_hours

  @doc "True for the categories a report hides at once (abuse of children, intimate images)."
  def hides_on_report?(category), do: category in @hide_on_report

  # ======================================================================= reports

  @doc """
  Files a report. `attrs` (string or atom keys): `kind`, `category`, `subject_url` or
  `subject_type`+`subject_id`, `details`, and the reporter (`reporter_id`, `reporter_name`,
  `reporter_email`, `reporter_ip`, `signature`, `sworn`). `{:ok, report}` or `{:error, changeset}`.
  """
  def create_report(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    {type, id} = resolve_subject(attrs)
    snapshot = describe(type, id)
    cat = category(attrs["category"]) || %{priority: 3}
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    due =
      cond do
        attrs["kind"] == "ncii_takedown" -> DateTime.add(now, @takedown_hours * 3600)
        cat.priority == 0 -> now
        true -> nil
      end

    attrs =
      Map.merge(attrs, %{
        "subject_type" => type,
        "subject_id" => id,
        "subject_owner_id" => snapshot[:owner_id],
        "subject_snapshot" => stringify(snapshot),
        "priority" => cat.priority,
        "due_at" => due
      })

    with {:ok, report} <- %Report{} |> Report.changeset(attrs, category_ids()) |> Repo.insert() do
      log(report, nil, "reported", "#{report.kind}: #{report.category}")

      if hides_on_report?(report.category) or report.kind == "ncii_takedown" do
        case quarantine(report, nil, "hidden when reported") do
          :ok -> :ok
          other -> Logger.warning("moderation: couldn't hide #{report.subject_type} #{report.subject_id}: #{inspect(other)}")
        end
      end

      broadcast({:report_created, report.id})
      notify_admins(report)
      {:ok, report}
    end
  end

  @doc "Open reports first by priority and due time; `status` filters (nil: all)."
  def list_reports(status \\ "open", limit \\ 200) do
    q = from r in Report, order_by: [asc: r.priority, asc_nulls_last: r.due_at, desc: r.inserted_at], limit: ^limit
    q = if status, do: from(r in q, where: r.status == ^status), else: q
    Repo.all(q)
  end

  @doc "A report with its history, or nil."
  def get_report(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Report |> Repo.get(uuid) |> Repo.preload(:actions)
      :error -> nil
    end
  end

  @doc "How many open reports, and how many of them urgent (priority 0-1) or overdue."
  def counts(now \\ DateTime.utc_now()) do
    open = Repo.all(from r in Report, where: r.status == "open", select: {r.priority, r.due_at})

    %{
      open: length(open),
      urgent: Enum.count(open, fn {p, _} -> p <= 1 end),
      overdue: Enum.count(open, fn {_, due} -> due && DateTime.compare(due, now) == :lt end)
    }
  end

  # ======================================================================= actions

  @actions ~w(preserve_remove remove block_hash restore ncmec_reported ban_owner dismiss resolve note)
  def actions, do: @actions

  @doc """
  Does something about a report as `actor` (an admin). `params`: `"note"`, and
  `"ncmec_report_id"` for `ncmec_reported`.

    * `preserve_remove` - keep the evidence for a year (`Hold`), hide the subject, block its files'
      hashes. For suspected abuse of children, do this before anything else (banning deletes the
      account's posts at once).
    * `remove` - delete the subject (a drive file, an upload, a plugin's message) and block its hashes
    * `block_hash` - only block its files' hashes
    * `restore` - un-hide what a report hid
    * `ncmec_reported` - record the CyberTipline report number
    * `ban_owner` - ban the account that posted it (`Bacon8.Accounts.change_role/3`)
    * `dismiss`, `resolve` - close the report; `note` - add to its history

  `{:ok, report}` or `{:error, message}`.
  """
  def act(%Report{} = report, action, %User{} = actor, params \\ %{}) when action in @actions do
    note = params["note"] |> to_string() |> String.trim() |> String.slice(0, 2_000)

    result =
      case action do
        "preserve_remove" ->
          with {:ok, n} <- preserve(report, actor),
               r when r in [:ok, :unknown] <- quarantine(report, actor, "kept as evidence and hidden"),
               {:ok, b} <- block_hashes(report, actor) do
            {:ok, "kept #{n} item(s) as evidence for #{@hold_days} days, hid it, blocked #{b} file hash(es)"}
          end

        "remove" ->
          with {:ok, b} <- block_hashes(report, actor),
               :ok <- remove_subject(report) do
            {:ok, "removed it and blocked #{b} file hash(es)"}
          end

        "block_hash" ->
          with {:ok, b} <- block_hashes(report, actor), do: {:ok, "blocked #{b} file hash(es)"}

        "restore" ->
          with :ok <- unquarantine(report), do: {:ok, "restored"}

        "ncmec_reported" ->
          case String.trim(to_string(params["ncmec_report_id"])) do
            "" -> {:error, "Enter the CyberTipline report number."}
            n -> save_status(report, %{ncmec_report_id: String.slice(n, 0, 60)}) && {:ok, "CyberTipline report #{n}"}
          end

        "ban_owner" ->
          ban_owner(report, actor)

        "dismiss" ->
          close(report, actor, "dismissed", note)
          {:ok, "dismissed"}

        "resolve" ->
          close(report, actor, "actioned", note)
          {:ok, "resolved"}

        "note" ->
          if note == "", do: {:error, "Write the note first."}, else: {:ok, "note"}
      end

    case result do
      {:ok, summary} ->
        log(report, actor, action, Enum.join(Enum.reject([summary, note], &(&1 in ["", "note"])), " · "))
        Bacon8.Audit.log(actor.id, "moderation.#{action}", "moderation_report", report.id, %{summary: summary})
        broadcast({:report_updated, report.id})
        {:ok, get_report(report.id)}

      {:error, msg} when is_binary(msg) ->
        {:error, msg}

      other ->
        {:error, "That didn't work: #{inspect(other)}"}
    end
  end

  defp save_status(report, attrs), do: report |> Report.status_changeset(attrs) |> Repo.update()

  defp close(report, actor, status, note) do
    save_status(report, %{status: status, resolution: note, resolved_by: actor.id, resolved_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  defp ban_owner(%Report{subject_owner_id: nil}, _actor), do: {:error, "This report names no account."}

  defp ban_owner(report, actor) do
    case Repo.get(User, report.subject_owner_id) do
      nil ->
        {:error, "That account is gone."}

      %User{} = user ->
        held = Repo.exists?(from h in Hold, where: h.report_id == ^report.id)

        if report.category in ~w(csam child_exploitation) and not held do
          {:error, "Keep the evidence first (Keep evidence & remove): banning deletes the account's posts at once."}
        else
          case Bacon8.Accounts.change_role(user, "banned", actor: actor) do
            {:ok, _} -> {:ok, "banned #{user.name || user.email}"}
            {:error, reason} -> {:error, "Couldn't ban: #{inspect(reason)}"}
          end
        end
    end
  end

  defp log(report, actor, action, note) do
    %Action{report_id: report.id, actor_id: actor && actor.id, action: action, note: note}
    |> Repo.insert()
  end

  # ======================================================================= subjects

  @doc """
  What a report names, from a link: a drive share (`/s/<token>`) or file (`/files/<id>`), an
  upload (`/uploads/...`), or the link itself. A type and id given (an in-site Report button) win.
  """
  def resolve_subject(%{"subject_type" => t, "subject_id" => id}) when is_binary(t) and t != "" and is_binary(id) and id != "", do: {t, id}

  def resolve_subject(%{"subject_url" => url}) when is_binary(url) and url != "" do
    path = URI.parse(String.trim(url)).path || ""

    cond do
      match = Regex.run(~r"^/s/([A-Za-z0-9_\-]{16,64})$", path) ->
        case Drive.get_file_by_share_token(Enum.at(match, 1)) do
          %DFile{id: id} -> {"drive_file", id}
          nil -> {"url", url}
        end

      match = Regex.run(~r"^/files/([0-9a-f\-]{36})$", path) ->
        {"drive_file", Enum.at(match, 1)}

      String.starts_with?(path, "/uploads/") ->
        {"upload", path}

      true ->
        {"url", url}
    end
  end

  def resolve_subject(_), do: {"url", nil}

  @doc "What is known about a subject now (kept on the report, so it outlives a deletion)."
  def describe(type, id)

  def describe("drive_file", id) do
    case Drive.get_file(id) do
      %DFile{} = f -> %{title: f.name, owner_id: f.owner_id, size: f.size, content_type: f.content_type, sha256: f.blob_sha256, visibility: f.visibility, uploaded_at: f.inserted_at}
      nil -> %{title: "(drive file #{id}: gone)"}
    end
  end

  def describe("upload", path) do
    with fs when is_binary(fs) <- Uploads.url_to_path(path),
         true <- Elixir.File.regular?(fs) do
      %{title: Path.basename(path), path: path, owner_id: upload_owner(path), size: Elixir.File.stat!(fs).size, sha256: Storage.sha256_file(fs)}
    else
      _ -> %{title: path, path: path, owner_id: upload_owner(path)}
    end
  end

  def describe("user", id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> (u = Repo.get(User, uuid)) && %{title: u.name || u.email, owner_id: u.id} || %{title: "(account #{id}: gone)"}
      :error -> %{title: "(no such account)"}
    end
  end

  def describe("url", url), do: %{title: url || "(no link)"}

  def describe(type, id) do
    case Bacon8.Plugins.moderation_subject(type, id) do
      {:ok, %{} = s} -> s
      _ -> %{title: "#{type} #{id}"}
    end
  end

  # /uploads/users/<id>/... and /uploads/<id>/... name their uploader
  defp upload_owner(path) do
    case Regex.run(~r"^/uploads/(?:users/)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/", path) do
      [_, id] -> id
      _ -> nil
    end
  end

  # the file hashes a report's subject has (drive blob, upload, a plugin's attachments)
  defp subject_files(%Report{subject_type: "drive_file"} = r), do: List.wrap(r.subject_snapshot["sha256"])
  defp subject_files(%Report{subject_type: "upload", subject_id: path}), do: Enum.reject([sha_of_upload(path)], &is_nil/1)

  defp subject_files(%Report{} = r) do
    paths = r.subject_snapshot["files"] || []
    Enum.flat_map(paths, &List.wrap(sha_of_upload(&1)))
  end

  defp sha_of_upload(path) do
    with fs when is_binary(fs) <- Uploads.url_to_path(path), true <- Elixir.File.regular?(fs), do: Storage.sha256_file(fs), else: (_ -> nil)
  end

  @doc """
  Hides a report's subject from everyone (a drive file can't be opened, not even by its owner or
  staff; an upload moves into the evidence store; a plugin's subject is removed by the plugin
  after its files are kept). `:ok`, `:unknown` (nothing the hub can hide, like a bare link) or
  `{:error, reason}`.
  """
  def quarantine(%Report{subject_type: "drive_file", subject_id: id} = r, _actor, _why) do
    case Drive.quarantine(id, true) do
      :ok -> Repo.update_all(from(x in Report, where: x.id == ^r.id), set: [subject_snapshot: Map.put(r.subject_snapshot || %{}, "hidden", true)]) && :ok
      other -> other
    end
  end

  def quarantine(%Report{subject_type: "upload", subject_id: path}, _actor, _why) do
    with fs when is_binary(fs) <- Uploads.url_to_path(path),
         true <- Elixir.File.regular?(fs) do
      sha = Storage.sha256_file(fs)
      {:ok, _} = Storage.put_new(sha, fs)
      Uploads.delete_file(path)
      :ok
    else
      _ -> :unknown
    end
  end

  def quarantine(%Report{subject_type: t} = r, actor, _why) when t not in ["user", "url", nil] do
    # a plugin's subject can't be hidden in place: keep it, then remove it
    {:ok, _} = preserve(r, actor)
    remove_subject(r)
  end

  def quarantine(_report, _actor, _why), do: :unknown

  @doc "Undoes `quarantine/3` where it can (a drive file, an upload kept in the store)."
  def unquarantine(%Report{subject_type: "drive_file", subject_id: id}), do: Drive.quarantine(id, false)

  def unquarantine(%Report{subject_type: "upload", subject_id: path} = r) do
    with fs when is_binary(fs) <- Uploads.url_to_path(path),
         false <- Elixir.File.exists?(fs),
         sha when is_binary(sha) <- r.subject_snapshot["sha256"],
         {:ok, src} <- Storage.local_path(sha) do
      Elixir.File.mkdir_p!(Path.dirname(fs))
      Elixir.File.cp!(src, fs)
      :ok
    else
      true -> :ok
      _ -> {:error, "The file can't be put back."}
    end
  end

  def unquarantine(_), do: {:error, "This can't be put back from here (it was removed)."}

  defp remove_subject(%Report{subject_type: "drive_file", subject_id: id}), do: Drive.remove_by_staff(id)

  # (an upload already moved into the evidence store is gone from its folder: nothing to do)
  defp remove_subject(%Report{subject_type: "upload", subject_id: path}) do
    _ = Uploads.delete_file(path)
    :ok
  end

  defp remove_subject(%Report{subject_type: t}) when t in ["user", "url", nil], do: {:error, "Remove it where it is (this report names #{t || "nothing"} the hub can delete)."}

  defp remove_subject(%Report{subject_type: t, subject_id: id}) do
    case Bacon8.Plugins.moderation_remove(t, id) do
      :ok -> :ok
      :unknown -> {:error, "No plugin knows how to remove a #{t}."}
      {:error, reason} -> {:error, "Couldn't remove it: #{inspect(reason)}"}
    end
  end

  # ======================================================================= evidence

  @doc """
  Keeps a report's evidence for a year: each file's body in the blob store (an upload or a plugin's
  attachment is copied there first) and what is known (the snapshot, the account, when).
  `{:ok, count}`.
  """
  def preserve(%Report{} = r, actor) do
    until = DateTime.utc_now() |> DateTime.add(@hold_days * 86_400) |> DateTime.truncate(:second)
    owner = r.subject_owner_id && Repo.get(User, r.subject_owner_id)

    evidence = %{
      "snapshot" => r.subject_snapshot,
      "report" => %{"kind" => r.kind, "category" => r.category, "details" => r.details, "url" => r.subject_url, "filed_at" => r.inserted_at && DateTime.to_iso8601(r.inserted_at)},
      "account" => owner && %{"id" => owner.id, "name" => owner.name, "email" => owner.email, "created_at" => owner.inserted_at && to_string(owner.inserted_at)},
      "kept_by" => actor && actor.id,
      "kept_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    shas =
      case r.subject_type do
        "drive_file" -> List.wrap(r.subject_snapshot["sha256"])
        _ -> copy_files_to_store(r)
      end

    rows =
      case shas do
        [] -> [nil]
        list -> list
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      for sha <- rows do
        %{id: Ecto.UUID.generate(), report_id: r.id, sha256: sha, subject_type: r.subject_type, subject_id: r.subject_id, owner_id: r.subject_owner_id,
          evidence: evidence, preserve_until: until, inserted_at: now, updated_at: now}
      end

    {n, _} = Repo.insert_all(Hold, entries)
    {:ok, n}
  end

  # uploads and plugin attachments: their bodies into the content-addressed store
  defp copy_files_to_store(%Report{subject_type: "upload", subject_id: path}), do: path |> copy_one() |> List.wrap()
  defp copy_files_to_store(%Report{} = r), do: (r.subject_snapshot["files"] || []) |> Enum.map(&copy_one/1) |> Enum.reject(&is_nil/1)

  defp copy_one(path) do
    with fs when is_binary(fs) <- Uploads.url_to_path(path),
         true <- Elixir.File.regular?(fs) do
      sha = Storage.sha256_file(fs)
      {:ok, _} = Storage.put_new(sha, fs)
      sha
    else
      _ -> nil
    end
  end

  @doc "File bodies under an unreleased hold (`Bacon8.Drive.gc_blobs/2` keeps them)."
  def held_shas do
    Repo.all(from h in Hold, where: is_nil(h.released_at) and not is_nil(h.sha256), select: h.sha256, distinct: true)
  rescue
    # no table yet (an install mid-migration): keep nothing extra, delete nothing extra
    _ -> []
  end

  @doc "Holds, newest first."
  def list_holds(limit \\ 200), do: Repo.all(from h in Hold, order_by: [desc: h.inserted_at], limit: ^limit)

  @doc "Ends a hold (its year is up, or law enforcement has what it needs). The body goes at the next GC unless something else uses it."
  def release_hold(id, %User{} = actor) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Hold{released_at: nil} = h <- Repo.get(Hold, uuid) do
      {:ok, _} = h |> Ecto.Changeset.change(released_at: DateTime.utc_now() |> DateTime.truncate(:second)) |> Repo.update()
      Bacon8.Audit.log(actor.id, "moderation.release_hold", "moderation_hold", h.id, %{report_id: h.report_id})
      :ok
    else
      _ -> {:error, "No such hold, or it was released already."}
    end
  end

  # ======================================================================= blocked hashes

  @doc "True when nobody may upload this file (by SHA-256)."
  def blocked_hash?(sha) when is_binary(sha) do
    Repo.exists?(from b in BlockedHash, where: b.sha256 == ^sha)
  rescue
    _ -> false
  end

  def blocked_hash?(_), do: false

  @doc "True when the file at `path` may not be uploaded."
  def blocked_file?(path) when is_binary(path) do
    Elixir.File.regular?(path) and blocked_hash?(Storage.sha256_file(path))
  end

  defp block_hashes(%Report{} = r, actor) do
    shas = r |> subject_files() |> Enum.concat(held_of(r)) |> Enum.uniq() |> Enum.filter(&Storage.valid_sha?/1)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    reason = "#{r.category} (report #{String.slice(r.id, 0, 8)})"
    rows = for s <- shas, do: %{sha256: s, reason: reason, report_id: r.id, added_by: actor && actor.id, inserted_at: now}
    {n, _} = Repo.insert_all(BlockedHash, rows, on_conflict: :nothing, conflict_target: :sha256)
    {:ok, max(n, length(shas))}
  end

  defp held_of(r), do: Repo.all(from h in Hold, where: h.report_id == ^r.id and not is_nil(h.sha256), select: h.sha256)

  @doc "Blocks a hash by hand (a known-bad file from elsewhere)."
  def block_hash(sha, reason, %User{} = actor) do
    sha = sha |> to_string() |> String.trim() |> String.downcase()

    if Storage.valid_sha?(sha) do
      Repo.insert_all(BlockedHash, [%{sha256: sha, reason: String.slice(reason || "", 0, 200), added_by: actor.id, inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)}], on_conflict: :nothing, conflict_target: :sha256)
      Bacon8.Audit.log(actor.id, "moderation.block_hash", "sha256", nil, %{sha256: sha})
      :ok
    else
      {:error, "A SHA-256 is 64 hex digits."}
    end
  end

  def list_blocked(limit \\ 500), do: Repo.all(from b in BlockedHash, order_by: [desc: b.inserted_at], limit: ^limit)

  def unblock_hash(sha, %User{} = actor) do
    Repo.delete_all(from b in BlockedHash, where: b.sha256 == ^sha)
    Bacon8.Audit.log(actor.id, "moderation.unblock_hash", "sha256", nil, %{sha256: sha})
    :ok
  end

  # ======================================================================= scanning

  @doc """
  The hook for scanning a new upload (best effort, after it is stored): blocked hashes now; a
  perceptual-hash provider (PhotoDNA Cloud Service, Thorn's Safer) would go here. Returns
  `{:ok, :clean}` or `{:ok, :flagged}` (a blocked file that got through is reported and hidden).
  """
  def scan_file(file_path) when is_binary(file_path) do
    if blocked_file?(file_path) do
      Logger.warning("moderation: a blocked file was found at #{file_path}")
      {:ok, :flagged}
    else
      {:ok, :clean}
    end
  rescue
    _ -> {:ok, :clean}
  end

  # ======================================================================= telling people

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(Bacon8.PubSub, @topic, msg)

  # every admin gets a notification (and so a push to their phone, Bacon8.Push)
  defp notify_admins(%Report{} = r) do
    cat = category(r.category)
    urgent = r.priority <= 1
    title = if(urgent, do: "Urgent report: ", else: "Report: ") <> ((cat && cat.label) || r.category)

    for admin <- Repo.all(from u in User, where: u.is_admin == true) do
      Bacon8.Notifications.create_notification(%{
        user_id: admin.id,
        type: "system",
        title: title,
        content: if(r.kind == "ncii_takedown", do: "Takedown request: due within #{@takedown_hours} hours.", else: "A new report is waiting."),
        source_kind: "moderation_report",
        source_id: r.id,
        metadata: %{"path" => "/admin/moderation?id=#{r.id}", "urgent" => urgent}
      })
    end

    :ok
  rescue
    e -> Logger.warning("moderation: couldn't notify admins: #{inspect(e)}")
  end

  defp stringify(%DateTime{} = d), do: DateTime.to_iso8601(d)
  defp stringify(%NaiveDateTime{} = d), do: NaiveDateTime.to_iso8601(d)
  defp stringify(m) when is_map(m), do: for({k, v} <- m, into: %{}, do: {to_string(k), stringify(v)})
  defp stringify(l) when is_list(l), do: Enum.map(l, &stringify/1)
  defp stringify(v), do: v
end
