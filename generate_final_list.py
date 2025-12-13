import subprocess

def get_large_objects():
    # Get top 50 large objects
    cmd = "git rev-list --objects --all | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | sed -n 's/^blob //p' | sort -rn -k 2 | head -n 50"
    output = subprocess.check_output(cmd, shell=True).decode()
    files = []
    for line in output.splitlines():
        parts = line.split()
        if len(parts) >= 3:
            # parts[0] is hash, parts[1] is size, parts[2:] is path
            path = " ".join(parts[2:])
            files.append(path)
    return files

def get_all_data_files():
    output = subprocess.check_output(['git', 'rev-list', '--objects', '--all']).decode()
    files = set()
    for line in output.splitlines():
        parts = line.split(' ', 1)
        if len(parts) == 2:
            path = parts[1]
            if path.startswith('data/'):
                files.add(path)
    return files

large_files = get_large_objects()
all_data_files = get_all_data_files()

to_remove = set()

# Add all large files that look like data or images
for f in large_files:
    if f.startswith('data/') or f.endswith('.png') or f.endswith('.csv') or f.endswith('.geojson'):
        to_remove.add(f)

# Add all data files except README and scripts
for f in all_data_files:
    if f == 'data/README.md':
        continue
    if f == 'data/processing_scripts' or f.startswith('data/processing_scripts/'):
        continue
    to_remove.add(f)

with open('files_to_remove_final.txt', 'w') as f:
    for path in to_remove:
        f.write(f'"{path}"\n')

print(f"Found {len(to_remove)} files to remove.")
