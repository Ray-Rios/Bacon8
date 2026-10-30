defmodule Bacon8.Repo.Migrations.DropLegacyUserFiles do
  use Ecto.Migration

  # The legacy upload system (user_files, user_folders) was replaced by the drive in 2026-10 and its code
  # was deleted on 2026-10-29. Production's tables were empty when last checked (2026-10-15).
  #
  # Each table is dropped ONLY IF IT IS EMPTY. A table that still holds rows is left alone (and the deploy
  # goes on), so this migration can never destroy data. An install that still has rows should run the old
  # `Bacon8.Drive.Import` first (git history: lib/bacon8/drive/import.ex), then drop the tables by hand.
  def up do
    for table <- ["user_files", "user_folders"] do
      execute("""
      DO $$
      BEGIN
        IF to_regclass('public.#{table}') IS NOT NULL THEN
          IF NOT EXISTS (SELECT 1 FROM public.#{table}) THEN
            DROP TABLE public.#{table};
          ELSE
            RAISE NOTICE '#{table} still has rows; leaving it in place';
          END IF;
        END IF;
      END
      $$;
      """)
    end
  end

  def down do
    # The tables were empty and nothing reads or writes them; the baseline migration
    # (20250101000001_site_baseline.exs) has their definitions if they are ever needed.
    :ok
  end
end
