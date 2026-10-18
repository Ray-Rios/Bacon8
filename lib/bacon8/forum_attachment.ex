defmodule Bacon8.ForumAttachment do
  use Arc.Definition
  use Arc.Ecto.Definition

  @versions [:original, :thumb]
  @extension_whitelist ~w(.jpg .jpeg .gif .png .webp .pdf .doc .docx .txt .mp3 .mp4 .avi .mov)

  def validate({file, _}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    Enum.member?(@extension_whitelist, file_extension)
  end

  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 200x200^ -gravity center -extent 200x200 -format png", :png}
  end

  def filename(version, {file, scope}) do
    name = Path.basename(file.file_name, Path.extname(file.file_name))
    "#{scope.id}_#{name}_#{version}#{Path.extname(file.file_name)}"
  end

  def storage_dir(_version, {_file, scope}) do
    # Prefer explicit channel_id if available; fall back to message_id or scope id.
    channel_part = Map.get(scope, :channel_id) || Map.get(scope, :message_id) || Map.get(scope, :id)
    message_part = Map.get(scope, :message_id) || Map.get(scope, :id)

    "uploads/forum/#{channel_part}/#{message_part}"
  end
end