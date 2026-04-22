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

usage() {
  cat <<'EOF'
Usage: collab-init.sh [options]
  --agent <name>       Bootstrap only the named agent (repeatable)
  --add-agent <name>   Add a new agent descriptor and bootstrap only its files
  --dry-run            Print actions without writing
  --force              Overwrite non-marker content (destructive)
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) TARGET_AGENTS+=("$2"); shift 2 ;;
    --add-agent) ADD_AGENT="$2"; shift 2 ;;
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

setup_shared() {
  say "Setting up shared files"
  copy_file "$TEMPLATES/collab/VERSION" ".collab/VERSION"
  copy_file "$TEMPLATES/collab/ACTIVE.md" ".collab/ACTIVE.md"
  copy_file "$TEMPLATES/collab/INDEX.md" ".collab/INDEX.md"
  copy_file "$TEMPLATES/collab/ROUTING.md" ".collab/ROUTING.md"
  copy_file "$TEMPLATES/collab/PROTOCOL.md" ".collab/PROTOCOL.md"
  mkdir -p ".collab/agents.d" ".collab/archive"
  for yml in "$TEMPLATES/agents.d/"*.yml; do
    copy_file "$yml" ".collab/agents.d/$(basename "$yml")"
  done
  copy_file "$TEMPLATES/AI_AGENTS.md" "AI_AGENTS.md"
}

# --- Main dispatch ---

if [[ -f ".collab/VERSION" ]]; then
  echo "collab-init: .collab/VERSION exists — re-init/upgrade path not yet implemented in this task (see Task 16)."
  exit 1
fi

say "Mode: fresh"

setup_shared

# Decide which agents to bootstrap.
if [[ ${#TARGET_AGENTS[@]} -eq 0 && -z "$ADD_AGENT" ]]; then
  # Default: all descriptors.
  for yml in ".collab/agents.d/"*.yml; do
    bootstrap_agent "$yml"
  done
else
  for name in "${TARGET_AGENTS[@]}"; do
    bootstrap_agent ".collab/agents.d/${name}.yml"
  done
fi

# Register shared files.
if [[ $DRY_RUN -eq 0 ]]; then
  for f in AI_AGENTS.md .collab/ACTIVE.md .collab/INDEX.md .collab/ROUTING.md .collab/PROTOCOL.md; do
    bash "$HERE/collab-register.sh" "$f" || true
  done
fi

say "Done. Repo bootstrapped at version $(cat .collab/VERSION 2>/dev/null || echo '?')."
