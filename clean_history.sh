#!/bin/bash

# Read the generated git rm command
GIT_RM_CMD=$(cat git_rm_cmd_round_3.txt)

echo "Running filter-branch with command: $GIT_RM_CMD"

# Run git filter-branch
git filter-branch --force --index-filter "$GIT_RM_CMD" --prune-empty --tag-name-filter cat -- --all
