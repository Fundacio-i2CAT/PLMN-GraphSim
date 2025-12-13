import subprocess

def get_commits():
    return subprocess.check_output(['git', 'rev-list', '--all']).decode().splitlines()

def check_commit(commit):
    try:
        files = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', commit]).decode().splitlines()
        for f in files:
            if f.startswith('data/spain') or f.startswith('data/usa'):
                print(f"Found in commit {commit}: {f}")
                return True
    except:
        pass
    return False

commits = get_commits()
for c in commits:
    if check_commit(c):
        break
