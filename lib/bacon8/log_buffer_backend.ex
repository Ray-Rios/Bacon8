defmodule Bacon8.LogBufferBackend do
  @moduledoc """
  A custom Logger backend that sends log entries to the LogBuffer.
  """
  @behaviour :gen_event

  @impl true
  def init(_opts) do
    {:ok, %{level: :debug}}
  end

  @impl true
  def handle_call({:configure, opts}, state) do
    level = opts |> Keyword.get(:level, state.level) |> normalize()
    {:ok, :ok, %{state | level: level}}
  end

  @impl true
  def handle_event({level, _gl, {Logger, message, timestamp, metadata}}, state) do
    # Legacy :gen_event backends are still handed `:warn` for warnings, and
    # passing it to Logger.compare_levels/2 prints a deprecation notice on
    # every event. Normalise once, here.
    level = normalize(level)

    if meet_level?(level, state.level) do
      formatted_timestamp = format_timestamp(timestamp)
      formatted_message = format_message(message)
      
      metadata_map = 
        metadata
        |> Enum.into(%{})
        |> Map.take([:module, :function, :file, :line, :request_id, :pid])
      
      Bacon8.LogBuffer.add_entry(level, "#{formatted_timestamp} [#{level}] #{formatted_message}", metadata_map)
    end
    
    {:ok, state}
  end

  @impl true
  def handle_event(:flush, state) do
    {:ok, state}
  end

  @impl true
  def handle_event(_, state) do
    {:ok, state}
  end

  @impl true
  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  defp normalize(:warn), do: :warning
  defp normalize(level), do: level

  defp meet_level?(level, min_level) do
    Logger.compare_levels(level, min_level) != :lt
  end

  defp format_timestamp({{year, month, day}, {hour, min, sec, _micro}}) do
    :io_lib.format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B", 
                   [year, month, day, hour, min, sec])
    |> IO.iodata_to_binary()
  end

  defp format_message(message) when is_binary(message), do: message
  defp format_message(message) when is_list(message), do: IO.iodata_to_binary(message)
  defp format_message(message), do: inspect(message)
end
