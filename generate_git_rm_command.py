import shlex

with open("files_to_remove_round_4.txt", "r") as f:
    files = [line.strip() for line in f if line.strip()]

# Construct the command
# git rm --cached --ignore-unmatch -r file1 file2 ...
quoted_files = [shlex.quote(f) for f in files]
command = "git rm --cached --ignore-unmatch -r " + " ".join(quoted_files)

print(command)
