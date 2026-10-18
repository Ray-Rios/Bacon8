defmodule Bacon8.EmailLogging do
  @moduledoc """
  The EmailLogging context.
  """

  import Ecto.Query, warn: false
  alias Bacon8.Repo
  alias Bacon8.EmailLogging.EmailLog

  @doc """
  Returns the list of email_logs.
  """
  def list_email_logs do
    Repo.all(from e in EmailLog, order_by: [desc: e.sent_at])
  end

  @doc """
  Gets a single email_log.
  """
  def get_email_log!(id), do: Repo.get!(EmailLog, id)

  @doc """
  Creates a email_log.
  """
  def create_email_log(attrs \\ %{}) do
    %EmailLog{}
    |> EmailLog.changeset(attrs)
    |> Repo.insert()
  end
end
