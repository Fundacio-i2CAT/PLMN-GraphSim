import subprocess

def get_remaining_large_files():
    # Get top 100 large objects
    cmd = "git rev-list --objects --all | git cat-file --batch-check='%(objectname) %(objecttype) %(objectsize) %(rest)' | sort -rnk 3 | head -n 100"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    
    files_to_remove = []
    seen_files = set()

    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) > 3:
            # parts[0] is hash, parts[1] is type, parts[2] is size
            # parts[3:] is the path
            file_path = " ".join(parts[3:])
            
            if parts[1] == "blob":
                size = int(parts[2])
                # Filter: > 500KB OR in data/ OR in images/
                if size > 500 * 1024 or "data/" in file_path or "images/" in file_path:
                    if file_path not in seen_files:
                        files_to_remove.append(file_path)
                        seen_files.add(file_path)

    return files_to_remove

files = get_remaining_large_files()
with open("files_to_remove_round_3.txt", "w") as f:
    for file_path in files:
        f.write(f"{file_path}\n")

print(f"Found {len(files)} files to remove in Round 3.")
