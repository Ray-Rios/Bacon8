defmodule Mix.Tasks.Drive.Import do
  @shortdoc "Imports legacy user files into the drive (safe to re-run)"
  @moduledoc """
  Copies legacy `user_files`, `user_folders` and `uploads/users/**` into
  `Bacon8.Drive`. See `Bacon8.Drive.Import`.

      mix drive.import            # import
      mix drive.import --dry-run  # count only

  In a release use `bin/bacon8 eval "Bacon8.Drive.Import.run()"`.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [dry_run: :boolean])
    totals = Bacon8.Drive.Import.run(dry_run: Keyword.get(opts, :dry_run, false))
    Mix.shell().info("Drive import: #{inspect(totals)}")
  end
end
