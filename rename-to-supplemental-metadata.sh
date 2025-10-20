#!/usr/bin/env bash
set -euo pipefail

# rename-to-supplemental-metadata.sh
# Recursively rename files matching: <name>.<type>.<whatever>.json
# to: <name>.<type>.supplemental-metadata.json
#
# By default performs a dry-run and prints proposed renames.
# Use -f or --force to actually perform the rename operations.
# Use -n or --noop for explicit dry-run (same as default).
#
# Examples:
#   ./rename-to-supplemental-metadata.sh           # dry-run
#   ./rename-to-supplemental-metadata.sh -f        # perform renames
#   ./rename-to-supplemental-metadata.sh -d path   # run in specific directory

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -f, --force       Actually perform renames (default: dry-run)
  -d DIR, --dir DIR Directory to scan (default: current directory)
  -h, --help        Show this help message

This script finds files ending with .json that have at least two dots before .json
(e.g. IMG_1234.jpg.supplemental-meta(1).json) and renames them to use
.supplemental-metadata.json for the metadata suffix.

It will skip files that already end with .supplemental-metadata.json.
EOF
}

# Defaults
FORCE=0
TARGET_DIR="."

# Parse args
while [[ ${#} -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE=1
      shift
      ;;
    -d|--dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --) shift; break;;
    -* ) echo "Unknown option: $1"; usage; exit 1;;
    * ) break;;
  esac
done

# Safety: ensure dir exists
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Directory not found: $TARGET_DIR" >&2
  exit 2
fi

# Find candidate json files
# We want files that have at least two dots before the .json suffix
# Regex explanation (bash extglob): match filenames containing at least two dots
# We'll use a find + perl-compatible regex to capture groups and build new filename

shopt -s nullglob

declare -a ACTIONS
FOUND=0

# Use a null-delimited find + read loop to safely handle any filenames and recurse
while IFS= read -r -d '' f; do
  FOUND=1

  # Skip files that already end with .supplemental-metadata.json
  if [[ "$f" == *.supplemental-metadata.json ]]; then
    continue
  fi

  # Get the filename (no dir), and dir
  dir=$(dirname -- "$f")
  base=$(basename -- "$f")

  # Split base by dots
  IFS='.' read -r -a parts <<< "$base"
  # parts includes the final 'json'
  len=${#parts[@]}
  # Require at least: name.type.something.json => parts >= 4
  if (( len < 4 )); then
    continue
  fi

  # Reconstruct name and type (first two parts)
  name="${parts[0]}"
  type="${parts[1]}"

  # Determine suffix. We only support two forms:
  #  - filename(1).jpg.something.json  -> suffix attached to the filename
  #  - filename.jpg.something(1).json  -> suffix attached to the final component
  # Normalize by stripping the suffix from the component where it appears and
  # appending it to the final name as name<suffix>.<type>.supplemental-metadata.json
  suffix=""
  last_comp="${parts[len-2]}"

  # 1) check name (filename(1).ext.json)
  if [[ ${name} =~ \([0-9]+\)$ ]]; then
    suffix="${BASH_REMATCH[0]}"
    name="${name%${suffix}}"
  elif [[ ${last_comp} =~ \([0-9]+\)$ ]]; then
    # 2) suffix on the final component before .json (e.g. supplemental(1).json)
    suffix="${BASH_REMATCH[0]}"
  fi

  newbase="${name}${suffix}.${type}.supplemental-metadata.json"
  newpath="${dir}/${newbase}"

  # If the target already exists, record skip; otherwise record rename (and perform it if forced)
  if [[ -e "$newpath" ]]; then
    ACTIONS+=("SKIP_EXISTS: $f -> $newpath")
  else
    ACTIONS+=("RENAME: $f -> $newpath")
    if (( FORCE == 1 )); then
      mv -- "$f" "$newpath"
    fi
  fi
done < <(find "$TARGET_DIR" -type f -name "*.json" -print0)

if [[ $FOUND -eq 0 ]]; then
  echo "No .json files found under $TARGET_DIR"
  exit 0
fi

# Print results
if (( ${#ACTIONS[@]} == 0 )); then
  echo "No candidate files found to rename under $TARGET_DIR"
  exit 0
fi

if (( FORCE == 1 )); then
  echo "Performed the following actions:"
else
  echo "Dry-run: the following renames would be performed (use -f to apply):"
fi

for a in "${ACTIONS[@]}"; do
  echo "$a"
done

exit 0
