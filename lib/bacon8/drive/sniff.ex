defmodule Bacon8.Drive.Sniff do
  @moduledoc """
  Content-type detection from magic bytes. The client's declared type and the
  file extension are never trusted for anything that affects how the browser
  renders a file: only a type recognised here may be served inline.
  """

  @signatures [
    {<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>, "image/png"},
    {<<0xFF, 0xD8, 0xFF>>, "image/jpeg"},
    {"GIF87a", "image/gif"},
    {"GIF89a", "image/gif"},
    {"%PDF-", "application/pdf"},
    {"ID3", "audio/mpeg"},
    {<<0xFF, 0xFB>>, "audio/mpeg"},
    {<<0xFF, 0xF3>>, "audio/mpeg"},
    {<<0xFF, 0xF2>>, "audio/mpeg"},
    {"OggS", "audio/ogg"},
    {"fLaC", "audio/flac"},
    {<<0x1A, 0x45, 0xDF, 0xA3>>, "video/webm"},
    {<<"PK", 3, 4>>, "application/zip"}
  ]

  # Types that may be rendered inline by the browser (images, audio, video,
  # PDF). Everything else is served as an attachment.
  @inline ~w(image/png image/jpeg image/gif image/webp audio/mpeg audio/ogg audio/wav audio/flac
             video/mp4 video/webm application/pdf)

  @doc "Reads the first bytes of `path` and returns a MIME type or nil."
  def sniff_file(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 16)) do
      {:ok, head} when is_binary(head) -> sniff(head)
      _ -> nil
    end
  end

  @doc "Returns a MIME type for the leading bytes, or nil."
  def sniff(<<"RIFF", _size::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  def sniff(<<"RIFF", _size::binary-size(4), "WAVE", _::binary>>), do: "audio/wav"
  def sniff(<<_size::binary-size(4), "ftyp", _::binary>>), do: "video/mp4"

  def sniff(head) when is_binary(head) do
    Enum.find_value(@signatures, fn {magic, type} ->
      if String.starts_with?(head, magic), do: type
    end)
  end

  def sniff(_), do: nil

  @doc """
  The type to store: the sniffed type when recognised; otherwise the type
  implied by the name, *unless* that type would be rendered inline (a ".png"
  whose bytes are not a PNG is stored as application/octet-stream). So
  `inline?(stored_type)` can only be true for content we actually recognised.
  """
  def content_type(sniffed, _name) when is_binary(sniffed), do: sniffed

  def content_type(nil, name) do
    by_name = MIME.from_path(name || "")
    if by_name && not inline?(by_name), do: by_name, else: "application/octet-stream"
  end

  @doc "May a file whose *sniffed* type is `type` be shown inline?"
  def inline?(type), do: type in @inline
end
