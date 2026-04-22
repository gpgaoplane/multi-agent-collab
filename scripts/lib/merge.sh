#!/usr/bin/env bash
# Marker-guided merge helpers.
# Managed sections are wrapped by:
#   <!-- collab:<section>:start -->
#   ...managed content...
#   <!-- collab:<section>:end -->
# merge_replace_section atomically swaps the content between markers.

# merge_has_section <file> <section-name>
# Returns 0 if both markers exist, 1 otherwise.
merge_has_section() {
  local file="$1"
  local section="$2"
  local start_marker="<!-- collab:${section}:start -->"
  local end_marker="<!-- collab:${section}:end -->"
  grep -qF "$start_marker" "$file" 2>/dev/null && grep -qF "$end_marker" "$file" 2>/dev/null
}

# merge_replace_section <file> <section-name> <new-content>
# Replaces content between markers with new-content (verbatim, newlines preserved).
# Errors if either marker is missing.
merge_replace_section() {
  local file="$1"
  local section="$2"
  local new_content="$3"
  local start_marker="<!-- collab:${section}:start -->"
  local end_marker="<!-- collab:${section}:end -->"

  if ! merge_has_section "$file" "$section"; then
    echo "merge_replace_section: markers for section '$section' missing in $file" >&2
    return 1
  fi

  local tmp
  tmp=$(mktemp)

  awk -v start="$start_marker" -v end="$end_marker" -v body="$new_content" '
    {
      if ($0 == start) { print; print body; skipping = 1; next }
      if ($0 == end) { skipping = 0; print; next }
      if (!skipping) print
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}
