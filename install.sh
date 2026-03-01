#!/usr/bin/env bash
# =============================================================================
# AI Team Config Installer
# =============================================================================
#
# Interactive installer that sets up a project with:
#   1. Team selection (frontend, backend, qa, etc.)
#   2. Sub-team role selection (e.g., frontend-dev, frontend-qa)
#   3. Platform setup (claude, codex, or both)
#   4. Memory vault scaffolding
#   5. Dev communication scaffolding (if not already present)
#
# Usage:
#   ./ai_team_config/install.sh                    # Interactive mode
#   ./ai_team_config/install.sh --team frontend    # Skip team prompt
#   ./ai_team_config/install.sh --team frontend --role frontend-dev --platform claude
#   ./ai_team_config/install.sh --team frontend --role frontend-dev --platform both --devcomm create
#   ./ai_team_config/install.sh --team frontend --role frontend-dev --platform both --refresh-threshold 5
#   ./ai_team_config/install.sh --team frontend --role frontend-dev --platform both --force-refresh-links
#   ./ai_team_config/install.sh --non-interactive   # Skip project.yaml prompts (just copy scaffold)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILES_FILE="${SCRIPT_DIR}/teams/profiles.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
TEAM_ID=""
ROLE_ID=""
PLATFORM=""
DEVCOMM_MODE="create"
DEVCOMM_LINK_TARGET=""
REFRESH_THRESHOLD=5
FORCE_REFRESH_LINKS=0
NON_INTERACTIVE=0
RUN_ID="$(date +%Y%m%d-%H%M%S)"

while [[ $# -gt 0 ]]; do
  case $1 in
    --team) TEAM_ID="$2"; shift 2 ;;
    --role) ROLE_ID="$2"; shift 2 ;;
    --platform) PLATFORM="$2"; shift 2 ;;
    --devcomm) DEVCOMM_MODE="$2"; shift 2 ;;
    --refresh-threshold) REFRESH_THRESHOLD="$2"; shift 2 ;;
    --force-refresh-links) FORCE_REFRESH_LINKS=1; shift 1 ;;
    --non-interactive) NON_INTERACTIVE=1; shift 1 ;;
    --help|-h)
      echo "Usage: $0 [--team TEAM] [--role ROLE] [--platform claude|codex|both] [--devcomm create|skip|symlink:/abs/path] [--refresh-threshold N] [--force-refresh-links] [--non-interactive]"
      echo ""
      echo "  --force-refresh-links   Refresh symlinks AND regenerate platform docs (CLAUDE.md, AGENTS.md)"
      echo "                          Existing files are backed up as .legacy-<timestamp>"
      echo "  --non-interactive       Skip interactive project.yaml prompts; just copy scaffold if missing"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

case "$DEVCOMM_MODE" in
  create|skip)
    ;;
  symlink:*)
    DEVCOMM_LINK_TARGET="${DEVCOMM_MODE#symlink:}"
    ;;
  *)
    echo -e "${RED}Invalid --devcomm mode: ${DEVCOMM_MODE}${NC}"
    echo "Use one of: create, skip, symlink:/absolute/path"
    exit 1
    ;;
esac

if ! [[ "$REFRESH_THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Invalid --refresh-threshold: ${REFRESH_THRESHOLD}${NC}"
  echo "Use a non-negative integer."
  exit 1
fi

safe_link() {
  local target="$1"
  local link_path="$2"
  local label="$3"
  local target_for_link="$target"

  if [[ "$target" = /* ]]; then
    target_for_link="$(python3 - "$target" "$(dirname "$link_path")" <<'PY'
import os
import sys

target = os.path.abspath(sys.argv[1])
base = os.path.realpath(sys.argv[2])
target = os.path.realpath(target)
print(os.path.relpath(target, base))
PY
)"
  fi

  if [ -L "$link_path" ]; then
    local current_target
    current_target="$(readlink "$link_path" || true)"
    if [ "$current_target" != "$target_for_link" ]; then
      ln -sf "$target_for_link" "$link_path"
      echo "  Updated symlink: ${label}"
    else
      echo "  Symlink already current: ${label}"
    fi
  elif [ -e "$link_path" ]; then
    if [ "$FORCE_REFRESH_LINKS" = "1" ]; then
      local backup_path="${link_path}.legacy-${RUN_ID}"
      mv "$link_path" "$backup_path"
      ln -s "$target_for_link" "$link_path"
      echo -e "  ${YELLOW}Refreshed link ${label}; backup: ${backup_path}${NC}"
    else
      echo -e "  ${YELLOW}Skipped symlink ${label}: regular file/directory exists.${NC}"
      return 1
    fi
  else
    ln -s "$target_for_link" "$link_path"
    echo "  Created symlink: ${label}"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Helper: check which project.yaml fields still have scaffold placeholders
# ---------------------------------------------------------------------------
check_project_yaml_status() {
  local yaml_file="$1"
  python3 - "$yaml_file" <<'CHECK_PY'
import re, sys

yaml_file = sys.argv[1]
SENTINEL_PATTERNS = [
    r'<!--\s*Fill in',
    r'No canonical spec documents configured\.',
]

# Minimal YAML parser (same logic as Step 6b renderer)
project_vars = {}
current_key = None
current_lines = []
with open(yaml_file) as f:
    for line in f:
        if line.strip().startswith('#') and current_key is None:
            continue
        match = re.match(r'^([a-z_]+):\s*(.*)', line)
        if match and not line[0].isspace():
            if current_key is not None:
                project_vars[current_key] = '\n'.join(current_lines).strip()
            current_key = match.group(1)
            value = match.group(2).strip()
            if value in ('|', '>'):
                current_lines = []
            elif value:
                project_vars[current_key] = value
                current_key = None
                current_lines = []
            else:
                current_lines = []
        elif current_key is not None:
            if line.startswith('  '):
                current_lines.append(line[2:].rstrip())
            elif line.strip() == '':
                current_lines.append('')
            else:
                project_vars[current_key] = '\n'.join(current_lines).strip()
                current_key = None
                current_lines = []
    if current_key is not None:
        project_vars[current_key] = '\n'.join(current_lines).strip()

required = ['project_description', 'spec_documents', 'quick_reference']
unfilled = []
for field in required:
    val = project_vars.get(field, '').strip()
    if not val:
        unfilled.append(field)
        continue
    for pat in SENTINEL_PATTERNS:
        if re.search(pat, val):
            unfilled.append(field)
            break

if unfilled:
    print('NEEDS_SETUP:' + ','.join(unfilled))
else:
    print('COMPLETE')
CHECK_PY
}

# ---------------------------------------------------------------------------
# Helper: detect whether interactive /dev/tty prompts are available
# ---------------------------------------------------------------------------
can_use_tty() {
  if [ ! -c /dev/tty ]; then
    return 1
  fi
  if ! { exec 9<>/dev/tty; } 2>/dev/null; then
    return 1
  fi
  exec 9>&-
  exec 9<&-
  return 0
}

# ---------------------------------------------------------------------------
# Helper: collect multiline markdown input for a field
# ---------------------------------------------------------------------------
collect_multiline() {
  local field_name="$1"
  local instructions="$2"
  local tmpfile
  tmpfile="$(mktemp /tmp/project-yaml-XXXXXX.md)"

  local editor="${VISUAL:-${EDITOR:-}}"
  if [ -n "$editor" ]; then
    echo -e "  ${YELLOW}${field_name}:${NC} ${instructions}" >&2
    : > "$tmpfile"

    "$editor" "$tmpfile" </dev/tty >/dev/tty 2>/dev/tty
    sed -e 's/[[:space:]]*$//' "$tmpfile"
  else
    echo -e "  ${YELLOW}No \$EDITOR set — entering line-by-line mode.${NC}" >&2
    echo -e "  ${YELLOW}Type your content. Enter __END__ on its own line to finish.${NC}" >&2
    local line
    local content=""
    while IFS= read -r line </dev/tty; do
      [ "$line" = "__END__" ] && break
      if [ -z "$content" ]; then
        content="$line"
      else
        content="${content}
${line}"
      fi
    done
    echo "$content"
  fi

  rm -f "$tmpfile"
}

# ---------------------------------------------------------------------------
# Helper: write project.yaml from env vars
# ---------------------------------------------------------------------------
write_project_yaml() {
  python3 - <<'WRITE_PY'
import os

out_path  = os.environ['_PY_OUT']
name      = os.environ.get('_PY_NAME', '')
desc      = os.environ.get('_PY_DESC', '')
specs     = os.environ.get('_PY_SPECS', '')
quick     = os.environ.get('_PY_QUICK', '')

def multiline_block(value):
    """Format a value as a YAML | multiline block with 2-space indent."""
    lines = value.split('\n')
    return '|\n' + '\n'.join('  ' + l for l in lines) + '\n'

with open(out_path, 'w') as f:
    f.write("# =============================================================================\n")
    f.write("# Project Configuration for Template Rendering\n")
    f.write("# =============================================================================\n\n")

    if name:
        f.write(f"project_name: {name}\n\n")

    f.write("project_description: " + multiline_block(desc))
    f.write("\nspec_documents: " + multiline_block(specs))
    f.write("\nquick_reference: " + multiline_block(quick))
WRITE_PY
}

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  AI Team Config Installer${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

# ---- Check prerequisites ----
if ! command -v python3 &>/dev/null; then
  echo -e "${RED}Error: python3 is required but not found.${NC}"
  exit 1
fi

if [ ! -f "$PROFILES_FILE" ]; then
  echo -e "${RED}Error: profiles.json not found at ${PROFILES_FILE}${NC}"
  exit 1
fi

# ---- Load available teams ----
AVAILABLE_TEAMS=$(python3 -c "
import json
with open('$PROFILES_FILE') as f:
    data = json.load(f)
for tid, team in data['teams'].items():
    print(f'{tid}|{team[\"name\"]}')
")

# ---- Step 1: Select team ----
if [ -z "$TEAM_ID" ]; then
  echo -e "${GREEN}Step 1: Select your team${NC}"
  echo ""
  i=1
  declare -a TEAM_IDS
  while IFS='|' read -r tid tname; do
    TEAM_IDS+=("$tid")
    echo "  ${i}) ${tname} (${tid})"
    ((i++))
  done <<< "$AVAILABLE_TEAMS"
  echo ""
  read -rp "Enter team number: " TEAM_NUM

  if [[ "$TEAM_NUM" -ge 1 && "$TEAM_NUM" -le "${#TEAM_IDS[@]}" ]]; then
    TEAM_ID="${TEAM_IDS[$((TEAM_NUM-1))]}"
  else
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
  fi
fi

echo -e "  Selected team: ${YELLOW}${TEAM_ID}${NC}"
echo ""

# ---- Load team profile ----
TEAM_JSON=$(python3 -c "
import json
with open('$PROFILES_FILE') as f:
    data = json.load(f)
team = data['teams'].get('$TEAM_ID')
if not team:
    print('NOT_FOUND')
else:
    print(json.dumps(team))
")

if [ "$TEAM_JSON" = "NOT_FOUND" ]; then
  echo -e "${RED}Team '$TEAM_ID' not found in profiles.json${NC}"
  exit 1
fi

# ---- Step 2: Select sub-team role ----
SUB_TEAMS=$(python3 -c "
import json
team = json.loads('$TEAM_JSON')
for sid, sub in team.get('sub_teams', {}).items():
    print(f'{sid}|{sub[\"name\"]}|{sub.get(\"function\", \"\")}')
")

if [ -z "$ROLE_ID" ]; then
  echo -e "${GREEN}Step 2: Select your sub-team role${NC}"
  echo "  (This defines what this agent controller window operates as)"
  echo ""
  i=1
  declare -a ROLE_IDS
  while IFS='|' read -r rid rname rfunc; do
    ROLE_IDS+=("$rid")
    echo "  ${i}) ${rname} (${rid}) — ${rfunc}"
    ((i++))
  done <<< "$SUB_TEAMS"
  echo ""
  read -rp "Enter role number: " ROLE_NUM

  if [[ "$ROLE_NUM" -ge 1 && "$ROLE_NUM" -le "${#ROLE_IDS[@]}" ]]; then
    ROLE_ID="${ROLE_IDS[$((ROLE_NUM-1))]}"
  else
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
  fi
fi

echo -e "  Selected role: ${YELLOW}${ROLE_ID}${NC}"
echo ""

# ---- Step 3: Select platform ----
if [ -z "$PLATFORM" ]; then
  echo -e "${GREEN}Step 3: Select platform${NC}"
  echo ""
  echo "  1) Claude Code"
  echo "  2) Codex"
  echo "  3) Both"
  echo ""
  read -rp "Enter platform number: " PLAT_NUM

  case $PLAT_NUM in
    1) PLATFORM="claude" ;;
    2) PLATFORM="codex" ;;
    3) PLATFORM="both" ;;
    *) echo -e "${RED}Invalid selection.${NC}"; exit 1 ;;
  esac
fi

echo -e "  Selected platform: ${YELLOW}${PLATFORM}${NC}"
echo ""

# ---- Step 4: Scaffold memory/ ----
echo -e "${GREEN}Step 4: Setting up memory vault...${NC}"

MEMORY_DIR="${PROJECT_ROOT}/memory"
if [ -d "$MEMORY_DIR" ]; then
  echo "  memory/ already exists, preserving existing content."
  # Ensure subdirectories exist
  for subdir in sessions context patterns entities templates team-configs prompts prompts/agents prompts/tasks prompts/workflows prompts/team-configs; do
    mkdir -p "${MEMORY_DIR}/${subdir}"
  done

  # Seed missing scaffold files without overwriting project-local memory data
  while IFS= read -r rel_file; do
    src_file="${SCRIPT_DIR}/scaffolds/memory/${rel_file}"
    dst_file="${MEMORY_DIR}/${rel_file}"
    if [ ! -f "$dst_file" ]; then
      mkdir -p "$(dirname "$dst_file")"
      cp "$src_file" "$dst_file"
      echo "  Seeded: memory/${rel_file}"
    fi
  done < <(cd "${SCRIPT_DIR}/scaffolds/memory" && find . -type f | sed 's|^\./||')
else
  echo "  Creating memory/ from scaffold..."
  cp -r "${SCRIPT_DIR}/scaffolds/memory" "$MEMORY_DIR"
fi
echo "  Done."
echo ""

# ---- Step 4b: Interactive project.yaml setup ----
PROJECT_YAML="${PROJECT_ROOT}/project.yaml"
PROJECT_YAML_SCAFFOLD="${SCRIPT_DIR}/scaffolds/project.yaml"

if [ "$NON_INTERACTIVE" = "0" ] && ! can_use_tty; then
  echo -e "  ${YELLOW}No interactive TTY detected; switching to --non-interactive mode for project.yaml setup.${NC}"
  NON_INTERACTIVE=1
fi

if [ "$NON_INTERACTIVE" = "1" ]; then
  # Non-interactive: just copy scaffold if missing (old behavior)
  if [ ! -f "$PROJECT_YAML" ]; then
    if [ -f "$PROJECT_YAML_SCAFFOLD" ]; then
      cp "$PROJECT_YAML_SCAFFOLD" "$PROJECT_YAML"
      echo -e "  ${YELLOW}Seeded project.yaml from scaffold (non-interactive) — edit it manually.${NC}"
    fi
  else
    echo "  project.yaml already exists."
  fi
else
  # Interactive mode
  if [ -f "$PROJECT_YAML" ]; then
    YAML_STATUS="$(check_project_yaml_status "$PROJECT_YAML")"
  else
    # Seed scaffold first so the checker and loader have something to parse
    if [ -f "$PROJECT_YAML_SCAFFOLD" ]; then
      cp "$PROJECT_YAML_SCAFFOLD" "$PROJECT_YAML"
    fi
    YAML_STATUS="NEEDS_SETUP:project_description,spec_documents,quick_reference"
  fi

  if [ "$YAML_STATUS" = "COMPLETE" ]; then
    echo "  project.yaml already configured — skipping interactive setup."
  else
    UNFILLED="${YAML_STATUS#NEEDS_SETUP:}"
    echo -e "${GREEN}Step 4b: Project configuration${NC}"
    echo ""
    echo "  The following fields need to be filled in: ${UNFILLED}"
    echo ""

    # Load existing values from project.yaml (base64-encoded for shell safety)
    # Initialize to empty so set -u doesn't crash if python fails
    _EXISTING_PROJECT_NAME=""
    _EXISTING_PROJECT_DESCRIPTION=""
    _EXISTING_SPEC_DOCUMENTS=""
    _EXISTING_QUICK_REFERENCE=""
    eval "$(python3 - "$PROJECT_YAML" <<'LOAD_PY'
import re, sys, base64

yaml_file = sys.argv[1]
project_vars = {}
current_key = None
current_lines = []
with open(yaml_file) as f:
    for line in f:
        if line.strip().startswith('#') and current_key is None:
            continue
        match = re.match(r'^([a-z_]+):\s*(.*)', line)
        if match and not line[0].isspace():
            if current_key is not None:
                project_vars[current_key] = '\n'.join(current_lines).strip()
            current_key = match.group(1)
            value = match.group(2).strip()
            if value in ('|', '>'):
                current_lines = []
            elif value:
                project_vars[current_key] = value
                current_key = None
                current_lines = []
            else:
                current_lines = []
        elif current_key is not None:
            if line.startswith('  '):
                current_lines.append(line[2:].rstrip())
            elif line.strip() == '':
                current_lines.append('')
            else:
                project_vars[current_key] = '\n'.join(current_lines).strip()
                current_key = None
                current_lines = []
    if current_key is not None:
        project_vars[current_key] = '\n'.join(current_lines).strip()

# Emit shell assignments with base64-encoded values
for key in ['project_name', 'project_description', 'spec_documents',
            'quick_reference']:
    val = project_vars.get(key, '')
    encoded = base64.b64encode(val.encode()).decode()
    print(f'_EXISTING_{key.upper()}="{encoded}"')
LOAD_PY
)"

    # Decode helper
    _decode_b64() { echo "$1" | base64 -d 2>/dev/null || echo ""; }

    DEFAULT_PROJECT_NAME="$(basename "$PROJECT_ROOT")"
    EXISTING_NAME="$(_decode_b64 "$_EXISTING_PROJECT_NAME")"

    # --- project_name (always prompt — simple single-line) ---
    if [ -n "$EXISTING_NAME" ]; then
      DEFAULT_PROJECT_NAME="$EXISTING_NAME"
    fi
    read -rp "  Project name [${DEFAULT_PROJECT_NAME}]: " INPUT_NAME </dev/tty
    FINAL_NAME="${INPUT_NAME:-$DEFAULT_PROJECT_NAME}"
    echo ""

    # --- Prompt only for unfilled fields ---
    needs_field() { echo ",$UNFILLED," | grep -q ",$1,"; }

    # project_description
    if needs_field "project_description"; then
      echo -e "  ${GREEN}Project description${NC} (one paragraph about your project):"
      FINAL_DESC="$(collect_multiline "Project Description" "Write a brief overview of your project.")"
      if [ -z "$FINAL_DESC" ]; then
        FINAL_DESC="$(_decode_b64 "$_EXISTING_PROJECT_DESCRIPTION")"
      fi
    else
      FINAL_DESC="$(_decode_b64 "$_EXISTING_PROJECT_DESCRIPTION")"
    fi
    echo ""

    # spec_documents
    if needs_field "spec_documents"; then
      echo -e "  ${GREEN}Spec documents${NC} (markdown table or list of blueprint docs):"
      FINAL_SPECS="$(collect_multiline "Spec Documents" "List your canonical spec/blueprint documents as markdown.")"
      if [ -z "$FINAL_SPECS" ]; then
        FINAL_SPECS="$(_decode_b64 "$_EXISTING_SPEC_DOCUMENTS")"
      fi
    else
      FINAL_SPECS="$(_decode_b64 "$_EXISTING_SPEC_DOCUMENTS")"
    fi
    echo ""

    # quick_reference
    if needs_field "quick_reference"; then
      DEFAULT_QUICK='```bash
npm run dev          # Start dev server
npm test             # Run all tests
npx tsc --noEmit     # Type check
```'
      echo -e "  ${GREEN}Quick reference commands:${NC}"
      echo "  Default:"
      echo "$DEFAULT_QUICK" | sed 's/^/    /'
      echo ""
      read -rp "  Keep defaults? [Y/n]: " KEEP_QUICK </dev/tty
      if [[ "$KEEP_QUICK" =~ ^[Nn] ]]; then
        FINAL_QUICK="$(collect_multiline "Quick Reference" "Enter your quick-reference commands as a markdown code block.")"
        if [ -z "$FINAL_QUICK" ]; then
          FINAL_QUICK="$DEFAULT_QUICK"
        fi
      else
        FINAL_QUICK="$DEFAULT_QUICK"
      fi
    else
      FINAL_QUICK="$(_decode_b64 "$_EXISTING_QUICK_REFERENCE")"
    fi
    echo ""

    # Write project.yaml
    export _PY_OUT="$PROJECT_YAML"
    export _PY_NAME="$FINAL_NAME"
    export _PY_DESC="$FINAL_DESC"
    export _PY_SPECS="$FINAL_SPECS"
    export _PY_QUICK="$FINAL_QUICK"
    write_project_yaml
    unset _PY_OUT _PY_NAME _PY_DESC _PY_SPECS _PY_QUICK

    echo -e "  ${GREEN}Wrote: project.yaml${NC}"
  fi
fi
echo ""

# ---- Step 5: Setup dev_communication/ ----
echo -e "${GREEN}Step 5: Setting up dev_communication/...${NC}"

DEVCOMM_DIR="${PROJECT_ROOT}/dev_communication"
DEVCOMM_SCAFFOLD="${SCRIPT_DIR}/scaffolds/dev_communication"
if [ -e "$DEVCOMM_DIR" ]; then
  echo "  dev_communication/ already exists ($(file -b "$DEVCOMM_DIR"))."
else
  echo -e "  ${YELLOW}dev_communication/ not found.${NC}"

  case "$DEVCOMM_MODE" in
    create)
      if [ -d "$DEVCOMM_SCAFFOLD" ]; then
        cp -r "$DEVCOMM_SCAFFOLD" "$DEVCOMM_DIR"
        echo "  Created from ai_team_config scaffold."
      else
        echo -e "  ${RED}Scaffold not found at ${DEVCOMM_SCAFFOLD}.${NC}"
        exit 1
      fi
      ;;
    symlink:*)
      if [ -d "$DEVCOMM_LINK_TARGET" ]; then
        ln -s "$DEVCOMM_LINK_TARGET" "$DEVCOMM_DIR"
        echo "  Symlinked to ${DEVCOMM_LINK_TARGET}."
      else
        echo -e "  ${RED}Symlink target not found: ${DEVCOMM_LINK_TARGET}${NC}"
        exit 1
      fi
      ;;
    skip)
      echo "  Skipped. Set up dev_communication/ before using /comms or /adr."
      ;;
  esac
fi
echo ""

# ---- Step 5a: ADR bootstrap ----
SHARED_DIR="${PROJECT_ROOT}/dev_communication/shared"
ADR_SCAFFOLD="${SCRIPT_DIR}/scaffolds/dev_communication/shared"

if [ -d "$SHARED_DIR" ]; then
  echo -e "${GREEN}Step 5a: Bootstrapping ADR directory structure...${NC}"

  # Always seed architecture scaffolds (idempotent — won't overwrite)
  for rel_file in \
    "architecture/index.md" \
    "architecture/decision-log.md" \
    "architecture/templates/adr-template.md"
  do
    src_file="${ADR_SCAFFOLD}/${rel_file}"
    dst_file="${SHARED_DIR}/${rel_file}"
    if [ -f "$src_file" ] && [ ! -f "$dst_file" ]; then
      mkdir -p "$(dirname "$dst_file")"
      cp "$src_file" "$dst_file"
      echo "  Seeded: dev_communication/shared/${rel_file}"
    fi
  done

  # Starter ADR — interactive prompt or skip in non-interactive
  STARTER_ADR_SRC="${ADR_SCAFFOLD}/architecture/decisions/ADR-001-INITIAL-ARCHITECTURE.md"
  STARTER_ADR_DST="${SHARED_DIR}/architecture/decisions/ADR-001-INITIAL-ARCHITECTURE.md"
  if [ -f "$STARTER_ADR_SRC" ] && [ ! -f "$STARTER_ADR_DST" ]; then
    if [ "$NON_INTERACTIVE" = "1" ]; then
      echo "  Skipped starter ADR (non-interactive)."
    else
      read -rp "  Seed a starter ADR (ADR-001-INITIAL-ARCHITECTURE)? [y/N]: " SEED_ADR </dev/tty
      if [[ "$SEED_ADR" =~ ^[Yy] ]]; then
        mkdir -p "$(dirname "$STARTER_ADR_DST")"
        cp "$STARTER_ADR_SRC" "$STARTER_ADR_DST"
        echo "  Seeded: dev_communication/shared/architecture/decisions/ADR-001-INITIAL-ARCHITECTURE.md"
      else
        echo "  Skipped starter ADR."
      fi
    fi
  fi

  # Feature development checklist — interactive prompt or auto-seed in non-interactive
  CHECKLIST_SRC="${ADR_SCAFFOLD}/guidance/FEATURE_DEVELOPMENT_CHECKLIST.md"
  CHECKLIST_DST="${SHARED_DIR}/guidance/FEATURE_DEVELOPMENT_CHECKLIST.md"
  if [ -f "$CHECKLIST_SRC" ] && [ ! -f "$CHECKLIST_DST" ]; then
    if [ "$NON_INTERACTIVE" = "1" ]; then
      mkdir -p "$(dirname "$CHECKLIST_DST")"
      cp "$CHECKLIST_SRC" "$CHECKLIST_DST"
      echo "  Seeded: dev_communication/shared/guidance/FEATURE_DEVELOPMENT_CHECKLIST.md"
    else
      read -rp "  Seed a feature development checklist? [Y/n]: " SEED_CHECKLIST </dev/tty
      if [[ "$SEED_CHECKLIST" =~ ^[Nn] ]]; then
        echo "  Skipped development checklist."
      else
        mkdir -p "$(dirname "$CHECKLIST_DST")"
        cp "$CHECKLIST_SRC" "$CHECKLIST_DST"
        echo "  Seeded: dev_communication/shared/guidance/FEATURE_DEVELOPMENT_CHECKLIST.md"
      fi
    fi
  fi

  echo "  Done."
  echo ""
fi

# ---- Step 6: Run platform setup ----
echo -e "${GREEN}Step 6: Installing platform skills...${NC}"

if [ "$PLATFORM" = "claude" ] || [ "$PLATFORM" = "both" ]; then
  echo ""
  echo "  --- Claude Code ---"
  FORCE_REFRESH_LINKS="$FORCE_REFRESH_LINKS" RUN_ID="$RUN_ID" bash "${SCRIPT_DIR}/platforms/claude/setup.sh" "$PROJECT_ROOT"
fi

if [ "$PLATFORM" = "codex" ] || [ "$PLATFORM" = "both" ]; then
  echo ""
  echo "  --- Codex ---"
  FORCE_REFRESH_LINKS="$FORCE_REFRESH_LINKS" RUN_ID="$RUN_ID" bash "${SCRIPT_DIR}/platforms/codex/setup.sh" "$PROJECT_ROOT" "$TEAM_ID" "$ROLE_ID"
fi
echo ""

# ---- Step 6b: Generate platform instruction files from templates ----
echo -e "${GREEN}Step 6b: Generating platform instruction files from templates...${NC}"

TEMPLATE_DIR="${SCRIPT_DIR}/templates"

render_template() {
  local template_file="$1"
  local output_file="$2"
  local file_label="$3"

  if [ ! -f "$template_file" ]; then
    echo -e "  ${YELLOW}No template found at ${template_file}${NC}"
    return 1
  fi

  if [ -f "$output_file" ] && [ "$FORCE_REFRESH_LINKS" != "1" ]; then
    echo "  ${file_label} already exists at project root."
    echo -e "  ${YELLOW}To regenerate, re-run with --force-refresh-links.${NC}"
    return 0
  fi

  if [ -f "$output_file" ] && [ "$FORCE_REFRESH_LINKS" = "1" ]; then
    local backup_path="${output_file}.legacy-${RUN_ID}"
    mv "$output_file" "$backup_path"
    echo -e "  ${YELLOW}Backed up existing ${file_label} to ${backup_path}${NC}"
  fi

  python3 - "$template_file" "$output_file" <<'RENDER_PY'
import json, os, sys, re

template_file = sys.argv[1]
output_file = sys.argv[2]

# Env vars passed from shell
team_json = os.environ.get('_RENDER_TEAM_JSON', '{}')
role_id = os.environ.get('_RENDER_ROLE_ID', '')
team_id = os.environ.get('_RENDER_TEAM_ID', '')
project_root = os.environ.get('_RENDER_PROJECT_ROOT', '.')
script_dir = os.environ.get('_RENDER_SCRIPT_DIR', '.')

team = json.loads(team_json)
sub = team.get('sub_teams', {}).get(role_id, {})
function = sub.get('function', 'dev')
project_name = os.path.basename(os.path.abspath(project_root))

# --- Read project.yaml for project-specific content ---
project_yaml_path = os.path.join(project_root, 'project.yaml')
project_vars = {}
SENTINEL_PATTERNS = [
    r'<!--\s*Fill in',
    r'No canonical spec documents configured\.',
]

def is_scaffold_value(value: str) -> bool:
    val = (value or '').strip()
    if not val:
        return True
    return any(re.search(pat, val) for pat in SENTINEL_PATTERNS)

def render_project_field(key: str) -> str:
    value = (project_vars.get(key) or '').strip()
    if is_scaffold_value(value):
        return f'<!-- TODO: Fill in {key.upper()} for your project -->'
    return value

if os.path.isfile(project_yaml_path):
    # Minimal YAML parser for simple key: | multiline blocks
    current_key = None
    current_lines = []
    with open(project_yaml_path) as f:
        for line in f:
            # Skip comments
            if line.strip().startswith('#') and current_key is None:
                continue
            # New top-level key
            match = re.match(r'^([a-z_]+):\s*(.*)', line)
            if match and not line[0].isspace():
                # Save previous key
                if current_key is not None:
                    project_vars[current_key] = '\n'.join(current_lines).strip()
                current_key = match.group(1)
                value = match.group(2).strip()
                if value == '|' or value == '>':
                    current_lines = []
                elif value:
                    project_vars[current_key] = value
                    current_key = None
                    current_lines = []
                else:
                    current_lines = []
            elif current_key is not None:
                # Continuation of multiline block — strip exactly 2 leading spaces
                if line.startswith('  '):
                    current_lines.append(line[2:].rstrip())
                elif line.strip() == '':
                    current_lines.append('')
                else:
                    # End of block
                    project_vars[current_key] = '\n'.join(current_lines).strip()
                    current_key = None
                    current_lines = []
        # Flush last key
        if current_key is not None:
            project_vars[current_key] = '\n'.join(current_lines).strip()

# Override project_name from yaml if provided
if project_vars.get('project_name'):
    project_name = project_vars['project_name']

# --- Read role yaml dev_gate ---
role_file = os.path.join(script_dir, 'roles', f'{role_id}.yaml')
gate_checks = []
if os.path.isfile(role_file):
    in_gate = False
    with open(role_file) as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith('dev_gate:') or stripped.startswith('qa_gate:'):
                in_gate = True
                continue
            if in_gate:
                if stripped.startswith('- '):
                    item = stripped[2:].strip().strip('"').strip("'")
                    gate_checks.append(f'- [ ] {item}')
                elif stripped and not stripped.startswith('#'):
                    break

if not gate_checks:
    gate_checks = [
        '- [ ] Typecheck passes (0 errors)',
        '- [ ] All tests pass',
        '- [ ] New functionality has corresponding tests',
        '- [ ] Session file created',
        '- [ ] Resolution notes appended to issue file',
    ]

# --- Build file paths ---
file_paths = f"""- **Procedures:** `ai_team_config/procedures/` — universal dev/QA lifecycle docs
- **Dev communication:** `dev_communication/` — issues, messaging, architecture, coordination
- **Memory vault:** `memory/` — patterns, entities, context, sessions
- **Team inbox:** `dev_communication/{team_id}/inbox/`
- **Team config:** `team.json`
- **Role definitions:** `ai_team_config/roles/`"""

# --- Read template ---
with open(template_file) as f:
    content = f.read()

# --- Replace all placeholders ---
replacements = {
    '{{PROJECT_NAME}}': project_name,
    '{{COMPLETION_GATE_CHECKS}}': '\n'.join(gate_checks),
    '{{FILE_PATHS}}': file_paths,
    '{{PROJECT_DESCRIPTION}}': render_project_field('project_description'),
    '{{SPEC_DOCUMENTS}}': render_project_field('spec_documents'),
    '{{QUICK_REFERENCE}}': render_project_field('quick_reference'),
}
for placeholder, value in replacements.items():
    content = content.replace(placeholder, value)

# Any remaining unknown placeholders become TODO markers
def mark_remaining(match):
    name = match.group(1)
    return f'<!-- TODO: Fill in {name} for your project -->'

content = re.sub(r'\{\{([A-Z_]+)\}\}', mark_remaining, content)

with open(output_file, 'w') as f:
    f.write(content)
RENDER_PY

  echo "  Generated: ${file_label} (rendered from template)"
}

# Export render context as env vars for the Python renderer
export _RENDER_TEAM_JSON="$TEAM_JSON"
export _RENDER_ROLE_ID="$ROLE_ID"
export _RENDER_TEAM_ID="$TEAM_ID"
export _RENDER_PROJECT_ROOT="$PROJECT_ROOT"
export _RENDER_SCRIPT_DIR="$SCRIPT_DIR"

if [ "$PLATFORM" = "claude" ] || [ "$PLATFORM" = "both" ]; then
  render_template "${TEMPLATE_DIR}/CLAUDE.md.template" "${PROJECT_ROOT}/CLAUDE.md" "CLAUDE.md"
fi

if [ "$PLATFORM" = "codex" ] || [ "$PLATFORM" = "both" ]; then
  render_template "${TEMPLATE_DIR}/AGENTS.md.template" "${PROJECT_ROOT}/AGENTS.md" "AGENTS.md"
fi

# Seed a MEMORY.md reference at project root if not present
MEMORY_TEMPLATE="${TEMPLATE_DIR}/MEMORY.md.template"
MEMORY_TARGET="${PROJECT_ROOT}/memory/MEMORY_TEMPLATE.md"
if [ -f "$MEMORY_TEMPLATE" ] && [ ! -f "$MEMORY_TARGET" ]; then
  render_template "$MEMORY_TEMPLATE" "$MEMORY_TARGET" "memory/MEMORY_TEMPLATE.md"
fi

# Clean up render env vars
unset _RENDER_TEAM_JSON _RENDER_ROLE_ID _RENDER_TEAM_ID _RENDER_PROJECT_ROOT _RENDER_SCRIPT_DIR

echo ""

# ---- Step 7: Write team.json ----
echo -e "${GREEN}Step 7: Writing team configuration...${NC}"

ROLE_FILE="${SCRIPT_DIR}/roles/${ROLE_ID}.yaml"
if [ -f "$ROLE_FILE" ]; then
  echo "  Role definition found: ${ROLE_FILE}"
else
  echo -e "  ${YELLOW}No role definition file for ${ROLE_ID}. Skills will infer from team context.${NC}"
fi

# Write a JSON team config for easy consumption by any platform
# This is team-level only — sub-role is resolved at session start via prompt
python3 -c "
import json
team = json.loads('''$TEAM_JSON''')
team_config = {
    'team_id': '$TEAM_ID',
    'team_name': team.get('name', '$TEAM_ID'),
    'allowed_sub_roles': list(team.get('sub_teams', {}).keys()),
    'role_definitions': 'ai_team_config/roles/',
    'paths': team.get('default_paths', {})
}
with open('${PROJECT_ROOT}/team.json', 'w') as f:
    json.dump(team_config, f, indent=2)
print('  Wrote: team.json')
"

if [ -d "${PROJECT_ROOT}/.codex-workflow/config" ]; then
  safe_link "${PROJECT_ROOT}/team.json" "${PROJECT_ROOT}/.codex-workflow/config/team.json" ".codex-workflow/config/team.json" || true
fi

if [ -d "${PROJECT_ROOT}/.claude" ]; then
  safe_link "${PROJECT_ROOT}/team.json" "${PROJECT_ROOT}/.claude/team.json" ".claude/team.json" || true
fi
echo ""

# ---- Step 8: Compliance audit ----
echo -e "${GREEN}Step 8: Running compliance audit...${NC}"

COMPLIANCE_ISSUES=0
report_issue() {
  local message="$1"
  echo "  [non-compliant] ${message}"
  COMPLIANCE_ISSUES=$((COMPLIANCE_ISSUES + 1))
}

# Required memory files (from canonical scaffold)
while IFS= read -r rel_file; do
  if [ ! -f "${MEMORY_DIR}/${rel_file}" ]; then
    report_issue "Missing memory file: memory/${rel_file}"
  fi
done < <(cd "${SCRIPT_DIR}/scaffolds/memory" && find . -type f | sed 's|^\./||')

if [ ! -e "$DEVCOMM_DIR" ]; then
  report_issue "Missing dev_communication/ root"
else
  if [ -L "$DEVCOMM_DIR" ] && [ ! -e "$DEVCOMM_DIR" ]; then
    report_issue "Broken dev_communication symlink"
  fi

  for required_dir in \
    "shared/architecture" \
    "templates" \
    "archive" \
    "${TEAM_ID}/inbox" \
    "${TEAM_ID}/issues/queue" \
    "${TEAM_ID}/issues/active" \
    "${TEAM_ID}/issues/completed"
  do
    if [ ! -d "${DEVCOMM_DIR}/${required_dir}" ]; then
      report_issue "Missing dev_communication/${required_dir}"
    fi
  done

  # Shared architecture/guidance docs referenced by templates must exist.
  for required_file in \
    "shared/architecture/index.md" \
    "shared/architecture/decision-log.md" \
    "shared/architecture/templates/adr-template.md" \
    "shared/guidance/FEATURE_DEVELOPMENT_CHECKLIST.md"
  do
    if [ ! -f "${DEVCOMM_DIR}/${required_file}" ]; then
      report_issue "Missing dev_communication/${required_file}"
    fi
  done
fi

if [ ! -f "$ROLE_FILE" ]; then
  report_issue "Missing role definition: ai_team_config/roles/${ROLE_ID}.yaml"
fi

for proc_file in polling-workflow.md dev-lifecycle.md qa-lifecycle.md comms-protocol.md; do
  if [ ! -f "${SCRIPT_DIR}/procedures/${proc_file}" ]; then
    report_issue "Missing procedure: ai_team_config/procedures/${proc_file}"
  fi
done

# Installer package integrity: required ADR/checklist scaffolds must exist.
for scaffold_file in \
  "architecture/index.md" \
  "architecture/decision-log.md" \
  "architecture/templates/adr-template.md" \
  "guidance/FEATURE_DEVELOPMENT_CHECKLIST.md"
do
  if [ ! -f "${SCRIPT_DIR}/scaffolds/dev_communication/shared/${scaffold_file}" ]; then
    report_issue "Installer scaffold missing: ai_team_config/scaffolds/dev_communication/shared/${scaffold_file}"
  fi
done

if [ "$PLATFORM" = "claude" ] || [ "$PLATFORM" = "both" ]; then
  for skill_src_dir in "${PROJECT_ROOT}/ai_team_config/skills"/*/; do
    skill_name=$(basename "$skill_src_dir")
    if [ ! -L "${PROJECT_ROOT}/.claude/commands/${skill_name}.md" ]; then
      report_issue "Missing Claude skill symlink: .claude/commands/${skill_name}.md"
    fi
  done
fi

if [ "$PLATFORM" = "codex" ] || [ "$PLATFORM" = "both" ]; then
  for skill_src_dir in "${PROJECT_ROOT}/ai_team_config/skills"/*/; do
    skill_name=$(basename "$skill_src_dir")
    if [ ! -L "${PROJECT_ROOT}/.codex-workflow/skills/${skill_name}/SKILL.md" ]; then
      report_issue "Missing Codex skill symlink: .codex-workflow/skills/${skill_name}/SKILL.md"
    fi
  done
fi

# Validate generated platform docs: unresolved placeholders and path refs
for doc_file in "${PROJECT_ROOT}/CLAUDE.md" "${PROJECT_ROOT}/AGENTS.md"; do
  if [ -f "$doc_file" ]; then
    doc_name="$(basename "$doc_file")"

    # Check for unresolved {{...}} placeholders
    unresolved=$(grep -cE '\{\{[A-Z_]+\}\}' "$doc_file" 2>/dev/null || true)
    if [ "$unresolved" -gt 0 ]; then
      report_issue "${doc_name} has ${unresolved} unresolved {{PLACEHOLDER}} token(s)"
    fi

    # Check for <!-- TODO --> markers (project.yaml not filled in)
    todo_count=$(grep -cE '<!-- TODO:' "$doc_file" 2>/dev/null || true)
    if [ "$todo_count" -gt 0 ]; then
      report_issue "${doc_name} has ${todo_count} <!-- TODO --> section(s) — fill in project.yaml and re-run with --force-refresh-links"
    fi

    # Check for scaffold sentinel content that indicates project.yaml is uncustomized.
    sentinel_count=$(grep -cE '<!--\s*Fill in|No canonical spec documents configured\.' "$doc_file" 2>/dev/null || true)
    if [ "$sentinel_count" -gt 0 ]; then
      report_issue "${doc_name} still contains scaffold placeholder content — fill in project.yaml and re-run with --force-refresh-links"
    fi

    # Check that all ai_team_config/procedures/*.md references resolve to real files
    while IFS= read -r proc_ref; do
      proc_path="${PROJECT_ROOT}/${proc_ref}"
      if [ ! -f "$proc_path" ]; then
        report_issue "${doc_name} references non-existent procedure: ${proc_ref}"
      fi
    done < <(grep -oE 'ai_team_config/procedures/[a-z_-]+\.md' "$doc_file" 2>/dev/null | sort -u)

    # Check that all dev_communication/shared/*.md references resolve to real files.
    while IFS= read -r shared_ref; do
      shared_path="${PROJECT_ROOT}/${shared_ref}"
      if [ ! -f "$shared_path" ]; then
        report_issue "${doc_name} references non-existent shared doc: ${shared_ref}"
      fi
    done < <(grep -oE 'dev_communication/shared/[A-Za-z0-9_./-]+\.md' "$doc_file" 2>/dev/null | sort -u)
  fi
done

echo "  Compliance issues detected: ${COMPLIANCE_ISSUES}"
if [ "$COMPLIANCE_ISSUES" -ge "$REFRESH_THRESHOLD" ]; then
  echo -e "  ${YELLOW}Recommendation: refresh setup (issues >= threshold ${REFRESH_THRESHOLD}).${NC}"
  echo "  Suggested command:"
  echo "    ./ai_team_config/install.sh --team ${TEAM_ID} --role ${ROLE_ID} --platform ${PLATFORM} --devcomm create"
fi
echo ""

# ---- Summary ----
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  Installation Complete${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo -e "  Team:      ${YELLOW}${TEAM_ID}${NC}"
echo -e "  Role:      ${YELLOW}${ROLE_ID}${NC}"
echo -e "  Platform:  ${YELLOW}${PLATFORM}${NC}"
echo -e "  Memory:    ${GREEN}${MEMORY_DIR}${NC}"
echo ""
echo "  Working directories:"
echo "    Skills (canonical):  ai_team_config/skills/"
echo "    Procedures:          ai_team_config/procedures/"
echo "    Templates:           ai_team_config/templates/"
echo "    Memory vault:        memory/"
echo "    ADRs & specs:        dev_communication/shared/architecture/"
echo "    Team comms:          dev_communication/${TEAM_ID}/"
echo "    Role definitions:    ai_team_config/roles/"
echo "    Team config:         team.json"
echo ""
echo "  Sub-role is now selected at session start (no file to switch)."
echo "  To re-run the installer:"
echo "    ./ai_team_config/install.sh --team ${TEAM_ID} --role ${ROLE_ID} --platform ${PLATFORM}"
echo ""
echo "  Available skills: /comms /adr /memory /context /reflect /refine"
echo ""
