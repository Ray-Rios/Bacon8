defmodule Bacon8.Drive.RulesTest do
  @moduledoc "Pure rules: tiers, prices, quota policy, names, sniffing. No database."
  use ExUnit.Case, async: true

  alias Bacon8.Drive.{Names, Plans, Policy, Sniff}

  @gib 1_073_741_824

  describe "Plans (decided 2026-10-15)" do
    test "tiers and monthly prices at $0.50/GB" do
      assert [
               %{key: "small", gb: 10, monthly_cents: 500},
               %{key: "medium", gb: 25, monthly_cents: 1250},
               %{key: "large", gb: 50, monthly_cents: 2500},
               %{key: "xl", gb: 100, monthly_cents: 5000},
               %{key: "custom", min_gb: 1, max_gb: 1000}
             ] = Plans.tiers()

      assert Plans.free_tier() == %{key: "free", label: "Free", gb: 1, monthly_cents: 0}
    end

    test "custom sizes up to 1 TB" do
      assert {:ok, %{gb: 1000, monthly_cents: 50_000}} = Plans.resolve("custom", 1000)
      assert {:ok, %{gb: 7, monthly_cents: 350}} = Plans.resolve("custom", 7)
      assert {:error, :custom_size_out_of_range} = Plans.resolve("custom", 1001)
      assert {:error, :custom_size_out_of_range} = Plans.resolve("custom", 0)
      assert {:error, :custom_size_required} = Plans.resolve("custom", nil)
    end

    test "fixed tiers ignore a supplied size; unknown tiers are refused" do
      assert {:ok, %{key: "medium", gb: 25}} = Plans.resolve("medium", 999)
      assert {:error, :unknown_tier} = Plans.resolve("free", nil)
      assert {:error, :unknown_tier} = Plans.resolve("huge", nil)
    end

    test "formats cents" do
      assert Plans.format_cents(1250) == "$12.50"
      assert Plans.format_cents(5) == "$0.05"
      assert Plans.format_cents(50_000) == "$500.00"
    end
  end

  describe "Policy.quota_bytes/2" do
    test "guest and banned get nothing, even with a tier" do
      for role <- ~w(guest banned) do
        assert Policy.quota_bytes(%{role: role}, [%{quantity: 100}]) == 0
      end
    end

    test "admins are unlimited" do
      assert Policy.quota_bytes(%{role: "admin"}, []) == :unlimited
    end

    test "every other role gets 1 GB free, including staff" do
      for role <- ~w(gm editor moderator member) do
        assert Policy.quota_bytes(%{role: role}, []) == @gib
      end
    end

    test "a paid tier replaces the free tier; the largest active tier wins" do
      assert Policy.quota_bytes(%{role: "member"}, [%{quantity: 10}]) == 10 * @gib
      assert Policy.quota_bytes(%{role: "member"}, [%{quantity: 10}, %{quantity: 50}]) == 50 * @gib
    end

    test "purchase eligibility" do
      assert Policy.can_purchase_storage?(%{role: "member", status: "active"})
      refute Policy.can_purchase_storage?(%{role: "guest", status: "active"})
      refute Policy.can_purchase_storage?(%{role: "banned", status: "active"})
      refute Policy.can_purchase_storage?(%{role: "member", status: "disabled"})
    end

    test "largest single upload by role" do
      mib = 1_048_576
      assert Policy.max_upload_bytes(%{role: "member"}) == 25 * mib
      assert Policy.max_upload_bytes(%{role: "moderator"}) == 50 * mib
      assert Policy.max_upload_bytes(%{role: "editor"}) == @gib
      assert Policy.max_upload_bytes(%{role: "gm"}) == @gib
      assert Policy.max_upload_bytes(%{role: "admin"}) == :unlimited
      assert Policy.max_upload_bytes(%{role: "guest"}) == 0
      assert Policy.max_upload_bytes(%{role: "banned"}) == 0
      assert Policy.max_upload_bytes(nil) == 0
      assert Policy.upload_limit_for_live_view(%{role: "admin"}) == 1024 * @gib
      assert Policy.upload_limit_for_live_view(%{role: "guest"}) == 1
    end

    test "fits?/3" do
      assert Policy.fits?(:unlimited, 10 * @gib, @gib)
      assert Policy.fits?(@gib, @gib - 10, 10)
      refute Policy.fits?(@gib, @gib - 10, 11)
      refute Policy.fits?(0, 0, 1)
    end
  end

  describe "Names" do
    test "rejects path-like and control-character names" do
      for bad <- ["", ".", "..", "a/b", "a\\b", "x\u0000y", "tab\there"] do
        assert Names.problem(bad), "expected #{inspect(bad)} to be rejected"
      end

      assert Names.problem("Holiday photos (2026).zip") == nil
    end

    test "dedupe/2 appends a counter before the extension, case-insensitively" do
      assert Names.dedupe("a.png", []) == "a.png"
      assert Names.dedupe("a.png", ["A.PNG"]) == "a (1).png"
      assert Names.dedupe("a.png", ["a.png", "a (1).png"]) == "a (2).png"
      assert Names.dedupe("notes", ["notes"]) == "notes (1)"
    end
  end

  describe "Sniff" do
    test "recognises common formats by magic bytes" do
      assert Sniff.sniff(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0, 0>>) == "image/png"
      assert Sniff.sniff(<<0xFF, 0xD8, 0xFF, 0xE0>>) == "image/jpeg"
      assert Sniff.sniff("%PDF-1.7") == "application/pdf"
      assert Sniff.sniff(<<"RIFF", 0, 0, 0, 0, "WEBP">>) == "image/webp"
      assert Sniff.sniff(<<0, 0, 0, 0x18, "ftypmp42">>) == "video/mp4"
      assert Sniff.sniff("<html><script>") == nil
    end

    test "an unrecognised body never gets an inline type from its extension" do
      # HTML renamed to .png: stored as octet-stream, so never rendered inline.
      assert Sniff.content_type(nil, "evil.png") == "application/octet-stream"
      refute Sniff.inline?(Sniff.content_type(nil, "evil.png"))
      # Non-inline types keep their name-derived type for downloads.
      assert Sniff.content_type(nil, "notes.txt") == "text/plain"
      assert Sniff.content_type("image/png", "whatever.bin") == "image/png"
    end
  end
end
