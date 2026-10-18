defmodule UploadMigrator do
  def run do
    # Determine base path
    base_path = if File.exists?("/app/uploads"), do: "/app/uploads", else: "uploads"
    base_path = Path.expand(base_path)
    
    IO.puts "Checking for legacy uploads in: #{base_path}"
    
    user_files_path = Path.join(base_path, "users")
    
    if File.exists?(user_files_path) do
      IO.puts "Found legacy 'users' directory. Starting migration..."
      
      File.ls!(user_files_path)
      |> Enum.each(fn user_id ->
        source_dir = Path.join(user_files_path, user_id)
        
        if File.dir?(source_dir) do
          # Target: uploads/{user_id}/files
          target_dir = Path.join([base_path, user_id, "files"])
          File.mkdir_p!(target_dir)
          
          IO.puts "Migrating user #{user_id}..."
          
          # Recursively find all files in source_dir
          Path.wildcard(Path.join(source_dir, "**/*"))
          |> Enum.filter(&File.regular?/1)
          |> Enum.each(fn source_file ->
            filename = Path.basename(source_file)
            target_file = Path.join(target_dir, filename)
            
            IO.puts "  Moving #{filename} to #{target_file}"
            case File.rename(source_file, target_file) do
              :ok -> :ok
              {:error, reason} -> IO.puts "  Error moving #{filename}: #{inspect(reason)}"
            end
          end)
          
          # Clean up source directory
          File.rm_rf(source_dir)
        end
      end)
      
      case File.rmdir(user_files_path) do
        :ok -> IO.puts "Migration complete. 'users' directory removed."
        {:error, _} -> IO.puts "Migration complete. 'users' directory could not be removed (might not be empty)."
      end
    else
      IO.puts "No 'users' directory found. No migration needed."
    end
  end
end

UploadMigrator.run()
