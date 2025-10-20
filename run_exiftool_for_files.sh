#!/usr/bin/env bash
# Run exiftool over a tree of media files and apply metadata from sibling
# supplemental JSON files.
# Usage: run_exiftool_for_files.sh [--dry-run] [--jobs N] <root-dir>
#
# This script finds files by extension (jpg jpeg png gif webp heic mov mp4
# 3gp avi mkv webm), looks for a sibling JSON named <basename>.supplemental-metadata.json
# in the same directory and, if present, extracts timestamp/GPS/tags/description
# from that JSON and applies them to the file using exiftool.
#
# Notes:
# - The supplemental JSON must be in the same directory and share the file's
#   basename (filename without extension), e.g. IMG-0001.jpg -> IMG-0001.supplemental-metadata.json.
#
# Options:
#   --dry-run    Print exiftool commands instead of running them
#   --jobs N     Run up to N worker processes in parallel (default: 1)

set -eo pipefail

DRY_RUN=0
JOBS=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1; shift ;;
    --jobs*)
      # supports both '--jobs N' and '--jobs=N'
      if [[ "$1" == *=* ]]; then
        JOBS="${1#*=}"; shift
      else
        JOBS="$2"; shift 2
      fi ;;
    -h|--help)
      sed -n '2,17p' "$0"; exit 0 ;;
    *)
      ROOT_DIR="$1"; shift ;;
  esac
done

if [[ -z "$ROOT_DIR" ]]; then
  echo "Error: root directory is required." >&2
  echo "Usage: $0 [--dry-run] [--jobs N] <root-dir>" >&2
  exit 2
fi

if ! command -v exiftool >/dev/null 2>&1; then
  echo "exiftool not found in PATH. Please install it." >&2
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found in PATH. Please install jq (used to parse supplemental JSON)." >&2
  exit 4
fi

export DRY_RUN JOBS

## worker function: process a single image path
process_file() {
  img="$1"
  DRY_RUN=${DRY_RUN:-0}

  dir=$(dirname -- "$img")
  file=$(basename -- "$img")
  jsonfile="$dir/$file.supplemental-metadata.json"

  if [[ ! -f "$jsonfile" ]]; then
    echo "[SKIP] supplemental JSON not found for: $img -> expected $jsonfile"
    return 0
  fi

  # extract data
  epoch=$(jq -r '.photoTakenTime.timestamp // .creationTime.timestamp // empty' "$jsonfile" 2>/dev/null || echo "")
  lat=$(jq -r '.geoData.latitude // empty' "$jsonfile" 2>/dev/null || echo "")
  lon=$(jq -r '.geoData.longitude // empty' "$jsonfile" 2>/dev/null || echo "")
  alt=$(jq -r '.geoData.altitude // empty' "$jsonfile" 2>/dev/null || echo "")
  description=$(jq -r '.description // empty' "$jsonfile" 2>/dev/null || echo "")
  tags=$(jq -r '(.tags // .Tags // .labels // .Labels // .keywords // .Keywords) as $t | if $t==null then empty elif ($t|type)=="array" then ($t|map(tostring)|join(", ")) else ($t|tostring) end' "$jsonfile" 2>/dev/null || echo "")

  dt=""
  if [[ -n "$epoch" && "$epoch" != "null" ]]; then
    epoch=${epoch%%.*}
    if date -u -d "@$epoch" +"%Y:%m:%d %H:%M:%S Z" >/dev/null 2>&1; then
      dt=$(date -u -d "@$epoch" +"%Y:%m:%d %H:%M:%S Z")
    fi
  fi

  # helper to detect numeric zero (handles 0, 0.0, 0.000)
  is_zero() {
    local v="$1"
    if [[ -z "$v" ]]; then
      return 0
    fi
    awk -v val="$v" 'BEGIN{ if(val+0==0) exit 0; exit 1 }'
  }

  cmd=(exiftool -overwrite_original -progress)
  if [[ -n "$dt" ]]; then
    cmd+=("-DateTimeOriginal=$dt" "-CreateDate=$dt" "-AllDates=$dt" "-TrackCreateDate=$dt" "-TrackModifyDate=$dt" "-MediaCreateDate=$dt" "-MediaModifyDate=$dt" "-OffsetTimeOriginal=+00:00")
  fi
  if ! is_zero "$lat" && ! is_zero "$lon"; then
    cmd+=("-GPSLatitude=$lat" "-GPSLongitude=$lon")
    if ! is_zero "$alt"; then
      cmd+=("-GPSAltitude=$alt")
    fi
  fi
  if [[ -n "$tags" ]]; then
    cmd+=("-Keywords=$tags" "-Subject=$tags" "-TagsList=$tags")
  fi
  if [[ -n "$description" ]]; then
    cmd+=("-Caption-Abstract=$description" "-ImageDescription=$description" "-XPComment=$description" "-Description=$description")
  fi
  cmd+=("$img")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "DRY RUN: "; for a in "${cmd[@]}"; do printf '%q ' "$a"; done; printf "\n"
    return 0
  fi

  "${cmd[@]}"
}

# export function so sub-bash instances invoked by xargs can call it
export -f process_file

# Find files matching pattern: -WA<number> with a variety of media extensions
# We use -regextype posix-extended and -iregex (case-insensitive). The regex
# matches the full path that find provides, so include the root dir prefix.
EXT_REGEX='(jpg|jpeg|png|gif|webp|heic|mov|mp4|3gp|avi|mkv|webm)'
FIND_REGEX="$ROOT_DIR/.*\\.($EXT_REGEX)$"

echo "Searching in: $ROOT_DIR"

# Use find to print full paths, then pipe null-delimited paths to xargs which
# will call the exported process_file function in a subshell.
if [[ "$JOBS" -gt 1 ]]; then
  find "$ROOT_DIR" -type f -regextype posix-extended -iregex "$FIND_REGEX" -print0 \
    | xargs -0 -n1 -P "$JOBS" bash -c 'process_file "$1"' _
else
  find "$ROOT_DIR" -type f -regextype posix-extended -iregex "$FIND_REGEX" -print0 \
    | xargs -0 -n1 bash -c 'process_file "$1"' _
fi

echo "Done."
