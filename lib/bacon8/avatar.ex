defmodule Bacon8.Avatar do
  use Arc.Definition
  use Arc.Ecto.Definition

  @versions [:original, :thumb]
  @extension_whitelist ~w(.jpg .jpeg .gif .png)

  def validate({file, _}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    Enum.member?(@extension_whitelist, file_extension)
  end

  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 100x100^ -gravity center -extent 100x100 -format png", :png}
  end

  # Handle nil scope gracefully - return a default filename
  def filename(_version, {_file, nil}) do
    "default_avatar"
  end

  def filename(version, {_file, scope}) when is_map(scope) and not is_nil(scope.id) do
    "#{scope.id}_#{version}"
  end

  # Fallback for any other unexpected input
  def filename(_version, _) do
    "default_avatar"
  end

  def storage_dir(_version, {_file, scope}) do
    "uploads/avatars/#{scope.id}"
  end

  def default_url(:thumb) do
    "/uploads/public/images/default_avatar.jpg"
  end

  def default_url(_version) do
    "/uploads/public/images/default_avatar.jpg"
  end
end