import subprocess

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

files = get_all_data_files()
to_remove = []
for f in files:
    if f == 'data/README.md':
        continue
    if f == 'data/processing_scripts' or f.startswith('data/processing_scripts/'):
        continue
    to_remove.append(f)

with open('files_to_remove.txt', 'w') as f:
    # Join with spaces
    f.write(" ".join(to_remove))

print(f"Found {len(to_remove)} files to remove.")
