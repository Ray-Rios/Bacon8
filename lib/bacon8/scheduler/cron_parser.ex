defmodule Bacon8.Scheduler.CronParser do
  @moduledoc """
  Simple cron expression parser for computing next run times.
  
  Supports standard 5-field cron expressions:
  - minute (0-59)
  - hour (0-23)
  - day of month (1-31)
  - month (1-12)
  - day of week (0-7, where 0 and 7 are Sunday)
  
  Special characters:
  - * : any value
  - , : value list separator
  - - : range of values
  - / : step values
  
  Examples:
  - "0 9 * * 1"     - 9:00 AM every Monday
  - "*/15 * * * *" - Every 15 minutes
  - "0 0 1 * *"    - Midnight on the 1st of every month
  - "30 8 * * 1-5" - 8:30 AM Monday through Friday
  """

  @doc """
  Parse a cron expression and compute the next run time after the given datetime.
  Returns {:ok, DateTime.t()} or {:error, reason}
  """
  def next_run(cron_expression, after_time \\ nil) do
    after_time = after_time || DateTime.utc_now()
    
    case parse(cron_expression) do
      {:ok, cron} ->
        find_next_run(cron, after_time, 0)
      {:error, _} = error ->
        error
    end
  end

  @doc """
  Parse a cron expression into a structured format.
  """
  def parse(expression) when is_binary(expression) do
    parts = String.split(expression, ~r/\s+/, trim: true)
    
    case length(parts) do
      5 ->
        [minute, hour, day, month, weekday] = parts
        
        with {:ok, minutes} <- parse_field(minute, 0, 59),
             {:ok, hours} <- parse_field(hour, 0, 23),
             {:ok, days} <- parse_field(day, 1, 31),
             {:ok, months} <- parse_field(month, 1, 12),
             {:ok, weekdays} <- parse_field(weekday, 0, 7) do
          # Normalize Sunday (7 -> 0)
          weekdays = Enum.map(weekdays, fn d -> if d == 7, do: 0, else: d end) |> Enum.uniq()
          
          {:ok, %{
            minutes: MapSet.new(minutes),
            hours: MapSet.new(hours),
            days: MapSet.new(days),
            months: MapSet.new(months),
            weekdays: MapSet.new(weekdays)
          }}
        end
        
      _ ->
        {:error, "Invalid cron expression: expected 5 fields"}
    end
  end

  defp parse_field("*", min, max), do: {:ok, Enum.to_list(min..max)}
  
  defp parse_field(field, min, max) do
    cond do
      # Step: */n or range/n
      String.contains?(field, "/") ->
        parse_step(field, min, max)
        
      # Range: n-m
      String.contains?(field, "-") && !String.contains?(field, ",") ->
        parse_range(field, min, max)
        
      # List: n,m,o
      String.contains?(field, ",") ->
        parse_list(field, min, max)
        
      # Single value
      true ->
        case Integer.parse(field) do
          {val, ""} when val >= min and val <= max ->
            {:ok, [val]}
          _ ->
            {:error, "Invalid value: #{field}"}
        end
    end
  end

  defp parse_step(field, min, max) do
    case String.split(field, "/") do
      [range_part, step_str] ->
        case Integer.parse(step_str) do
          {step, ""} when step > 0 ->
            start_vals = if range_part == "*" do
              {:ok, min}
            else
              case parse_range(range_part, min, max) do
                {:ok, [first | _]} -> {:ok, first}
                {:ok, []} -> {:error, "Empty range"}
                error -> error
              end
            end
            
            case start_vals do
              {:ok, start} ->
                vals = for v <- start..max, rem(v - start, step) == 0, do: v
                {:ok, vals}
              error -> error
            end
            
          _ ->
            {:error, "Invalid step: #{step_str}"}
        end
        
      _ ->
        {:error, "Invalid step expression: #{field}"}
    end
  end

  defp parse_range(field, min, max) do
    case String.split(field, "-") do
      [start_str, end_str] ->
        with {start_val, ""} <- Integer.parse(start_str),
             {end_val, ""} <- Integer.parse(end_str),
             true <- start_val >= min and end_val <= max and start_val <= end_val do
          {:ok, Enum.to_list(start_val..end_val)}
        else
          _ -> {:error, "Invalid range: #{field}"}
        end
        
      _ ->
        {:error, "Invalid range expression: #{field}"}
    end
  end

  defp parse_list(field, min, max) do
    parts = String.split(field, ",")
    
    results = Enum.reduce_while(parts, [], fn part, acc ->
      case parse_field(String.trim(part), min, max) do
        {:ok, vals} -> {:cont, acc ++ vals}
        {:error, _} = error -> {:halt, error}
      end
    end)
    
    case results do
      {:error, _} = error -> error
      vals -> {:ok, Enum.uniq(vals)}
    end
  end

  defp find_next_run(_cron, _time, iterations) when iterations > 366 * 24 * 60 do
    {:error, "Could not find next run time within a year"}
  end

  defp find_next_run(cron, time, iterations) do
    # Add one minute to start
    time = if iterations == 0 do
      DateTime.add(time, 60, :second)
    else
      time
    end
    
    # Truncate to minute
    time = %{time | second: 0, microsecond: {0, 0}}
    
    if matches?(cron, time) do
      {:ok, time}
    else
      # Try next minute
      next_time = DateTime.add(time, 60, :second)
      find_next_run(cron, next_time, iterations + 1)
    end
  end

  defp matches?(cron, %DateTime{} = dt) do
    minute = dt.minute
    hour = dt.hour
    day = dt.day
    month = dt.month
    weekday = Date.day_of_week(DateTime.to_date(dt))
    # Convert Elixir's 1=Monday..7=Sunday to cron's 0=Sunday..6=Saturday
    weekday = if weekday == 7, do: 0, else: weekday
    
    MapSet.member?(cron.minutes, minute) &&
    MapSet.member?(cron.hours, hour) &&
    MapSet.member?(cron.months, month) &&
    (MapSet.member?(cron.days, day) || MapSet.member?(cron.weekdays, weekday))
  end

  @doc """
  Validate a cron expression.
  """
  def valid?(expression) do
    case parse(expression) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Human-readable description of a cron expression.
  """
  def describe(expression) do
    case parse(expression) do
      {:ok, cron} ->
        parts = []
        
        parts = parts ++ [describe_field(cron.minutes, "minute", 0, 59)]
        parts = parts ++ [describe_field(cron.hours, "hour", 0, 23)]
        parts = parts ++ [describe_field(cron.days, "day", 1, 31)]
        parts = parts ++ [describe_field(cron.months, "month", 1, 12)]
        parts = parts ++ [describe_weekdays(cron.weekdays)]
        
        {:ok, Enum.filter(parts, & &1) |> Enum.join(", ")}
        
      {:error, _} = error ->
        error
    end
  end

  defp describe_field(values, _name, min, max) do
    all = MapSet.new(min..max)
    if MapSet.equal?(values, all), do: nil, else: nil
  end

  defp describe_weekdays(values) do
    all = MapSet.new(0..6)
    if MapSet.equal?(values, all), do: nil, else: nil
  end
end
