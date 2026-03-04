#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ai_team_config/scripts/full_e2e_once_per_push.sh [options]

Run full e2e once per new git HEAD after all active frontend issues are QA: PASS.

Options:
  --repo-root PATH          Project root (default: current directory)
  --interval SECONDS        Poll interval in watch mode (default: 240)
  --timeout-seconds N       Timeout for full e2e run (default: 3600, 0 disables)
  --state-file PATH         State file path (default: dev_communication/frontend/automation/full-e2e-last-head.txt)
  --watch                   Run continuously (default)
  --once                    Run a single evaluation
  --help                    Show this help
EOF
}

log() {
  printf '[full-e2e-on-push] %s\n' "$*"
}

repo_root="$(pwd)"
interval=240
timeout_seconds=3600
watch_mode=1
state_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) repo_root="$2"; shift 2 ;;
    --interval) interval="$2"; shift 2 ;;
    --timeout-seconds) timeout_seconds="$2"; shift 2 ;;
    --state-file) state_file="$2"; shift 2 ;;
    --watch) watch_mode=1; shift 1 ;;
    --once) watch_mode=0; shift 1 ;;
    --help|-h) usage; exit 0 ;;
    *) log "ERROR: Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if ! [[ "$interval" =~ ^[0-9]+$ ]]; then
  log "ERROR: --interval must be a non-negative integer"
  exit 1
fi

if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]]; then
  log "ERROR: --timeout-seconds must be a non-negative integer"
  exit 1
fi

repo_root="$(cd "$repo_root" && pwd)"
automation_dir="$repo_root/dev_communication/frontend/automation"
active_dir="$repo_root/dev_communication/frontend/issues/active"

mkdir -p "$automation_dir"
if [[ -z "$state_file" ]]; then
  state_file="$automation_dir/full-e2e-last-head.txt"
fi

all_active_issues_pass() {
  local issue_file
  shopt -s nullglob
  for issue_file in "$active_dir"/*.md; do
    local qa_state
    qa_state="$(sed -n -E 's/^## QA:[[:space:]]*(.*)$/\1/p' "$issue_file" | head -n1 | tr '[:lower:]' '[:upper:]')"
    if [[ "$qa_state" != "PASS" ]]; then
      return 1
    fi
  done
  return 0
}

run_full_e2e_once() {
  local head_sha="$1"
  local run_stamp
  run_stamp="$(date -u +%Y%m%d-%H%M%S)"
  local run_log="$automation_dir/full-e2e-${run_stamp}.log"

  log "Running full e2e for HEAD $head_sha"
  if [[ "$timeout_seconds" -gt 0 ]] && command -v timeout >/dev/null 2>&1; then
    if (cd "$repo_root" && timeout --signal=TERM --kill-after=30s "${timeout_seconds}s" bash -lc "npm run e2e") >"$run_log" 2>&1; then
      log "Full e2e passed for $head_sha (log: $run_log)"
    else
      log "Full e2e failed for $head_sha (log: $run_log)"
    fi
  else
    if (cd "$repo_root" && bash -lc "npm run e2e") >"$run_log" 2>&1; then
      log "Full e2e passed for $head_sha (log: $run_log)"
    else
      log "Full e2e failed for $head_sha (log: $run_log)"
    fi
  fi

  printf '%s\n' "$head_sha" >"$state_file"
}

evaluate_once() {
  local head_sha
  if ! head_sha="$(cd "$repo_root" && git rev-parse HEAD 2>/dev/null)"; then
    log "Skipping: unable to resolve git HEAD."
    return 0
  fi

  local last_head=""
  if [[ -f "$state_file" ]]; then
    last_head="$(head -n1 "$state_file" | tr -d '\r\n')"
  fi

  if ! all_active_issues_pass; then
    log "Active issues are not all QA: PASS. Skipping full e2e for now."
    return 0
  fi

  if [[ "$head_sha" == "$last_head" ]]; then
    log "HEAD unchanged ($head_sha). Full e2e already executed for this commit."
    return 0
  fi

  run_full_e2e_once "$head_sha"
}

if [[ "$watch_mode" -eq 1 ]]; then
  while true; do
    evaluate_once
    sleep "$interval"
  done
else
  evaluate_once
fi

