#!/usr/bin/env bash
# collab-init.sh — bootstrap the multi-agent-collab structure in the current repo.
# Modes: fresh (no .collab/), re-init (.collab/ exists, version matches),
#        upgrade (.collab/ exists, version older), legacy-merge (some files exist w/o markers).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(cd "$HERE/.." && pwd)"
TEMPLATES="$SKILL_ROOT/templates"

source "$HERE/lib/frontmatter.sh"
source "$HERE/lib/index.sh"
source "$HERE/lib/merge.sh"

DRY_RUN=0
FORCE=0
TARGET_AGENTS=()
ADD_AGENT=""
JOIN_AGENT=""

usage() {
  cat <<'EOF'
Usage: collab-init.sh [options]
  --agent <name>       Bootstrap only the named agent (repeatable)
  --add-agent <name>   Add a new agent; requires descriptor to already exist
  --join <name>        Add an agent by name. Three-tier lookup:
                         1. existing user descriptor at .collab/agents.d/<name>.yml
                         2. shipped descriptor in templates/agents.d/<name>.yml
                         3. generic template (auto-renders defaults)
  --dry-run            Print actions without writing
  --force              Overwrite non-marker content (destructive)
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) TARGET_AGENTS+=("$2"); shift 2 ;;
    --add-agent) ADD_AGENT="$2"; shift 2 ;;
    --join) JOIN_AGENT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

say() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    echo "$*"
  fi
}

copy_file() {
  local src="$1"
  local dest="$2"
  if [[ $DRY_RUN -eq 1 ]]; then
    say "copy $src -> $dest"
    return 0
  fi
  if [[ -f "$dest" && $FORCE -eq 0 ]]; then
    say "skip (exists): $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}

# substitute_tokens <src> <dest> <var=value> [...]
substitute_tokens() {
  local src="$1"; shift
  local dest="$1"; shift
  if [[ $DRY_RUN -eq 1 ]]; then
    say "render $src -> $dest"
    return 0
  fi
  if [[ -f "$dest" && $FORCE -eq 0 ]]; then
    say "skip (exists): $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  local content
  content=$(cat "$src")
  for pair in "$@"; do
    local key="${pair%%=*}"
    local val="${pair#*=}"
    content="${content//\{\{$key\}\}/$val}"
  done
  printf '%s' "$content" > "$dest"
}

# parse_descriptor <yml-file> — emits shell assignments for name/display/adapter/memory/log.
parse_descriptor() {
  local f="$1"
  awk '
    /^name:/        { sub(/^name:[ \t]*/, ""); print "DESC_NAME="$0 }
    /^display:/     { sub(/^display:[ \t]*/, ""); print "DESC_DISPLAY="$0 }
    /^adapter_path:/{ sub(/^adapter_path:[ \t]*/, ""); print "DESC_ADAPTER="$0 }
    /^memory_dir:/  { sub(/^memory_dir:[ \t]*/, ""); print "DESC_MEMORY="$0 }
    /^log_path:/    { sub(/^log_path:[ \t]*/, ""); print "DESC_LOG="$0 }
  ' "$f"
}

bootstrap_agent() {
  local descriptor="$1"
  eval "$(parse_descriptor "$descriptor")"

  say "Bootstrapping agent: $DESC_DISPLAY"

  local now
  now=$(bash "$HERE/collab-now.sh")

  substitute_tokens "$TEMPLATES/adapter/ADAPTER.md" "$DESC_ADAPTER" \
    "AGENT_NAME=$DESC_NAME" "AGENT_DISPLAY=$DESC_DISPLAY" \
    "MEMORY_DIR=$DESC_MEMORY" "WORK_LOG_PATH=$DESC_LOG"

  for f in state.md context.md decisions.md pitfalls.md; do
    substitute_tokens "$TEMPLATES/memory/$f" "$DESC_MEMORY/$f" \
      "AGENT_NAME=$DESC_NAME" "AGENT_DISPLAY=$DESC_DISPLAY"
  done

  substitute_tokens "$TEMPLATES/work-log-seed.md" "$DESC_LOG" \
    "AGENT_NAME=$DESC_NAME" "AGENT_DISPLAY=$DESC_DISPLAY" \
    "ONBOARD_DATE=${now%T*}" "ADAPTER_PATH=$DESC_ADAPTER"

  # Register all generated files in INDEX if INDEX exists (it does after setup).
  if [[ -f ".collab/INDEX.md" && $DRY_RUN -eq 0 ]]; then
    bash "$HERE/collab-register.sh" "$DESC_ADAPTER" || true
    bash "$HERE/collab-register.sh" "$DESC_LOG" || true
    for f in state.md context.md decisions.md pitfalls.md; do
      bash "$HERE/collab-register.sh" "$DESC_MEMORY/$f" || true
    done
  fi
}

inject_agents_md_section() {
  local target="AGENTS.md"
  local template="$TEMPLATES/AGENTS.md"

  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ -f "$target" ]]; then
      say "would refresh/append managed section in AGENTS.md"
    else
      say "would create AGENTS.md from template"
    fi
    return 0
  fi

  if [[ ! -f "$target" ]]; then
    cp "$template" "$target"
    return 0
  fi

  if merge_has_section "$target" "agents-md"; then
    local new_content
    new_content=$(awk -v start="<!-- collab:agents-md:start -->" -v end="<!-- collab:agents-md:end -->" '
      $0 == start { in_sec = 1; next }
      $0 == end { in_sec = 0; next }
      in_sec { print }
    ' "$template")
    merge_replace_section "$target" "agents-md" "$new_content"
  else
    {
      echo
      cat "$template"
    } >> "$target"
  fi
}

setup_shared() {
  say "Setting up shared files"
  copy_file "$TEMPLATES/collab/VERSION" ".collab/VERSION"
  copy_file "$TEMPLATES/collab/ACTIVE.md" ".collab/ACTIVE.md"
  copy_file "$TEMPLATES/collab/INDEX.md" ".collab/INDEX.md"
  copy_file "$TEMPLATES/collab/ROUTING.md" ".collab/ROUTING.md"
  copy_file "$TEMPLATES/collab/PROTOCOL.md" ".collab/PROTOCOL.md"
  mkdir -p ".collab/agents.d" ".collab/archive"
  for yml in "$TEMPLATES/agents.d/"*.yml; do
    # Skip internal templates (underscore-prefixed) — not real shipped descriptors.
    [[ "$(basename "$yml")" == _* ]] && continue
    copy_file "$yml" ".collab/agents.d/$(basename "$yml")"
  done
  copy_file "$TEMPLATES/AI_AGENTS.md" "AI_AGENTS.md"
  inject_agents_md_section
}

join_agent() {
  local name="$1"
  local upper
  upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')
  local display="$(echo "${name:0:1}" | tr '[:lower:]' '[:upper:]')${name:1}"

  local shipped="$TEMPLATES/agents.d/${name}.yml"
  local user=".collab/agents.d/${name}.yml"
  local generic="$TEMPLATES/agents.d/_generic.yml"

  if [[ -f "$user" ]]; then
    say "join: using existing descriptor at $user"
  elif [[ -f "$shipped" ]]; then
    say "join: installing shipped descriptor for $name"
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p ".collab/agents.d"
      cp "$shipped" "$user"
    fi
  else
    say "join: rendering generic descriptor for unknown agent $name"
    if [[ ! -f "$generic" ]]; then
      echo "join: generic template missing at $generic" >&2
      return 1
    fi
    if [[ $DRY_RUN -eq 0 ]]; then
      mkdir -p ".collab/agents.d"
      local content
      content=$(cat "$generic")
      content="${content//\{\{AGENT_NAME\}\}/$name}"
      content="${content//\{\{AGENT_DISPLAY\}\}/$display}"
      content="${content//\{\{AGENT_UPPER\}\}/$upper}"
      printf '%s\n' "$content" > "$user"
    fi
  fi

  bootstrap_agent "$user"
}

validate_descriptor_exists() {
  local name="$1"
  local path=".collab/agents.d/${name}.yml"
  if [[ ! -f "$path" ]]; then
    cat >&2 <<EOF
collab-init: descriptor for agent "$name" not found at $path

To add a new agent, first create the descriptor:
  cp templates/agents.d/claude.yml .collab/agents.d/$name.yml
  # then edit to set name/display/adapter_path/memory_dir/log_path

Then re-run:
  ./scripts/collab-init.sh --add-agent $name
EOF
    return 1
  fi
}

# --- Main dispatch ---

detect_mode() {
  if [[ ! -f ".collab/VERSION" ]]; then
    echo "fresh"
    return
  fi
  local installed="$(cat .collab/VERSION)"
  local shipped="$(cat "$TEMPLATES/collab/VERSION")"
  if [[ "$installed" == "$shipped" ]]; then
    echo "re-init"
  else
    echo "upgrade"
  fi
}

re_init_shared() {
  say "Re-initializing shared files (idempotent, markers-only)"
  # Re-emit files that don't exist. For files that do, use merge to refresh
  # marker sections only.
  [[ -f .collab/VERSION ]] || copy_file "$TEMPLATES/collab/VERSION" ".collab/VERSION"
  [[ -f .collab/ACTIVE.md ]] || copy_file "$TEMPLATES/collab/ACTIVE.md" ".collab/ACTIVE.md"
  [[ -f .collab/INDEX.md ]] || copy_file "$TEMPLATES/collab/INDEX.md" ".collab/INDEX.md"
  [[ -f .collab/ROUTING.md ]] || copy_file "$TEMPLATES/collab/ROUTING.md" ".collab/ROUTING.md"
  [[ -f .collab/PROTOCOL.md ]] || copy_file "$TEMPLATES/collab/PROTOCOL.md" ".collab/PROTOCOL.md"

  # For AI_AGENTS.md, refresh managed sections only.
  if [[ -f AI_AGENTS.md ]]; then
    refresh_managed_sections "AI_AGENTS.md" "$TEMPLATES/AI_AGENTS.md"
  else
    copy_file "$TEMPLATES/AI_AGENTS.md" "AI_AGENTS.md"
  fi

  # AGENTS.md — always ensure managed section present/current.
  inject_agents_md_section

  # Sync descriptors (additive only — never remove user customizations).
  mkdir -p .collab/agents.d .collab/archive
  for yml in "$TEMPLATES/agents.d/"*.yml; do
    local name=$(basename "$yml")
    [[ "$name" == _* ]] && continue
    [[ -f ".collab/agents.d/$name" ]] || copy_file "$yml" ".collab/agents.d/$name"
  done
}

# refresh_managed_sections <target> <template>
# For every <!-- collab:NAME:start/end --> section in target, replace content
# with the content from template's same-named section.
refresh_managed_sections() {
  local target="$1"
  local template="$2"

  # Extract section names from template.
  local sections
  sections=$(grep -oE '<!-- collab:[a-z-]+:start -->' "$template" | sed -E 's/<!-- collab:([a-z-]+):start -->/\1/' | sort -u)

  for section in $sections; do
    if merge_has_section "$target" "$section" && merge_has_section "$template" "$section"; then
      # Extract template content between markers (exclusive).
      local new_content
      new_content=$(awk -v start="<!-- collab:${section}:start -->" -v end="<!-- collab:${section}:end -->" '
        $0 == start { in_sec = 1; next }
        $0 == end { in_sec = 0; next }
        in_sec { print }
      ' "$template")
      if [[ $DRY_RUN -eq 1 ]]; then
        say "would refresh section $section in $target"
      else
        merge_replace_section "$target" "$section" "$new_content"
      fi
    fi
  done
}

MODE=$(detect_mode)
say "Mode: $MODE"

case "$MODE" in
  fresh)
    setup_shared
    ;;
  re-init)
    re_init_shared
    ;;
  upgrade)
    installed=$(cat .collab/VERSION)
    shipped=$(cat "$TEMPLATES/collab/VERSION")
    say "Upgrading from $installed to $shipped"
    # v0.1.0 has no prior version, so no migration script. Future upgrades
    # will invoke scripts/migrations/<from>-to-<to>.sh if present.
    migration="$HERE/migrations/${installed}-to-${shipped}.sh"
    if [[ -f "$migration" ]]; then
      say "Running migration: $migration"
      [[ $DRY_RUN -eq 1 ]] || bash "$migration"
    fi
    # After migration, run re-init to pick up any new template content.
    re_init_shared
    [[ $DRY_RUN -eq 1 ]] || echo "$shipped" > .collab/VERSION
    ;;
esac

# Agent selection.
if [[ -n "$JOIN_AGENT" ]]; then
  join_agent "$JOIN_AGENT"
elif [[ -n "$ADD_AGENT" ]]; then
  validate_descriptor_exists "$ADD_AGENT"
  bootstrap_agent ".collab/agents.d/${ADD_AGENT}.yml"
elif [[ ${#TARGET_AGENTS[@]} -eq 0 ]]; then
  for yml in ".collab/agents.d/"*.yml; do
    [[ -f "$yml" ]] || continue
    # Skip internal underscore-prefixed templates if any leaked in.
    [[ "$(basename "$yml")" == _* ]] && continue
    bootstrap_agent "$yml"
  done
else
  for name in "${TARGET_AGENTS[@]}"; do
    bootstrap_agent ".collab/agents.d/${name}.yml"
  done
fi

if [[ $DRY_RUN -eq 0 ]]; then
  # AGENTS.md has no YAML frontmatter (standard format), so collab-register will soft-fail; that's OK.
  for f in AI_AGENTS.md AGENTS.md .collab/ACTIVE.md .collab/INDEX.md .collab/ROUTING.md .collab/PROTOCOL.md; do
    [[ -f "$f" ]] && bash "$HERE/collab-register.sh" "$f" 2>/dev/null || true
  done
fi

say "Done. Repo at collab version $(cat .collab/VERSION 2>/dev/null || echo '?')."
