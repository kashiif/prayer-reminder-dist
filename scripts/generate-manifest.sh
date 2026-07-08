#!/usr/bin/env bash
#
# Generates adhans.json (repo root) by scanning downloads/adhans for valid adhan
# "leaf" directories. A leaf directory is valid when it contains the three core
# segments debut/milieu/fin (fajr is optional and marks a Fajr-capable adhan).
#
# Each entry's label comes from the directory's meta.json ({"label": "..."}); if
# that's missing the label is derived from the path. Segment files must use the
# canonical names debut.ogg / milieu.ogg / fajr.ogg / fin.ogg — the app downloads
# them by those names, so non-canonical files are reported and skipped.
#
# Usage: scripts/generate-manifest.sh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
adhans_dir="$repo_root/downloads/adhans"
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
  if [ -f "$dir/fajr.ogg" ]; then
    files="$files, \"fajr.ogg\""
    has_fajr=true
  fi
  files="$files, \"fin.ogg\""

  label="$(read_label "$dir/meta.json")"
  [ -n "$label" ] || label="$(derive_label "$id")"
  label="$(json_escape "$label")"

  entry=$(cat <<EOF
    {
      "id": "$id",
      "label": "$label",
      "hasFajr": $has_fajr,
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

{
  echo "{"
  echo "  \"version\": 1,"
  echo "  \"adhans\": ["
  printf '%s\n' "$entries"
  echo "  ]"
  echo "}"
} > "$out"

echo "Wrote $out ($count adhan(s), $warnings warning(s))"
