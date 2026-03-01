#!/usr/bin/env bash
# =============================================================================
# Codex Platform Setup
# =============================================================================
#
# Creates .codex-workflow/ config files and symlinks canonical skills + team
# configs from ai_team_config/. Also links team.json config.
#
# Usage: ./ai_team_config/platforms/codex/setup.sh <project_root> <team_id> <role_id>
#
# =============================================================================

set -euo pipefail

PROJECT_ROOT="${1:-.}"
TEAM_ID="${2:-}"
ROLE_ID="${3:-}"
SKILL_SOURCE="ai_team_config/skills"
TEAM_CONFIG_SOURCE="ai_team_config/team-configs"
CODEX_DIR="${PROJECT_ROOT}/.codex-workflow"
CONFIG_DIR="${CODEX_DIR}/config"
SKILL_DIR="${CODEX_DIR}/skills"
TEAM_CONFIG_DIR="${CODEX_DIR}/team-configs"
FORCE_REFRESH_LINKS="${FORCE_REFRESH_LINKS:-0}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"

echo "Setting up Codex workflow..."

mkdir -p "$CONFIG_DIR" "$SKILL_DIR" "$TEAM_CONFIG_DIR"

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
      echo "  Refreshed link ${label}; backup: ${backup_path}"
    else
      echo "  Skipped symlink ${label}: regular file/directory exists."
      return 1
    fi
  else
    ln -s "$target_for_link" "$link_path"
    echo "  Created symlink: ${label}"
  fi

  return 0
}

# Symlink each canonical skill into .codex-workflow/skills/<name>/
for skill_src_dir in "$PROJECT_ROOT/$SKILL_SOURCE"/*/; do
  skill_name=$(basename "$skill_src_dir")
  skill_file="${skill_src_dir}SKILL.md"

  if [ -f "$skill_file" ]; then
    target_dir="${SKILL_DIR}/${skill_name}"
    mkdir -p "$target_dir"

    target="${PROJECT_ROOT}/${SKILL_SOURCE}/${skill_name}/SKILL.md"
    link_path="${target_dir}/SKILL.md"

    safe_link "$target" "$link_path" "${skill_name}/SKILL.md" || true
  fi
done

# Symlink shared team-config definitions into .codex-workflow/team-configs/
for team_cfg in "$PROJECT_ROOT/$TEAM_CONFIG_SOURCE"/*; do
  cfg_name=$(basename "$team_cfg")
  link_path="${TEAM_CONFIG_DIR}/${cfg_name}"
  safe_link "$team_cfg" "$link_path" "team-configs/${cfg_name}" || true
done

# Canonical team config shared across platforms
safe_link "${PROJECT_ROOT}/team.json" "${CONFIG_DIR}/team.json" "config/team.json" || true

# Write active-team.json from profiles.json (team-level only, no sub-role identity)
if [ -n "$TEAM_ID" ]; then
  PROFILES_FILE="${PROJECT_ROOT}/ai_team_config/teams/profiles.json"
  if command -v python3 &>/dev/null && [ -f "$PROFILES_FILE" ]; then
    python3 -c "
import json, sys
with open('$PROFILES_FILE') as f:
    profiles = json.load(f)
team = profiles['teams'].get('$TEAM_ID')
if not team:
    print(f'Team $TEAM_ID not found in profiles.json', file=sys.stderr)
    sys.exit(1)
manifest = {
    'pack_name': 'codex-workflow',
    'team_id': '$TEAM_ID',
    'team_profile': team,
    'allowed_sub_roles': list(team.get('sub_teams', {}).keys()),
    'project_root': '.'
}
with open('$CONFIG_DIR/active-team.json', 'w') as f:
    json.dump(manifest, f, indent=2)
print('  Wrote: config/active-team.json')
"
  fi
fi

echo "Codex workflow installed."
