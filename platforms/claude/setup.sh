#!/usr/bin/env bash
# =============================================================================
# Claude Code Platform Setup
# =============================================================================
#
# Creates .claude/commands/ skill symlinks, .claude/team-configs/ symlinks,
# and a platform team.json alias to the canonical project team config file.
#
# Usage: ./ai_team_config/platforms/claude/setup.sh <project_root>
#
# =============================================================================

set -euo pipefail

PROJECT_ROOT="${1:-.}"
SKILL_SOURCE="ai_team_config/skills"
TEAM_CONFIG_SOURCE="ai_team_config/team-configs"
COMMAND_DIR="${PROJECT_ROOT}/.claude/commands"
TEAM_CONFIG_DIR="${PROJECT_ROOT}/.claude/team-configs"
FORCE_REFRESH_LINKS="${FORCE_REFRESH_LINKS:-0}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"

echo "Setting up Claude Code skills..."

mkdir -p "$COMMAND_DIR" "$TEAM_CONFIG_DIR"

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

# Map each canonical skill to a .claude/commands/ symlink
# Claude Code loads skills from .claude/commands/<name>.md
for skill_dir in "$PROJECT_ROOT/$SKILL_SOURCE"/*/; do
  skill_name=$(basename "$skill_dir")
  skill_file="${skill_dir}SKILL.md"

  if [ -f "$skill_file" ]; then
    target="${PROJECT_ROOT}/${SKILL_SOURCE}/${skill_name}/SKILL.md"
    link_path="${COMMAND_DIR}/${skill_name}.md"

    safe_link "$target" "$link_path" "${skill_name}.md" || true
  fi
done

for team_cfg in "$PROJECT_ROOT/$TEAM_CONFIG_SOURCE"/*; do
  cfg_name=$(basename "$team_cfg")
  link_path="${TEAM_CONFIG_DIR}/${cfg_name}"
  safe_link "$team_cfg" "$link_path" "team-configs/${cfg_name}" || true
done

safe_link "${PROJECT_ROOT}/team.json" "${PROJECT_ROOT}/.claude/team.json" "team.json" || true

echo "Claude Code skills installed."
echo ""
echo "Verify with: ls -la ${COMMAND_DIR}/"
