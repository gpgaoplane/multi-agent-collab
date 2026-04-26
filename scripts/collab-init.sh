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
INSTALL_HOOKS=0
ACK_UPGRADE=0
RESOLVED_AGENTS=()

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
  --install-hooks      Install collab pre-commit hook at .git/hooks/pre-commit
  --ack-upgrade        Archive .collab/UPGRADE_NOTES.md (run after reading post-upgrade ritual)
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
    --install-hooks) INSTALL_HOOKS=1; shift ;;
    --ack-upgrade) ACK_UPGRADE=1; shift ;;
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

# Detect the calling agent via env-var probe. Returns name on stdout; empty if
# nothing matches. Probe order is fixed (claude, codex, gemini) — first hit wins.
# Env-var detection is best-effort across CLI versions; fallback is --agent or
# $COLLAB_AGENT, both checked by resolve_calling_agents() before this function.
detect_calling_agent() {
  if [[ -n "${CLAUDECODE:-}" || -n "${CLAUDE_CODE_SSE_PORT:-}" || -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
    echo "claude"
    return 0
  fi
  if [[ -n "${CODEX_HOME:-}" || -n "${CODEX_CLI:-}" ]]; then
    echo "codex"
    return 0
  fi
  if [[ -n "${GEMINI_CLI:-}" || -n "${GEMINI_API_KEY:-}" || -n "${GOOGLE_AI_API_KEY:-}" ]]; then
    echo "gemini"
    return 0
  fi
  return 0
}

# Resolve which agents to bootstrap on `init` (fresh mode). Precedence:
#   1. --agent <name> flag (one or more)
#   2. $COLLAB_AGENT env var
#   3. detect_calling_agent env probe
#   4. hard-fail with guidance
# Re-init / upgrade modes skip resolution and iterate existing descriptors.
resolve_calling_agents() {
  if [[ ${#TARGET_AGENTS[@]} -gt 0 ]]; then
    RESOLVED_AGENTS=("${TARGET_AGENTS[@]}")
    return 0
  fi
  if [[ -n "${COLLAB_AGENT:-}" ]]; then
    RESOLVED_AGENTS=("$COLLAB_AGENT")
    return 0
  fi
  local detected
  detected=$(detect_calling_agent)
  if [[ -n "$detected" ]]; then
    RESOLVED_AGENTS=("$detected")
    return 0
  fi
  cat >&2 <<'EOF'
collab-init: cannot detect calling agent on fresh install.

Re-run with one of:
  bash scripts/collab-init.sh --agent claude        # or codex / gemini / <name>
  COLLAB_AGENT=claude bash scripts/collab-init.sh

Detection probed (none set): CLAUDECODE, CLAUDE_CODE_SSE_PORT,
  CLAUDE_CODE_OAUTH_TOKEN, CODEX_HOME, CODEX_CLI, GEMINI_CLI,
  GEMINI_API_KEY, GOOGLE_AI_API_KEY.

Add agents later with:
  bash scripts/collab-init.sh --join <name>
EOF
  exit 1
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

# Render <!-- collab:current-adapters --> from the live descriptor set so the
# "Current Adapters" table in AI_AGENTS.md always reflects the agents that are
# actually installed in this repo. Called after any change to .collab/agents.d/.
render_adapters_table() {
  local target="${1:-AI_AGENTS.md}"
  [[ -f "$target" ]] || return 0
  if ! merge_has_section "$target" "current-adapters"; then
    return 0
  fi

  local body
  body=$'\n<!-- WARNING: framework-managed; edit OUTSIDE this block, not inside -->\n## Current Adapters\n\n| Agent | Config file | Memory dir | Work log |\n|-------|-------------|------------|----------|'

  for yml in .collab/agents.d/*.yml; do
    [[ -f "$yml" ]] || continue
    [[ "$(basename "$yml")" == _* ]] && continue
    local DESC_NAME="" DESC_DISPLAY="" DESC_ADAPTER="" DESC_MEMORY="" DESC_LOG=""
    eval "$(parse_descriptor "$yml")"
    local adapter_display
    if [[ "$DESC_ADAPTER" == */* ]]; then
      adapter_display="\`$DESC_ADAPTER\`"
    else
      adapter_display="\`$DESC_ADAPTER\` (root)"
    fi
    body+=$'\n'"| $DESC_DISPLAY | $adapter_display | \`$DESC_MEMORY/\` | \`$DESC_LOG\` |"
  done

  if [[ $DRY_RUN -eq 0 ]]; then
    merge_replace_section "$target" "current-adapters" "$body"
  fi
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

  # If the legacy single-section file pre-dates a section that's now in the
  # template, append the missing section. For sections present in both, refresh.
  local sections
  sections=$(grep -oE '<!-- collab:[a-z-]+:start -->' "$template" | sed -E 's/<!-- collab:([a-z-]+):start -->/\1/' | sort -u)

  for section in $sections; do
    local new_content
    new_content=$(awk -v start="<!-- collab:${section}:start -->" -v end="<!-- collab:${section}:end -->" '
      $0 == start { in_sec = 1; next }
      $0 == end { in_sec = 0; next }
      in_sec { print }
    ' "$template")
    if merge_has_section "$target" "$section"; then
      merge_replace_section "$target" "$section" "$new_content"
    else
      # Append the section verbatim from template (start marker + body + end marker).
      {
        echo
        echo "<!-- collab:${section}:start -->"
        printf '%s\n' "$new_content"
        echo "<!-- collab:${section}:end -->"
      } >> "$target"
    fi
  done
}

install_pre_commit_hook() {
  local src="$SKILL_ROOT/scripts/hooks/pre-commit"
  local dest=".git/hooks/pre-commit"

  if [[ ! -d .git/hooks ]]; then
    say "install-hooks: no .git/hooks dir (is this a git repo?)" >&2
    return 0
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    say "would install $src -> $dest"
    return 0
  fi

  # Preserve existing hook if the installed one is not already ours.
  # Detection uses the `# collab:managed-hook` sentinel — substring matches on
  # script paths are unreliable (can collide with user scripts that mention
  # collab-verify-receipt for any reason).
  if [[ -f "$dest" ]] && ! grep -q "^# collab:managed-hook" "$dest"; then
    mv "$dest" ".git/hooks/pre-commit.local"
    say "preserved existing pre-commit as .git/hooks/pre-commit.local"
  fi

  cp "$src" "$dest"
  chmod +x "$dest"
  # If a .local exists, append a single delegation block so it still runs.
  # The block is marked with `# collab:delegation` so test suites can count
  # occurrences (exactly one expected after any number of re-runs).
  if [[ -f .git/hooks/pre-commit.local ]]; then
    cat >> "$dest" <<'EOF'

# collab:delegation — invoke user's pre-existing hook, if any.
if [[ -x .git/hooks/pre-commit.local ]]; then
  .git/hooks/pre-commit.local "$@" || exit $?
fi
EOF
  fi
  say "installed collab pre-commit hook at $dest"
}

install_config() {
  local src="$TEMPLATES/config.yml"
  local dest=".collab/config.yml"
  [[ -f "$dest" ]] && return 0
  if [[ $DRY_RUN -eq 0 ]]; then
    cp "$src" "$dest"
  fi
  say "installed default config at $dest"
}

setup_shared() {
  say "Setting up shared files"
  copy_file "$TEMPLATES/collab/VERSION" ".collab/VERSION"
  copy_file "$TEMPLATES/collab/ACTIVE.md" ".collab/ACTIVE.md"
  copy_file "$TEMPLATES/collab/INDEX.md" ".collab/INDEX.md"
  copy_file "$TEMPLATES/collab/ROUTING.md" ".collab/ROUTING.md"
  copy_file "$TEMPLATES/collab/PROTOCOL.md" ".collab/PROTOCOL.md"
  mkdir -p ".collab/agents.d" ".collab/archive"
  # Per-agent descriptor seeding happens via join_agent() during dispatch — this
  # keeps fresh `init` to a single calling agent instead of pre-seeding all
  # shipped descriptors. Add others later with --join <name>.
  copy_file "$TEMPLATES/AI_AGENTS.md" "AI_AGENTS.md"
  inject_agents_md_section
  install_config
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

  # Descriptors are NOT auto-seeded on re-init. The calling-agent-only invariant
  # established at fresh install is preserved; users add agents via --join.
  mkdir -p .collab/agents.d .collab/archive

  install_config
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

# --ack-upgrade: archive the transient UPGRADE_NOTES.md and exit. Idempotent —
# if the file is already absent or already archived, this is a no-op.
if [[ $ACK_UPGRADE -eq 1 ]]; then
  if [[ -f .collab/UPGRADE_NOTES.md ]]; then
    mkdir -p .collab/archive
    archived=".collab/archive/UPGRADE_NOTES-$(date +%Y%m%d).md"
    if [[ -f "$archived" ]]; then
      # Concurrent ack from a sibling session — file was already archived.
      rm -f .collab/UPGRADE_NOTES.md
      echo "ack-upgrade: UPGRADE_NOTES.md already archived; removed live copy."
    else
      mv .collab/UPGRADE_NOTES.md "$archived"
      echo "ack-upgrade: archived UPGRADE_NOTES.md to $archived."
    fi
  else
    echo "ack-upgrade: no UPGRADE_NOTES.md present; nothing to do."
  fi
  exit 0
fi

MODE=$(detect_mode)
say "Mode: $MODE"

# Validate flag combinations. --join / --add-agent require an existing install;
# --agent acts as the calling-agent override on fresh installs.
if [[ "$MODE" == "fresh" ]]; then
  if [[ -n "$JOIN_AGENT" ]]; then
    echo "collab-init: --join is not valid on a fresh install. Use --agent <name> to set the calling agent." >&2
    exit 1
  fi
  if [[ -n "$ADD_AGENT" ]]; then
    echo "collab-init: --add-agent is not valid on a fresh install. Use --agent <name> to set the calling agent." >&2
    exit 1
  fi
fi

case "$MODE" in
  fresh)
    resolve_calling_agents   # populates RESOLVED_AGENTS or hard-fails
    setup_shared
    for name in "${RESOLVED_AGENTS[@]}"; do
      join_agent "$name"
    done
    ;;
  re-init)
    re_init_shared
    if [[ -z "$JOIN_AGENT" && -z "$ADD_AGENT" ]]; then
      if [[ ${#TARGET_AGENTS[@]} -eq 0 ]]; then
        for yml in ".collab/agents.d/"*.yml; do
          [[ -f "$yml" ]] || continue
          [[ "$(basename "$yml")" == _* ]] && continue
          bootstrap_agent "$yml"
        done
      else
        for name in "${TARGET_AGENTS[@]}"; do
          bootstrap_agent ".collab/agents.d/${name}.yml"
        done
      fi
    fi
    ;;
  upgrade)
    installed=$(cat .collab/VERSION)
    shipped=$(cat "$TEMPLATES/collab/VERSION")
    say "Upgrading from $installed to $shipped"

    # Capture migration output for UPGRADE_NOTES.md while still streaming to
    # stdout. The notes file becomes a transient artifact the next agent reads
    # to learn what changed.
    upgrade_log=""
    if [[ $DRY_RUN -eq 0 ]]; then
      upgrade_log=$(mktemp)
    fi

    # Chain migrations by walking shipped migration scripts. Filename order
    # works because versions are zero-padded semver-like (0.1.0, 0.2.0, 0.3.0).
    from_version="$installed"
    for script in "$HERE/migrations/"*-to-*.sh; do
      [[ -f "$script" ]] || continue
      base=$(basename "$script" .sh)            # e.g. 0.1.0-to-0.2.0
      src="${base%-to-*}"                       # 0.1.0
      dst="${base##*-to-}"                      # 0.2.0
      # Run only forward-chain migrations starting at our current from_version
      # and not exceeding shipped.
      if [[ "$src" == "$from_version" && ! "$dst" > "$shipped" ]]; then
        say "Running migration: $(basename "$script")"
        if [[ $DRY_RUN -eq 1 ]]; then
          :
        elif [[ -n "$upgrade_log" ]]; then
          bash "$script" 2>&1 | tee -a "$upgrade_log"
        else
          bash "$script"
        fi
        from_version="$dst"
      fi
    done
    if [[ "$from_version" != "$shipped" ]]; then
      say "warning: no migration path from $installed to $shipped; applying re-init only"
    fi

    re_init_shared
    [[ $DRY_RUN -eq 1 ]] || echo "$shipped" > .collab/VERSION

    # Write UPGRADE_NOTES.md so the first agent to enter the next session sees
    # what changed. Marked status: transient — agents read it, run the
    # post-upgrade ritual (re-read AI_AGENTS.md), then ack via --ack-upgrade.
    if [[ $DRY_RUN -eq 0 && -n "$upgrade_log" && -s "$upgrade_log" ]]; then
      now=$(bash "$HERE/collab-now.sh")
      {
        printf -- '---\n'
        printf 'status: transient\n'
        printf 'type: upgrade-notes\n'
        printf 'owner: shared\n'
        printf 'last-updated: %s\n' "$now"
        printf 'read-if: "you are starting a session and have not yet acked this upgrade"\n'
        printf 'skip-if: "you already ran collab-init --ack-upgrade after reading this"\n'
        printf -- '---\n\n'
        printf '# Upgrade Notes — %s → %s\n\n' "$installed" "$shipped"
        printf 'Run on %s.\n\n' "$now"
        printf '## What changed\n\n'
        # Strip ANSI escapes if any leaked in; preserve summary lines verbatim.
        cat "$upgrade_log"
        printf '\n## Post-upgrade ritual\n\n'
        printf 'Before your next substantive write:\n\n'
        printf '1. Re-read `AI_AGENTS.md` `behavioral-rules` (rules may have changed).\n'
        printf '2. Skim the `>>> Upgrade summary:` blocks above for breaking changes.\n'
        printf '3. Read `CHANGELOG.md` if a summary references it.\n'
        printf '4. Once done, ack: `bash scripts/collab-init.sh --ack-upgrade`\n'
        printf '   (this archives this file so other agents do not re-process it).\n'
      } > .collab/UPGRADE_NOTES.md
      rm -f "$upgrade_log"
      bash "$HERE/collab-register.sh" .collab/UPGRADE_NOTES.md >/dev/null 2>&1 || true
      say "wrote .collab/UPGRADE_NOTES.md (run --ack-upgrade after reading)"
    fi
    if [[ -z "$JOIN_AGENT" && -z "$ADD_AGENT" ]]; then
      if [[ ${#TARGET_AGENTS[@]} -eq 0 ]]; then
        for yml in ".collab/agents.d/"*.yml; do
          [[ -f "$yml" ]] || continue
          [[ "$(basename "$yml")" == _* ]] && continue
          bootstrap_agent "$yml"
        done
      else
        for name in "${TARGET_AGENTS[@]}"; do
          bootstrap_agent ".collab/agents.d/${name}.yml"
        done
      fi
    fi
    ;;
esac

# --join / --add-agent for re-init / upgrade modes.
if [[ -n "$JOIN_AGENT" ]]; then
  join_agent "$JOIN_AGENT"
fi
if [[ -n "$ADD_AGENT" ]]; then
  validate_descriptor_exists "$ADD_AGENT"
  bootstrap_agent ".collab/agents.d/${ADD_AGENT}.yml"
fi

if [[ $DRY_RUN -eq 0 ]]; then
  # AGENTS.md has no YAML frontmatter (standard format), so collab-register will soft-fail; that's OK.
  for f in AI_AGENTS.md AGENTS.md .collab/ACTIVE.md .collab/INDEX.md .collab/ROUTING.md .collab/PROTOCOL.md; do
    [[ -f "$f" ]] && bash "$HERE/collab-register.sh" "$f" 2>/dev/null || true
  done
  render_adapters_table "AI_AGENTS.md"
fi

if [[ $INSTALL_HOOKS -eq 1 ]]; then
  install_pre_commit_hook
fi

say "Done. Repo at collab version $(cat .collab/VERSION 2>/dev/null || echo '?')."
