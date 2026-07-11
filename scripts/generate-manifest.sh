#!/usr/bin/env bash
#
# Generates adhans.json (repo root) with two sections:
#
#   * "adhans"    — scanned from downloads/adhans for valid adhan "leaf" directories.
#                   A leaf directory is valid when it contains the three core segments
#                   debut/milieu/fin (fajr is optional and marks a Fajr-capable adhan).
#                   Each entry's label comes from the directory's meta.json
#                   ({"label": "..."}); if missing, it's derived from the path. Segment
#                   files must use the canonical names debut.ogg / milieu.ogg /
#                   fajr.ogg / fin.ogg — non-canonical files are reported and skipped.
#
#   * "reminders" — scanned from downloads/reminders for single audio files. Each entry
#                   is { id, path, file } where id is the file name without extension.
#                   The app derives a readable label from the file name at runtime.
#
# Usage: scripts/generate-manifest.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
adhans_dir="$repo_root/downloads/adhans"
reminders_dir="$repo_root/downloads/reminders"
out="$repo_root/adhans.json"

if [ ! -d "$adhans_dir" ]; then
  echo "error: $adhans_dir not found" >&2
  exit 1
fi

# Reads the "label" value from a meta.json, or empty string if absent/unparseable.
read_label() {
  local meta="$1"
  [ -f "$meta" ] || { printf ''; return; }
  # Extract the string value of the first "label": "..." pair.
  sed -n 's/.*"label"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$meta" | head -n1
}

# Best-effort duration probe in milliseconds (empty string if unknown).
duration_ms() {
  local file="$1"
  [ -f "$file" ] || { printf ''; return; }
  if command -v afinfo >/dev/null 2>&1; then
    local seconds
    seconds="$(afinfo "$file" 2>/dev/null | awk '/estimated duration:/ { print $3; exit }')"
    if [ -n "$seconds" ]; then
      awk -v s="$seconds" 'BEGIN { printf "%.0f", s * 1000 }'
      return
    fi
  fi
  printf ''
}

# Title-cases a slug like "haramayn/01" into a readable fallback label.
derive_label() {
  local id="$1"
  local family="${id%%/*}"
  local style="${id##*/}"
  local cap
  cap="$(printf '%s' "$family" | awk '{ print toupper(substr($0,1,1)) substr($0,2) }')"
  # Strip leading zeros from the style number for the label.
  local n="$((10#$style))"
  printf '%s Adhan - Style %s' "$cap" "$n"
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

entries=""
count=0
warnings=0

# Find leaf directories (deepest dirs) under downloads/adhans, sorted for stable output.
while IFS= read -r dir; do
  [ -d "$dir" ] || continue
  # Only consider directories that directly contain segment files.
  [ -f "$dir/debut.ogg" ] && [ -f "$dir/milieu.ogg" ] && [ -f "$dir/fin.ogg" ] || continue

  id="${dir#"$adhans_dir/"}"

  # Warn about non-canonical audio files so they can be fixed.
  for f in "$dir"/*.ogg; do
    b="$(basename "$f")"
    case "$b" in
      debut.ogg|milieu.ogg|fajr.ogg|fin.ogg) ;;
      *) echo "warning: $id has non-canonical segment '$b' (ignored)" >&2; warnings=$((warnings+1)) ;;
    esac
  done

  files='"debut.ogg", "milieu.ogg"'
  has_fajr=false
  total_duration=0
  has_duration=true
  seg_duration="$(duration_ms "$dir/debut.ogg")"
  if [ -n "$seg_duration" ]; then total_duration=$((total_duration + seg_duration)); else has_duration=false; fi
  seg_duration="$(duration_ms "$dir/milieu.ogg")"
  if [ -n "$seg_duration" ]; then total_duration=$((total_duration + seg_duration)); else has_duration=false; fi
  if [ -f "$dir/fajr.ogg" ]; then
    files="$files, \"fajr.ogg\""
    has_fajr=true
    seg_duration="$(duration_ms "$dir/fajr.ogg")"
    if [ -n "$seg_duration" ]; then total_duration=$((total_duration + seg_duration)); else has_duration=false; fi
  fi
  files="$files, \"fin.ogg\""
  seg_duration="$(duration_ms "$dir/fin.ogg")"
  if [ -n "$seg_duration" ]; then total_duration=$((total_duration + seg_duration)); else has_duration=false; fi
  if [ "$has_duration" = true ]; then
    duration_line=",
      \"durationMs\": $total_duration"
  else
    duration_line=""
  fi

  label="$(read_label "$dir/meta.json")"
  [ -n "$label" ] || label="$(derive_label "$id")"
  label="$(json_escape "$label")"

  entry=$(cat <<EOF
    {
      "id": "$id",
      "label": "$label",
      "hasFajr": $has_fajr$duration_line,
      "path": "downloads/adhans/$id",
      "files": [$files]
    }
EOF
)
  if [ -n "$entries" ]; then
    entries="$entries,
$entry"
  else
    entries="$entry"
  fi
  count=$((count+1))
done < <(find "$adhans_dir" -type d | sort)

# --- Reminders: single audio files directly under downloads/reminders ---------------
reminder_entries=""
reminder_count=0

if [ -d "$reminders_dir" ]; then
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    base="$(basename "$file")"
    case "$base" in
      *.ogg|*.mp3|*.wav|*.m4a|*.aac|*.flac|*.opus) ;;
      *) continue ;;
    esac
    id="${base%.*}"
    reminder_duration="$(duration_ms "$file")"
    if [ -n "$reminder_duration" ]; then
      duration_field=",
      \"durationMs\": $reminder_duration"
    else
      duration_field=""
    fi
    entry=$(cat <<EOF
    {
      "id": "$(json_escape "$id")",
      "path": "downloads/reminders",
      "file": "$(json_escape "$base")"$duration_field
    }
EOF
)
    if [ -n "$reminder_entries" ]; then
      reminder_entries="$reminder_entries,
$entry"
    else
      reminder_entries="$entry"
    fi
    reminder_count=$((reminder_count+1))
  done < <(find "$reminders_dir" -maxdepth 1 -type f | sort)
fi

{
  echo "{"
  echo "  \"version\": 1,"
  echo "  \"adhans\": ["
  [ -n "$entries" ] && printf '%s\n' "$entries"
  echo "  ],"
  echo "  \"reminders\": ["
  [ -n "$reminder_entries" ] && printf '%s\n' "$reminder_entries"
  echo "  ]"
  echo "}"
} > "$out"

echo "Wrote $out ($count adhan(s), $reminder_count reminder(s), $warnings warning(s))"
