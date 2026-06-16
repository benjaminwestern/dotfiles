#!/usr/bin/env bash
set -euo pipefail

CODE_DIR="$HOME/code"
EXCLUDE_DIRS_NAMES=(
    "node_modules" ".terraform" "vendor" "bower_components" 
    ".cache" "build" "dist" "target" ".venv" "venv" ".direnv"
) 

if [ ! -d "$CODE_DIR" ]; then
  echo "Error: Directory '$CODE_DIR' not found." >&2
  exit 1
fi

echo "Recursively checking Git status under '$CODE_DIR'..."
echo "Excluding directories named: ${EXCLUDE_DIRS_NAMES[*]}"
echo "Only showing repositories with changes."
echo "=============================================================="

prune_conditions=()
for dir_name in "${EXCLUDE_DIRS_NAMES[@]}"; do
  if [ ${#prune_conditions[@]} -gt 0 ]; then
    prune_conditions+=("-o")
  fi
  prune_conditions+=("-name" "$dir_name")
done

find_command_args=()
if [ ${#prune_conditions[@]} -gt 0 ]; then
  find_command_args=(
    "$CODE_DIR"
    \( "${prune_conditions[@]}" \) -a -type d -prune
    -o
    \( -path '*/.git' -type d -print0 \)
  )
else
  find_command_args=(
    "$CODE_DIR"
    -path '*/.git' -type d -print0
  )
fi

find "${find_command_args[@]}" | while IFS= read -r -d $'\0' git_dir_path; do
  repo_path="$(dirname "$git_dir_path")"
  
  repo_basename=$(basename "$repo_path")
  is_excluded_basename=0
  for excluded_name in "${EXCLUDE_DIRS_NAMES[@]}"; do
      if [[ "$repo_basename" == "$excluded_name" ]]; then
          is_excluded_basename=1
          break
      fi
  done
  if [[ "$is_excluded_basename" -eq 1 ]]; then
      continue 
  fi
  
  subshell_output=$(
    cd "$repo_path"
    
    git_changes=$(git status --porcelain)
    
    if [ -n "$git_changes" ]; then
      echo "" 
      echo "--- Status for: $(basename "$repo_path") ---"
      relative_repo_path="${repo_path#$CODE_DIR/}"
      if [ "$relative_repo_path" = "$repo_path" ] && [[ "$CODE_DIR" != *"/" ]]; then
          relative_repo_path="${repo_path#$CODE_DIR}" 
          relative_repo_path="${relative_repo_path#/}" 
      elif [ "$relative_repo_path" = "$repo_path" ]; then 
          relative_repo_path="$(basename "$repo_path")"
      fi
      echo "Path: $CODE_DIR/$relative_repo_path"
      
      git -c color.status=always status 
      echo "------------------------------------"
      echo "__HAS_CHANGES__" 
    fi
  )

  if [[ "$subshell_output" == *"__HAS_CHANGES__"* ]]; then
    printf "%s\n" "${subshell_output//__HAS_CHANGES__/}"
  fi
done

exit 0
