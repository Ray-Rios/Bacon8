defmodule Bacon8.Repo do
  use Ecto.Repo,
    otp_app: :bacon8,
    adapter: Ecto.Adapters.Postgres
end