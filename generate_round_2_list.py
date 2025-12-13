import subprocess

def get_remaining_large_files():
    cmd = "git rev-list --objects --all | git cat-file --batch-check='%(objectname) %(objecttype) %(objectsize) %(rest)' | sort -rnk 3 | head -n 50"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    files_to_remove = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) > 3:
            # parts[0] is hash, parts[1] is type, parts[2] is size
            # parts[3:] is the path, which might contain spaces
            file_path = " ".join(parts[3:])
            if parts[1] == "blob":
                # We want to remove large blobs, let's say > 1MB to be safe, or just specific ones we know are data/images
                size = int(parts[2])
                if size > 1024 * 1024: # > 1MB
                     files_to_remove.append(file_path)
                elif "data/" in file_path or "docs/images/" in file_path:
                     # Also remove any data or images that might be lingering if they are in the top 50
                     files_to_remove.append(file_path)

    return files_to_remove

files = get_remaining_large_files()
with open("files_to_remove_round_2.txt", "w") as f:
    for file_path in files:
        f.write(f"{file_path}\n")

print(f"Found {len(files)} files to remove.")
