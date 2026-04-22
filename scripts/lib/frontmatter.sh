#!/usr/bin/env bash
# YAML frontmatter helpers. Assumes simple key: value pairs, no nested structures.
# Lists are not required for the skill's managed fields (status, type, owner,
# last-updated, read-if, skip-if). `related: []` is written verbatim.

# fm_has_frontmatter <file>
# Returns 0 if the file starts with a YAML frontmatter block (--- on line 1).
fm_has_frontmatter() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  [[ "$(head -n 1 "$file")" == "---" ]]
}

# fm_get_field <file> <field>
# Echoes the value of a scalar field from the frontmatter block. Empty if absent.
fm_get_field() {
  local file="$1"
  local field="$2"
  fm_has_frontmatter "$file" || return 0
  awk -v field="$field" '
    BEGIN { in_fm = 0 }
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      # Match "field: value" allowing leading whitespace and value-trailing whitespace.
      if (match($0, "^[ \t]*" field "[ \t]*:[ \t]*")) {
        value = substr($0, RLENGTH + 1)
        # Trim trailing whitespace.
        sub(/[ \t]+$/, "", value)
        # Strip surrounding quotes if present.
        if (value ~ /^".*"$/) { value = substr(value, 2, length(value) - 2) }
        else if (value ~ /^'"'"'.*'"'"'$/) { value = substr(value, 2, length(value) - 2) }
        print value
        exit
      }
    }
  ' "$file"
}

# fm_set_field <file> <field> <value>
# Updates the field if present, appends before the closing --- if absent.
# Preserves body verbatim.
fm_set_field() {
  local file="$1"
  local field="$2"
  local value="$3"
  fm_has_frontmatter "$file" || {
    echo "fm_set_field: $file has no frontmatter" >&2
    return 1
  }

  local tmp
  tmp=$(mktemp)

  awk -v field="$field" -v value="$value" '
    BEGIN { in_fm = 0; replaced = 0 }
    NR == 1 && $0 == "---" { in_fm = 1; print; next }
    in_fm && $0 == "---" {
      if (!replaced) { print field ": " value; replaced = 1 }
      in_fm = 0
      print
      next
    }
    in_fm {
      if (match($0, "^[ \t]*" field "[ \t]*:")) {
        print field ": " value
        replaced = 1
        next
      }
    }
    { print }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}
