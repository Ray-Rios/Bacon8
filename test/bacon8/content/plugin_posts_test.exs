defmodule Bacon8.Content.PluginPostsTest do
  # Posts written by plugins and games (patch notes): drafts by default, text always escaped.
  use Bacon8.DataCase, async: true

  alias Bacon8.Content

  defp admin, do: user_fixture(%{role: "admin", is_admin: true})

  defp blocks(post) do
    %{"rows" => [%{"columns" => [%{"blocks" => blocks}]}]} = Jason.decode!(post.content)
    blocks
  end

  test "makes a draft by default, tagged with the plugin, authored by an admin" do
    author = admin()

    assert {:ok, post} =
             Content.post_from_plugin("rays_space_sim", %{title: "Patch 0.4", body: [{:paragraph, "Hello"}]}, author: author)

    refute post.is_published
    assert post.user_id == author.id
    assert "rays_space_sim" in post.tags
    assert post.slug == "patch-04"
  end

  test "publishes only when asked, and sets the publish date" do
    {:ok, post} = Content.post_from_plugin("p", %{title: "Out now", body: [{:paragraph, "x"}]}, author: admin(), publish: true)
    assert post.is_published
    assert post.published_at
    assert Content.get_post_by_slug("out-now").id == post.id
  end

  test "without an author uses the oldest admin, and fails when there is none" do
    assert {:error, :no_author} = Content.post_from_plugin("p", %{title: "T", body: [{:paragraph, "x"}]})

    first = admin()
    _later = admin()
    assert {:ok, post} = Content.post_from_plugin("p", %{title: "T", body: [{:paragraph, "x"}]})
    assert post.user_id == first.id
  end

  test "escapes every piece of text, so untrusted strings can't inject markup" do
    evil = ~s|<script>alert(1)</script> & "quotes"|

    {:ok, post} =
      Content.post_from_plugin("p", %{title: "T", body: [{:heading, evil}, {:paragraph, evil}, {:list, [evil]}]}, author: admin())

    html = post |> blocks() |> Enum.map_join(& &1["content"])
    refute html =~ "<script"
    assert html =~ "&lt;script&gt;"
    assert html =~ "&amp;"
  end

  test "builds ordinary editor blocks" do
    {:ok, post} =
      Content.post_from_plugin("p", %{title: "T", body: [{:heading, "Fixes"}, {:list, ["a", "b"]}, {:paragraph, "Thanks"}]}, author: admin())

    assert [%{"type" => "text", "content" => "<h2>Fixes</h2>"}, %{"content" => "<ul><li>a</li><li>b</li></ul>"}, %{"content" => "<p>Thanks</p>"}] =
             blocks(post)
  end

  test "a title that is taken gets a numbered slug" do
    a = admin()
    {:ok, one} = Content.post_from_plugin("p", %{title: "Same", body: [{:paragraph, "x"}]}, author: a)
    {:ok, two} = Content.post_from_plugin("p", %{title: "Same", body: [{:paragraph, "y"}]}, author: a)
    assert {one.slug, two.slug} == {"same", "same-2"}
  end

  test "refuses a missing title or an empty body" do
    a = admin()
    assert {:error, :title_required} = Content.post_from_plugin("p", %{title: "  ", body: [{:paragraph, "x"}]}, author: a)
    assert {:error, :empty_body} = Content.post_from_plugin("p", %{title: "T", body: []}, author: a)
    assert {:error, :empty_body} = Content.post_from_plugin("p", %{title: "T", body: [{:nonsense, "x"}]}, author: a)
    assert {:error, :empty_body} = Content.post_from_plugin("p", %{title: "T"}, author: a)
  end
end
