defmodule Bacon8.PostImage do
  use Arc.Definition
  use Arc.Ecto.Definition

  @versions [:original, :thumb, :large]
  @extension_whitelist ~w(.jpg .jpeg .gif .png .webp)

  def validate({file, _}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    Enum.member?(@extension_whitelist, file_extension)
  end

  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 300x200^ -gravity center -extent 300x200 -format png", :png}
  end

  def transform(:large, _) do
    {:convert, "-strip -resize 800x600> -format png", :png}
  end

  def filename(version, {_file, scope}) do
    "#{scope.id}_#{version}"
  end

  def storage_dir(_version, {_file, scope}) do
    "uploads/posts/#{scope.id}"
  end

  def default_url(:thumb) do
    "/images/default-avatar.png"
  end

  def default_url(_version) do
    "/images/default-avatar.png"
  end
end