defmodule Bacon8.EmailLogging.TelemetryHandler do
  require Logger
  alias Bacon8.EmailLogging

  def attach do
    :telemetry.attach(
      "email-logger",
      [:swoosh, :deliver, :stop],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:swoosh, :deliver, :stop], _measurements, metadata, _config) do
    email = metadata.email
    
    # Extract recipient (Swoosh stores as list of tuples or strings)
    to = case email.to do
      [{name, address}] -> "#{name} <#{address}>"
      [{_name, address} | _] -> address # Just take first one for now
      [address | _] -> address
      _ -> "unknown"
    end

    from = case email.from do
      {name, address} -> "#{name} <#{address}>"
      address when is_binary(address) -> address
      _ -> "unknown"
    end

    status = if Map.has_key?(metadata, :error), do: "failed", else: "sent"
    error = if Map.has_key?(metadata, :error), do: inspect(metadata.error), else: nil

    attrs = %{
      to: to,
      from: from,
      subject: email.subject,
      html_body: email.html_body,
      text_body: email.text_body,
      provider: Atom.to_string(email.provider_options[:adapter] || :unknown),
      status: status,
      error: error,
      sent_at: DateTime.utc_now()
    }

    # Run in a separate task to avoid blocking the mailer process
    Task.start(fn ->
      case EmailLogging.create_email_log(attrs) do
        {:ok, _} -> :ok
        {:error, changeset} -> 
          Logger.error("Failed to log email: #{inspect(changeset)}")
      end
    end)
  end
end
