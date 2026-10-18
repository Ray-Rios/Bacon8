defmodule Bacon8.MediaProcessor do
  @moduledoc "Background helpers for processing uploaded media (thumbnails, transcode)." 
  require Logger

  @doc "Attempt to generate a thumbnail for an image (best-effort). Returns :ok or {:error, reason}."
  def generate_thumbnail(file_path, out_path) do
    if System.find_executable("convert") do
      cmd = ["-strip", "-thumbnail", "200x200^", "-gravity", "center", "-extent", "200x200", "-format", "png", file_path, out_path]
      case System.cmd("convert", cmd, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {out, _} -> Logger.error("Thumbnail creation failed: #{out}"); {:error, out}
      end
    else
      Logger.warning("ImageMagick 'convert' not available; skipping thumbnail for #{file_path}")
      :ok
    end
  end

  @doc "Attempt to transcode a video file to H.264 MP4 (best-effort). Returns :ok or {:error, reason}."
  def transcode_video(input_path, output_path) do
    if System.find_executable("ffmpeg") do
      cmd = ["-i", input_path, "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", output_path]
      case System.cmd("ffmpeg", cmd, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {out, _} -> Logger.error("Transcode failed: #{out}"); {:error, out}
      end
    else
      Logger.warning("ffmpeg not available; skipping transcode for #{input_path}")
      :ok
    end
  end
end
