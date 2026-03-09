#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ai_team_config/scripts/qa_poll_cycle.sh [options]

Poll QA-ready items and run QA gate verification for frontend_qa/backend_qa roles.

Options:
  --repo-root PATH          Project root (default: current directory)
  --team TEAM               Team id (frontend|backend). Auto-detected from team.json if omitted.
  --role ROLE               Role id (frontend-qa|backend-qa). Defaults to {team_id}-qa if omitted.
  --interval SECONDS        Poll interval when --watch is used (default: 240)
  --idle-stop-seconds N     Stop watch mode after N seconds with no inbox/active issue changes (default: 1800)
  --watch                   Run continuously
  --once                    Run a single poll cycle (default)
  --autonomous              Implies --watch --approve --recheck-existing --emit-dev-message.
                            Explicit flags always override autonomous defaults.
  --approve                 If gates pass, set issue to COMPLETE and move active -> completed
  --manual-ok               Confirm manual code review is complete for this run
  --manual-notes TEXT       Manual review notes appended to QA evidence
  --issue ISSUE_ID          Evaluate only one issue id (for example UI-ISS-190)
  --recheck-existing        Re-run QA on issues that already have QA Verification entries
  --emit-dev-message        Write QA pass/blocked messages to team inbox (default)
  --no-emit-dev-message     Do not write QA pass/blocked messages
  --stale-recheck-hours N   Re-run BLOCKED issues after N hours even without fresh evidence (default: 12)
  --no-stale-recheck        Disable time-based recheck; require fresh dev evidence only
  --pending-manual-review-sla-minutes N
                            Guardrail threshold for stale QA=PENDING_MANUAL_REVIEW backlog (default: 30)
  --gate-timeout SECONDS    Per-gate execution timeout (default: 600)
  --dry-run                 Do not modify issue/message files
  --help                    Show this help

Environment overrides:
  QA_CMD_TYPECHECK
  QA_CMD_UNIT
  QA_CMD_INTEGRATION
  QA_CMD_UAT
EOF
}

log() {
  printf '[qa-cycle] %s\n' "$*"
}

err() {
  printf '[qa-cycle] ERROR: %s\n' "$*" >&2
}

extract_json_field() {
  local file="$1"
  local field="$2"
  sed -n -E "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\\1/p" "$file" | head -n1
}

repo_root="$(pwd)"
team_id=""
role_id=""
poll_interval=240
idle_stop_seconds=1800
watch_mode=0
approve_mode=0
manual_ok=0
manual_notes=""
issue_filter=""
recheck_existing=0
emit_dev_message=1
dry_run=0
autonomous=0
gate_timeout=600
stale_recheck_hours=12
stale_recheck=1
stale_in_progress_minutes=60
pending_manual_review_sla_minutes=30

# Track which flags were explicitly set to implement flag precedence
explicit_watch=0
explicit_emit=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) repo_root="$2"; shift 2 ;;
    --team) team_id="$2"; shift 2 ;;
    --role) role_id="$2"; shift 2 ;;
    --interval) poll_interval="$2"; shift 2 ;;
    --idle-stop-seconds) idle_stop_seconds="$2"; shift 2 ;;
    --watch) watch_mode=1; explicit_watch=1; shift 1 ;;
    --once) watch_mode=0; explicit_watch=1; shift 1 ;;
    --autonomous) autonomous=1; shift 1 ;;
    --approve) approve_mode=1; shift 1 ;;
    --manual-ok) manual_ok=1; shift 1 ;;
    --manual-notes) manual_notes="$2"; shift 2 ;;
    --issue) issue_filter="$2"; shift 2 ;;
    --recheck-existing) recheck_existing=1; shift 1 ;;
    --emit-dev-message) emit_dev_message=1; explicit_emit=1; shift 1 ;;
    --no-emit-dev-message) emit_dev_message=0; explicit_emit=1; shift 1 ;;
    --stale-recheck-hours) stale_recheck_hours="$2"; shift 2 ;;
    --no-stale-recheck) stale_recheck=0; shift 1 ;;
    --pending-manual-review-sla-minutes) pending_manual_review_sla_minutes="$2"; shift 2 ;;
    --gate-timeout) gate_timeout="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift 1 ;;
    --help|-h) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

# --autonomous sets defaults; explicit flags override
if [[ "$autonomous" -eq 1 ]]; then
  if [[ "$explicit_watch" -eq 0 ]]; then
    watch_mode=1
  fi
  approve_mode=1
  recheck_existing=1
  if [[ "$explicit_emit" -eq 0 ]]; then
    emit_dev_message=1
  fi
fi

if ! [[ "$poll_interval" =~ ^[0-9]+$ ]]; then
  err "--interval must be a positive integer"
  exit 1
fi

if ! [[ "$idle_stop_seconds" =~ ^[0-9]+$ ]]; then
  err "--idle-stop-seconds must be a non-negative integer"
  exit 1
fi

if ! [[ "$pending_manual_review_sla_minutes" =~ ^[0-9]+$ ]]; then
  err "--pending-manual-review-sla-minutes must be a non-negative integer"
  exit 1
fi

repo_root="$(cd "$repo_root" && pwd)"
team_json_file="$repo_root/team.json"

if [[ -z "$team_id" ]]; then
  if [[ -f "$team_json_file" ]]; then
    detected_team="$(extract_json_field "$team_json_file" "team_id" || true)"
    team_id="${team_id:-$detected_team}"
  fi
fi

if [[ -z "$team_id" && -n "$role_id" ]]; then
  team_id="${role_id%%-*}"
fi

# Default role to {team_id}-qa since this script only runs for QA roles
if [[ -z "$role_id" && -n "$team_id" ]]; then
  role_id="${team_id}-qa"
fi

if [[ -z "$role_id" || -z "$team_id" ]]; then
  err "Could not resolve role/team. Provide --role and --team or set team.json."
  exit 1
fi

case "$role_id" in
  frontend-qa|backend-qa) ;;
  *)
    err "Role '$role_id' is not a QA sub-team role (frontend-qa/backend-qa)."
    exit 1
    ;;
esac

if [[ "$team_id" != "frontend" && "$team_id" != "backend" ]]; then
  err "Team '$team_id' is unsupported by this script. Use frontend or backend."
  exit 1
fi

ready_regex='Development Complete|Awaiting QA|QA Ready|Ready for QA|QA Review Request|QA Re-Verification Request|QA Reverification Request|Re-Verification Request|Reverification Request|QA Recheck|QA Re-check'
timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

day_stamp() {
  date -u +"%Y-%m-%d"
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

inbox_dir="$repo_root/dev_communication/$team_id/inbox"
issues_active_dir="$repo_root/dev_communication/$team_id/issues/active"
issues_completed_dir="$repo_root/dev_communication/$team_id/issues/completed"
archive_root="$repo_root/dev_communication/archive"

if [[ ! -d "$inbox_dir" || ! -d "$issues_active_dir" || ! -d "$issues_completed_dir" ]]; then
  err "Missing comms directories under dev_communication/$team_id. Check project setup."
  exit 1
fi

project_name="$(basename "$repo_root")"
from_header="$(tr '[:lower:]' '[:upper:]' <<< "${team_id:0:1}")${team_id:1}-QA"
to_header="$(tr '[:lower:]' '[:upper:]' <<< "${team_id:0:1}")${team_id:1}-Dev"

script_exists() {
  local script_name="$1"
  local package_json="$repo_root/package.json"
  [[ -f "$package_json" ]] && grep -q "\"$script_name\"" "$package_json"
}

select_default_cmd() {
  local gate="$1"
  local team="$2"
  local cmd=""
  local candidates=()

  case "$gate" in
    typecheck)
      candidates=("npm run typecheck")
      ;;
    unit)
      candidates=("npm run test:unit" "npm run test")
      ;;
    integration)
      candidates=("npm run test:integration")
      ;;
    uat)
      if [[ "$team" == "frontend" ]]; then
        candidates=("npm run test:uat" "npm run e2e")
      else
        candidates=("npm run test:uat")
      fi
      ;;
    *)
      ;;
  esac

  for cmd in "${candidates[@]}"; do
    if [[ "$cmd" =~ ^npm[[:space:]]+run[[:space:]]+([^[:space:]]+) ]]; then
      local script_name="${BASH_REMATCH[1]}"
      if script_exists "$script_name"; then
        printf '%s' "$cmd"
        return 0
      fi
    else
      printf '%s' "$cmd"
      return 0
    fi
  done

  printf ''
}

run_gate() {
  local gate="$1"
  local cmd="$2"
  local log_dir="$3"
  local log_file="$log_dir/${gate}.log"
  local result_var="$4"
  local reason_var="$5"

  if [[ -z "$cmd" ]]; then
    printf -v "$result_var" "MISSING"
    printf -v "$reason_var" "No configured command found for $gate"
    return 0
  fi

  log "Running $gate gate: $cmd (timeout ${gate_timeout}s)"
  local exit_code=0
  (cd "$repo_root" && timeout "${gate_timeout}" bash -c "$cmd") >"$log_file" 2>&1 || exit_code=$?
  if [[ "$exit_code" -eq 0 ]]; then
    printf -v "$result_var" "PASS"
    printf -v "$reason_var" "$cmd"
  elif [[ "$exit_code" -eq 124 ]]; then
    printf -v "$result_var" "FAIL"
    printf -v "$reason_var" "Timed out after ${gate_timeout}s ($cmd)"
  else
    printf -v "$result_var" "FAIL"
    printf -v "$reason_var" "$cmd (see $log_file)"
  fi
}

find_issue_file_by_id() {
  local issue_id="$1"
  find "$issues_active_dir" -maxdepth 1 -type f -name "${issue_id}*.md" | head -n1
}

extract_issue_id_from_file() {
  local issue_file="$1"
  local base
  base="$(basename "$issue_file")"
  sed -E 's/^([A-Za-z]+-[A-Za-z]+-[0-9]+).*/\1/' <<<"$base"
}

extract_issue_field_value() {
  local issue_file="$1"
  local field="$2"
  awk -v field="$field" '
    {
      if ($0 ~ "^##[[:space:]]*" field ":[[:space:]]*") {
        line=$0
        sub("^##[[:space:]]*" field ":[[:space:]]*", "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
        exit
      }
      if ($0 ~ "^\\*\\*" field ":\\*\\*[[:space:]]*") {
        line=$0
        sub("^\\*\\*" field ":\\*\\*[[:space:]]*", "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
        exit
      }
    }
  ' "$issue_file"
}

upsert_issue_field() {
  local issue_file="$1"
  local field="$2"
  local value="$3"
  local default_style="${4:-heading}" # heading|bold
  local dry_run_note="${5:-}"

  if [[ "$dry_run" -eq 1 ]]; then
    log "Dry run: would set ${field}=${value} in ${issue_file}${dry_run_note:+ (${dry_run_note})}"
    return 0
  fi

  local temp_file
  temp_file="$(mktemp)"

  awk -v field="$field" -v value="$value" -v default_style="$default_style" '
    BEGIN { updated=0 }
    {
      if (!updated && $0 ~ "^##[[:space:]]*" field ":[[:space:]]*") {
        print "## " field ": " value
        updated=1
      } else if (!updated && $0 ~ "^\\*\\*" field ":\\*\\*[[:space:]]*") {
        print "**" field ":** " value
        updated=1
      } else {
        print $0
      }
    }
    END {
      if (!updated) {
        print ""
        if (default_style == "bold") {
          print "**" field ":** " value
        } else {
          print "## " field ": " value
        }
      }
    }
  ' "$issue_file" >"$temp_file"

  mv "$temp_file" "$issue_file"
}

set_issue_qa_state() {
  local issue_file="$1"
  local qa_state="$2"
  upsert_issue_field "$issue_file" "QA" "$qa_state" "heading" "qa-state transition"
}

append_qa_verification_section() {
  local issue_file="$1"
  local issue_id="$2"
  local verdict="$3"
  local typecheck_result="$4"
  local unit_result="$5"
  local integration_result="$6"
  local uat_result="$7"
  local coverage_note="$8"
  local manual_note="$9"
  local unblock_note="${10}"
  local recommendations="${11}"
  local commit_push_note="${12}"

  if [[ "$dry_run" -eq 1 ]]; then
    log "Dry run: would append QA Verification section to $issue_file"
    return 0
  fi

  cat >>"$issue_file" <<EOF

## QA Verification ($(timestamp_utc))

- QA Role: ${role_id}
- Issue: ${issue_id}
- Verdict: ${verdict}
- Automated Gates:
  - Typecheck: ${typecheck_result}
  - Unit: ${unit_result}
  - Integration: ${integration_result}
  - UAT: ${uat_result}
- Coverage Review: ${coverage_note}
- Manual Review: ${manual_note}
- Commit/Push Evidence: ${commit_push_note}
- Recommendations to Dev: ${recommendations}
- Unblock Criteria: ${unblock_note}
EOF
}

set_issue_complete_status() {
  local issue_file="$1"
  upsert_issue_field "$issue_file" "Status" "COMPLETE" "heading" "completion"
}

emit_dev_feedback_message() {
  local issue_id="$1"
  local verdict="$2"
  local qa_state="$3"
  local summary="$4"
  local unblock="$5"
  local out_file="$6"
  if [[ "$dry_run" -eq 1 ]]; then
    log "Dry run: would write QA feedback message to $out_file"
    return 0
  fi

  cat >"$out_file" <<EOF
# QA ${verdict}: ${issue_id}

**From:** ${from_header}
**To:** ${to_header}
**Date:** $(day_stamp)
**Priority:** High
**Type:** Response
**QA:** ${qa_state}

## Content

${summary}

## Unblock Criteria

- ${unblock}

## Related

- Issue: ${issue_id}
EOF
}

move_related_messages() {
  local issue_id="$1"
  if [[ "$dry_run" -eq 1 ]]; then
    log "Dry run: would move related messages for $issue_id"
    return 0
  fi

  local moved_count=0
  local msg

  local inbox_completed="$inbox_dir/completed"
  if [[ -d "$inbox_completed" ]]; then
    mkdir -p "$inbox_completed"
    while IFS= read -r msg; do
      mv "$msg" "$inbox_completed/"
      moved_count=$((moved_count + 1))
    done < <(find "$inbox_dir" -maxdepth 1 -type f -name '*.md' -exec grep -Eil "$issue_id" {} + 2>/dev/null || true)
    log "Moved $moved_count related inbox messages to $inbox_completed"
    return 0
  fi

  local archive_dir="$archive_root/$(day_stamp)_$(slugify "${issue_id}_qa_thread")"
  mkdir -p "$archive_dir"
  while IFS= read -r msg; do
    mv "$msg" "$archive_dir/"
    moved_count=$((moved_count + 1))
  done < <(find "$inbox_dir" -maxdepth 1 -type f -name '*.md' -exec grep -Eil "$issue_id" {} + 2>/dev/null || true)
  log "Moved $moved_count related inbox messages to $archive_dir"
}

issue_has_qa_marker() {
  local issue_file="$1"
  if grep -Eiq "$ready_regex" "$issue_file"; then
    return 0
  fi

  local status
  status="$(extract_issue_field_value "$issue_file" "Status" | tr '[:lower:]' '[:upper:]')"
  if [[ "$status" == "DEV_COMPLETE" ]]; then
    return 0
  fi

  local qa_state
  qa_state="$(extract_issue_field_value "$issue_file" "QA" | tr '[:lower:]' '[:upper:]')"
  [[ "$qa_state" == "PENDING" || "$qa_state" == "PENDING_MANUAL_REVIEW" || "$qa_state" == "IN_PROGRESS" || "$qa_state" == "BLOCKED" || "$qa_state" == "PASS" ]]
}

issue_has_ready_inbox_marker() {
  local issue_id="$1"
  local msg_file
  while IFS= read -r msg_file; do
    if grep -Eiq "$issue_id" "$msg_file"; then
      return 0
    fi
  done < <(find "$inbox_dir" -maxdepth 1 -type f -name '*.md' -exec grep -Eil "$ready_regex" {} + 2>/dev/null || true)
  return 1
}

latest_dev_handoff_file_for_issue() {
  local issue_id="$1"
  local latest_file=""
  local latest_epoch=0
  local msg_file

  while IFS= read -r msg_file; do
    [[ -z "$msg_file" ]] && continue
    if ! grep -q "$issue_id" "$msg_file" 2>/dev/null; then
      continue
    fi
    local msg_from
    msg_from="$(grep -m1 -E '^\*\*From:\*\* ' "$msg_file" | sed -E 's/^\*\*From:\*\* //')"
    if [[ "${msg_from,,}" != "${to_header,,}" ]]; then
      continue
    fi
    local msg_epoch
    msg_epoch="$(stat -c '%Y' "$msg_file" 2>/dev/null || stat -f '%m' "$msg_file" 2>/dev/null || echo 0)"
    if [[ "$msg_epoch" -gt "$latest_epoch" ]]; then
      latest_epoch="$msg_epoch"
      latest_file="$msg_file"
    fi
  done < <(find "$inbox_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)

  printf '%s' "$latest_file"
}

resolve_commit_push_evidence() {
  local issue_file="$1"
  local issue_id="$2"
  local status_var="$3"
  local note_var="$4"
  local commit_var="$5"

  local latest_handoff
  latest_handoff="$(latest_dev_handoff_file_for_issue "$issue_id" || true)"

  local sources=("$issue_file")
  if [[ -n "$latest_handoff" && -f "$latest_handoff" ]]; then
    sources+=("$latest_handoff")
  fi

  local commit_ref=""
  commit_ref="$(cat "${sources[@]}" 2>/dev/null | grep -Eo '\b[0-9a-f]{7,40}\b' | tail -n1 || true)"

  local push_present=0
  if cat "${sources[@]}" 2>/dev/null | grep -Eiq '\bpush(ed|ing)?\b'; then
    push_present=1
  fi

  local note=""
  if [[ -n "$commit_ref" ]]; then
    note="commit ${commit_ref:0:12}"
  else
    note="commit reference missing"
  fi
  if [[ "$push_present" -eq 1 ]]; then
    note="${note}; push evidence present"
  else
    note="${note}; push evidence missing"
  fi
  if [[ -n "$latest_handoff" ]]; then
    note="${note}; handoff message present"
  else
    note="${note}; handoff message missing"
  fi

  local status="missing"
  if [[ -n "$commit_ref" && "$push_present" -eq 1 ]]; then
    status="verified"
  fi

  printf -v "$status_var" '%s' "$status"
  printf -v "$note_var" '%s' "$note"
  printf -v "$commit_var" '%s' "$commit_ref"
}

snapshot_poll_state() {
  {
    find "$inbox_dir" -maxdepth 1 -type f -name '*.md' -printf 'inbox/%f|%T@|%s\n' 2>/dev/null || true
    find "$issues_active_dir" -maxdepth 1 -type f -name '*.md' -printf 'active/%f|%T@|%s\n' 2>/dev/null || true
  } | sort | sha256sum | awk '{print $1}'
}

issue_already_reviewed() {
  local issue_file="$1"
  grep -Eq '^## QA Verification \(' "$issue_file"
}

file_age_minutes() {
  local file="$1"
  local file_epoch now_epoch
  file_epoch="$(stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null || echo 0)"
  now_epoch="$(date +%s)"
  echo $(( (now_epoch - file_epoch) / 60 ))
}

last_qa_verification_epoch() {
  local issue_file="$1"
  local ts
  ts="$(grep -oP '## QA Verification \(\K[0-9T:\-Z]+' "$issue_file" | tail -n1 || true)"
  if [[ -z "$ts" ]]; then
    echo 0
    return
  fi
  date -d "$ts" +%s 2>/dev/null || echo 0
}

has_fresh_dev_evidence() {
  local issue_file="$1"
  local issue_id="$2"
  local last_qa_epoch
  last_qa_epoch="$(last_qa_verification_epoch "$issue_file")"
  if [[ "$last_qa_epoch" -eq 0 ]]; then
    return 0  # No prior QA verification, treat as fresh
  fi

  # BLOCKED issue re-pickup requires BOTH:
  #   1. a fresh dev inbox handoff/re-handoff message
  #   2. a fresh issue-level `## Dev Response (...)` annotation
  local latest_dev_handoff_epoch=0
  local msg_file
  while IFS= read -r msg_file; do
    [[ -z "$msg_file" ]] && continue
    local msg_epoch
    msg_epoch="$(stat -c '%Y' "$msg_file" 2>/dev/null || stat -f '%m' "$msg_file" 2>/dev/null || echo 0)"
    local msg_from
    msg_from="$(grep -m1 -E '^\*\*From:\*\* ' "$msg_file" | sed -E 's/^\*\*From:\*\* //')"
    if [[ "${msg_from,,}" != "${to_header,,}" ]]; then
      continue
    fi
    if ! grep -q "$issue_id" "$msg_file" 2>/dev/null; then
      continue
    fi
    local msg_name
    msg_name="$(basename "$msg_file" | tr '[:upper:]' '[:lower:]')"
    if [[ "$msg_name" != *dev-rehandoff* && "$msg_name" != *qa-handoff* ]] \
      && ! grep -Eiq 'QA Handoff|Re-Handoff|Rehandoff|QA Review Request|Awaiting QA|QA Ready|Ready for QA' "$msg_file"; then
      continue
    fi
    if [[ "$msg_epoch" -gt "$last_qa_epoch" && "$msg_epoch" -gt "$latest_dev_handoff_epoch" ]]; then
      latest_dev_handoff_epoch="$msg_epoch"
    fi
  done < <(find "$inbox_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)

  local dev_response_ts
  dev_response_ts="$(grep -oP '## Dev Response \(\K[^)]+' "$issue_file" | tail -n1 || true)"
  local dev_response_epoch=0
  if [[ -n "$dev_response_ts" ]]; then
    dev_response_epoch="$(date -d "$dev_response_ts" +%s 2>/dev/null || echo 0)"
  fi

  if [[ "$latest_dev_handoff_epoch" -gt "$last_qa_epoch" && "$dev_response_epoch" -gt "$last_qa_epoch" ]]; then
    return 0
  fi

  return 1
}

reset_stale_in_progress() {
  local f issue_id qa_state age
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    qa_state="$(extract_issue_field_value "$f" "QA" | tr '[:lower:]' '[:upper:]')"
    if [[ "$qa_state" == "IN_PROGRESS" ]]; then
      age="$(file_age_minutes "$f")"
      if [[ "$age" -ge "$stale_in_progress_minutes" ]]; then
        issue_id="$(extract_issue_id_from_file "$f")"
        log "Resetting stale IN_PROGRESS (${age}min old) to PENDING: $issue_id"
        set_issue_qa_state "$f" "PENDING"
      fi
    fi
  done < <(find "$issues_active_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)
}

qa_state_priority() {
  # Priority: 1=PASS (auto-heal), 2=PENDING_MANUAL_REVIEW, 3=BLOCKED, 4=PENDING/other
  local issue_file="$1"
  local qa_state
  qa_state="$(extract_issue_field_value "$issue_file" "QA" | tr '[:lower:]' '[:upper:]')"
  case "$qa_state" in
    PASS) echo 1 ;;
    PENDING_MANUAL_REVIEW) echo 2 ;;
    BLOCKED) echo 3 ;;
    *) echo 4 ;;
  esac
}

stale_pending_manual_review_files() {
  local f qa_state age
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    qa_state="$(extract_issue_field_value "$f" "QA" | tr '[:lower:]' '[:upper:]')"
    if [[ "$qa_state" == "PENDING_MANUAL_REVIEW" ]]; then
      age="$(file_age_minutes "$f")"
      if [[ "$age" -ge "$pending_manual_review_sla_minutes" ]]; then
        printf '%s\n' "$f"
      fi
    fi
  done < <(find "$issues_active_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)
}

discover_qa_ready_issue_files() {
  local issue_files=()
  local f

  while IFS= read -r f; do
    issue_files+=("$f")
  done < <(find "$issues_active_dir" -maxdepth 1 -type f -name '*.md' | sort)

  # Add issues referenced by QA-ready inbox messages.
  while IFS= read -r msg_file; do
    while IFS= read -r issue_id; do
      local issue_file
      issue_file="$(find_issue_file_by_id "$issue_id" || true)"
      if [[ -n "$issue_file" ]]; then
        issue_files+=("$issue_file")
      fi
    done < <(grep -Eo '[A-Za-z]+-[A-Za-z]+-[0-9]+' "$msg_file" | sort -u || true)
  done < <(find "$inbox_dir" -maxdepth 1 -type f -name '*.md' -exec grep -Eil "$ready_regex" {} + 2>/dev/null || true)

  # Deduplicate, then sort by priority (PASS > PENDING_MANUAL_REVIEW > BLOCKED > PENDING)
  local unique_files
  unique_files="$(printf '%s\n' "${issue_files[@]}" | awk 'NF' | sort -u)"
  if [[ -z "$unique_files" ]]; then
    return 0
  fi
  local prioritized=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local pri
    pri="$(qa_state_priority "$f")"
    prioritized+=("${pri}|${f}")
  done <<<"$unique_files"
  printf '%s\n' "${prioritized[@]}" | sort -t'|' -k1,1n | cut -d'|' -f2-
}

evaluate_issue() {
  local issue_file="$1"
  local issue_id="$2"
  local run_stamp
  run_stamp="$(date -u +"%Y%m%d-%H%M%S")"
  local run_log_dir="/tmp/qa-cycle-${team_id}-${issue_id}-${run_stamp}"
  mkdir -p "$run_log_dir"

  local typecheck_cmd="${QA_CMD_TYPECHECK:-$(select_default_cmd typecheck "$team_id")}"
  local unit_cmd="${QA_CMD_UNIT:-$(select_default_cmd unit "$team_id")}"
  local integration_cmd="${QA_CMD_INTEGRATION:-$(select_default_cmd integration "$team_id")}"
  local uat_cmd="${QA_CMD_UAT:-$(select_default_cmd uat "$team_id")}"

  local typecheck_result="" typecheck_reason=""
  local unit_result="" unit_reason=""
  local integration_result="" integration_reason=""
  local uat_result="" uat_reason=""

  local commit_push_status="" commit_push_note="" commit_ref=""
  resolve_commit_push_evidence "$issue_file" "$issue_id" commit_push_status commit_push_note commit_ref
  if [[ "$commit_push_status" != "verified" ]]; then
    set_issue_qa_state "$issue_file" "BLOCKED"
    append_qa_verification_section \
      "$issue_file" "$issue_id" "Need More Info" \
      "N/A (entry validation blocked before gates)" \
      "N/A (entry validation blocked before gates)" \
      "N/A (entry validation blocked before gates)" \
      "N/A (entry validation blocked before gates)" \
      "Entry validation stopped before automated verification because required commit/push evidence is missing from the dev handoff." \
      "Entry validation failed before automated review." \
      "Add a commit hash/reference to the issue notes or handoff and explicitly state the work was pushed to the shared remote branch, then re-handoff." \
      "Commit/push evidence is now a required QA entry criterion. Re-submit with both a commit reference and explicit push evidence." \
      "$commit_push_note"
    if [[ "$emit_dev_message" -eq 1 ]]; then
      local feedback_file="$inbox_dir/$(day_stamp)_$(slugify "${issue_id}_qa_Need_More_Info")_$(date -u +%H%M%S).md"
      emit_dev_feedback_message "$issue_id" "Need More Info" "BLOCKED" \
        "Commit/push evidence missing from the dev handoff. Add a commit hash/reference and explicit push statement, then re-handoff." \
        "Add a commit hash/reference and explicit push statement to the issue notes or handoff." \
        "$feedback_file"
      log "Wrote QA feedback message: $feedback_file"
    fi
    log "Issue $issue_id needs more info before QA gates: $commit_push_note"
    return 0
  fi

  set_issue_qa_state "$issue_file" "IN_PROGRESS"
  run_gate "typecheck" "$typecheck_cmd" "$run_log_dir" typecheck_result typecheck_reason
  run_gate "unit" "$unit_cmd" "$run_log_dir" unit_result unit_reason
  run_gate "integration" "$integration_cmd" "$run_log_dir" integration_result integration_reason
  run_gate "uat" "$uat_cmd" "$run_log_dir" uat_result uat_reason

  local coverage_note="Coverage evidence missing: add acceptance-criteria-to-test mapping and regression scope."
  if grep -Eiq 'coverage|test evidence|acceptance criteria' "$issue_file"; then
    coverage_note="Coverage evidence present in issue; verify mappings stay current with changes."
  fi

  local manual_note="Manual review not confirmed in this run."
  if [[ "$manual_ok" -eq 1 ]]; then
    if [[ -n "$manual_notes" ]]; then
      manual_note="$manual_notes"
    else
      manual_note="Manual review confirmed (efficiency, accuracy, duplication, security, ADR conformance)."
    fi
  fi

  # Collect automated blockers only (manual review is NOT a blocker)
  local blockers=()
  if [[ "$typecheck_result" != "PASS" ]]; then
    blockers+=("Typecheck gate: $typecheck_reason")
  fi
  if [[ "$unit_result" != "PASS" ]]; then
    blockers+=("Unit gate: $unit_reason")
  fi
  if [[ "$integration_result" != "PASS" ]]; then
    blockers+=("Integration gate: $integration_reason")
  fi
  if [[ "$uat_result" != "PASS" ]]; then
    blockers+=("UAT gate: $uat_reason")
  fi

  # Three-way verdict: BLOCKED / PASS / PENDING_MANUAL_REVIEW
  local verdict=""
  local qa_state=""
  local recommendations=""
  local unblock_note=""

  if [[ "${#blockers[@]}" -gt 0 ]]; then
    verdict="Blocked"
    qa_state="BLOCKED"
    recommendations="$(printf '%s; ' "${blockers[@]}" | sed 's/; $//')"
    unblock_note="$(printf '%s; ' "${blockers[@]}" | sed 's/; $//')"
  elif [[ "$manual_ok" -eq 1 ]]; then
    verdict="Pass"
    qa_state="PASS"
    recommendations="No blockers identified. Keep tests and evidence attached to issue."
    unblock_note="N/A"
  else
    verdict="Pending Manual Review"
    qa_state="PENDING_MANUAL_REVIEW"
    recommendations="All automated gates passed. Awaiting manual code review (--manual-ok)."
    unblock_note="Complete manual review checklist and re-run with --manual-ok."
  fi

  set_issue_qa_state "$issue_file" "$qa_state"
  append_qa_verification_section \
    "$issue_file" "$issue_id" "$verdict" \
    "$typecheck_result" "$unit_result" "$integration_result" "$uat_result" \
    "$coverage_note" "$manual_note" "$unblock_note" "$recommendations" "$commit_push_note"

  # PENDING_MANUAL_REVIEW suppresses dev notification regardless of emit_dev_message
  if [[ "$emit_dev_message" -eq 1 && "$qa_state" != "PENDING_MANUAL_REVIEW" ]]; then
    local feedback_file="$inbox_dir/$(day_stamp)_$(slugify "${issue_id}_qa_${verdict}")_$(date -u +%H%M%S).md"
    emit_dev_feedback_message "$issue_id" "$verdict" "$qa_state" "$recommendations" "$unblock_note" "$feedback_file"
    log "Wrote QA feedback message: $feedback_file"
  fi

  if [[ "$verdict" == "Pass" && "$approve_mode" -eq 1 ]]; then
    set_issue_qa_state "$issue_file" "PASS"
    set_issue_complete_status "$issue_file"
    if [[ "$dry_run" -eq 1 ]]; then
      log "Dry run: would move $issue_file to $issues_completed_dir/"
    else
      mv "$issue_file" "$issues_completed_dir/"
    fi
    move_related_messages "$issue_id"
    log "Approved and completed $issue_id"
  elif [[ "$verdict" == "Pass" ]]; then
    log "Issue $issue_id passed QA gates. Re-run with --approve to complete."
  elif [[ "$qa_state" == "PENDING_MANUAL_REVIEW" ]]; then
    log "Issue $issue_id: all automated gates passed. Awaiting manual review (--manual-ok to promote)."
  else
    log "Issue $issue_id is BLOCKED. See appended QA Verification section for details."
  fi
}

completion_sweep() {
  # Safety net: any QA: PASS issue still in active/ gets completed and moved
  local f issue_id qa_state
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    qa_state="$(extract_issue_field_value "$f" "QA" | tr '[:lower:]' '[:upper:]')"
    if [[ "$qa_state" == "PASS" && "$approve_mode" -eq 1 ]]; then
      issue_id="$(extract_issue_id_from_file "$f")"
      local commit_push_status="" commit_push_note="" commit_ref=""
      resolve_commit_push_evidence "$f" "$issue_id" commit_push_status commit_push_note commit_ref
      if [[ "$commit_push_status" != "verified" ]]; then
        log "Completion sweep: skipping $issue_id because commit/push evidence is missing ($commit_push_note)."
        continue
      fi
      log "Completion sweep: moving PASS issue $issue_id to completed/"
      set_issue_complete_status "$f"
      if [[ "$dry_run" -eq 0 ]]; then
        mv "$f" "$issues_completed_dir/"
      fi
      if [[ "$emit_dev_message" -eq 1 ]]; then
        local feedback_file="$inbox_dir/$(day_stamp)_$(slugify "${issue_id}_qa_Pass")_$(date -u +%H%M%S).md"
        emit_dev_feedback_message "$issue_id" "Pass" "PASS" "Completed via sweep." "N/A" "$feedback_file"
      fi
      move_related_messages "$issue_id"
    fi
  done < <(find "$issues_active_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null || true)
}

process_cycle() {
  log "Polling QA-ready items for team=$team_id role=$role_id project=$project_name"

  # Crash recovery: reset stale IN_PROGRESS issues to PENDING
  reset_stale_in_progress

  local inbox_hits
  inbox_hits="$(find "$inbox_dir" -maxdepth 1 -type f -name '*.md' -exec grep -Eil "$ready_regex" {} + 2>/dev/null || true)"

  if [[ -n "$inbox_hits" ]]; then
    log "QA-ready inbox markers detected:"
    while IFS= read -r file; do
      [[ -n "$file" ]] && log "  - $file"
    done <<<"$inbox_hits"
  else
    log "No QA-ready markers found in inbox."
  fi

  local candidate_files
  candidate_files="$(discover_qa_ready_issue_files || true)"
  if [[ -z "$candidate_files" ]]; then
    log "No QA-ready issues found in active queue."
    return 0
  fi

  local stale_pending_files stale_pending_issue_ids stale_pending_backlog=0
  stale_pending_files="$(stale_pending_manual_review_files || true)"
  if [[ -n "$stale_pending_files" ]]; then
    stale_pending_backlog=1
    stale_pending_issue_ids="$(while IFS= read -r f; do
      [[ -n "$f" ]] && extract_issue_id_from_file "$f"
    done <<<"$stale_pending_files" | paste -sd ', ' -)"
    log "Autonomous guardrail: stale PENDING_MANUAL_REVIEW backlog detected (${pending_manual_review_sla_minutes}m SLA): ${stale_pending_issue_ids}"
  fi

  local candidate
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    local issue_id
    issue_id="$(extract_issue_id_from_file "$candidate")"

    if [[ -n "$issue_filter" && "$issue_filter" != "$issue_id" ]]; then
      continue
    fi

    if [[ -z "$issue_filter" ]] && ! issue_has_qa_marker "$candidate" && ! issue_has_ready_inbox_marker "$issue_id"; then
      continue
    fi

    local qa_state
    qa_state="$(extract_issue_field_value "$candidate" "QA" | tr '[:lower:]' '[:upper:]')"

    if [[ "$autonomous" -eq 1 && "$manual_ok" -eq 0 && "$stale_pending_backlog" -eq 1 && -z "$issue_filter" ]]; then
      if [[ "$qa_state" != "PASS" && "$qa_state" != "PENDING_MANUAL_REVIEW" ]]; then
        log "Guardrail deferral: skipping $issue_id while stale manual-review backlog remains unresolved."
        continue
      fi
    fi

    # PASS in active/ — auto-heal: complete immediately without running gates
    if [[ "$qa_state" == "PASS" && "$approve_mode" -eq 1 ]]; then
      local commit_push_status="" commit_push_note="" commit_ref=""
      resolve_commit_push_evidence "$candidate" "$issue_id" commit_push_status commit_push_note commit_ref
      if [[ "$commit_push_status" != "verified" ]]; then
        log "Auto-heal skipped for $issue_id: commit/push evidence missing ($commit_push_note)."
        continue
      fi
      log "Auto-healing $issue_id: QA PASS still in active/, completing now."
      set_issue_complete_status "$candidate"
      if [[ "$dry_run" -eq 0 ]]; then
        mv "$candidate" "$issues_completed_dir/"
      fi
      move_related_messages "$issue_id"
      continue
    fi

    # PENDING_MANUAL_REVIEW — skip gates, only promote if --manual-ok
    if [[ "$qa_state" == "PENDING_MANUAL_REVIEW" ]]; then
      if [[ "$manual_ok" -eq 1 ]]; then
        local commit_push_status="" commit_push_note="" commit_ref=""
        resolve_commit_push_evidence "$candidate" "$issue_id" commit_push_status commit_push_note commit_ref
        if [[ "$commit_push_status" != "verified" ]]; then
          log "Cannot promote $issue_id: commit/push evidence missing ($commit_push_note)."
          set_issue_qa_state "$candidate" "BLOCKED"
          append_qa_verification_section \
            "$candidate" "$issue_id" "Need More Info" \
            "N/A (gates skipped — prior cycle passed)" "N/A" "N/A" "N/A" \
            "Manual promotion blocked because commit/push evidence is missing from the dev handoff." \
            "Manual review could not complete because required commit/push evidence is missing." \
            "Add a commit hash/reference and explicit push statement to the dev response or handoff, then re-handoff." \
            "Manual promotion blocked: dev handoff is missing commit/push evidence required by QA." \
            "$commit_push_note"
          if [[ "$emit_dev_message" -eq 1 ]]; then
            local feedback_file="$inbox_dir/$(day_stamp)_$(slugify "${issue_id}_qa_Need_More_Info")_$(date -u +%H%M%S).md"
            emit_dev_feedback_message "$issue_id" "Need More Info" "BLOCKED" \
              "Manual QA could not complete because commit/push evidence is missing from the dev handoff." \
              "Add a commit hash/reference and explicit push statement, then re-handoff." \
              "$feedback_file"
          fi
          continue
        fi
        log "Promoting $issue_id: PENDING_MANUAL_REVIEW → PASS (--manual-ok confirmed)."
        local promote_manual_note="Manual review confirmed (efficiency, accuracy, duplication, security, ADR conformance)."
        if [[ -n "$manual_notes" ]]; then
          promote_manual_note="$manual_notes"
        fi
        set_issue_qa_state "$candidate" "PASS"
        append_qa_verification_section \
          "$candidate" "$issue_id" "Pass" \
          "N/A (gates skipped — prior cycle passed)" "N/A" "N/A" "N/A" \
          "See prior verification cycle." "$promote_manual_note" "N/A" \
          "Manual review promotion via --manual-ok." "$commit_push_note"
        if [[ "$approve_mode" -eq 1 ]]; then
          set_issue_complete_status "$candidate"
          if [[ "$dry_run" -eq 0 ]]; then
            mv "$candidate" "$issues_completed_dir/"
          fi
          move_related_messages "$issue_id"
          log "Completed $issue_id"
        fi
        if [[ "$emit_dev_message" -eq 1 ]]; then
          local feedback_file="$inbox_dir/$(day_stamp)_$(slugify "${issue_id}_qa_Pass")_$(date -u +%H%M%S).md"
          emit_dev_feedback_message "$issue_id" "Pass" "PASS" "Manual review promotion via --manual-ok." "N/A" "$feedback_file"
        fi
      else
        log "Skipping $issue_id (awaiting manual review, use --manual-ok to promote)."
      fi
      continue
    fi

    # BLOCKED — only recheck with fresh evidence or stale-recheck threshold
    if [[ "$qa_state" == "BLOCKED" ]]; then
      local should_recheck=0
      if has_fresh_dev_evidence "$candidate" "$issue_id"; then
        log "Fresh dev evidence found for BLOCKED $issue_id — re-evaluating."
        should_recheck=1
      elif [[ "$stale_recheck" -eq 1 ]]; then
        local last_qa_epoch
        last_qa_epoch="$(last_qa_verification_epoch "$candidate")"
        local now_epoch
        now_epoch="$(date +%s)"
        local hours_since=$(( (now_epoch - last_qa_epoch) / 3600 ))
        if [[ "$hours_since" -ge "$stale_recheck_hours" ]]; then
          log "Stale-recheck threshold (${stale_recheck_hours}h) reached for BLOCKED $issue_id — re-evaluating."
          should_recheck=1
        fi
      fi
      if [[ "$should_recheck" -eq 0 ]]; then
        log "Skipping BLOCKED $issue_id (no fresh evidence, stale-recheck not reached)."
        continue
      fi
    fi

    # Layer 1: recheck_existing gate for previously reviewed issues
    if [[ "$recheck_existing" -eq 0 ]] && issue_already_reviewed "$candidate" && [[ "$qa_state" != "PENDING" ]]; then
      log "Skipping $issue_id (already has QA Verification; use --recheck-existing to force)."
      continue
    fi

    # Run full evaluation with crash-safe error handling
    evaluate_issue "$candidate" "$issue_id" || {
      log "evaluate_issue failed for $issue_id — will retry next cycle"
      set_issue_qa_state "$candidate" "PENDING"
      continue
    }
  done <<<"$candidate_files"

  # Completion invariant sweep: no QA: PASS should remain in active/
  completion_sweep
}

main() {
  if [[ "$watch_mode" -eq 1 ]]; then
    local prev_snapshot
    local last_change_epoch
    prev_snapshot="$(snapshot_poll_state)"
    last_change_epoch="$(date +%s)"
    while true; do
      process_cycle
      local current_snapshot
      local now_epoch
      local idle_seconds
      current_snapshot="$(snapshot_poll_state)"
      now_epoch="$(date +%s)"

      if [[ "$current_snapshot" == "$prev_snapshot" ]]; then
        idle_seconds=$((now_epoch - last_change_epoch))
        log "No inbox/active issue changes detected (idle=${idle_seconds}s)."
      else
        prev_snapshot="$current_snapshot"
        last_change_epoch="$now_epoch"
      fi

      idle_seconds=$((now_epoch - last_change_epoch))
      if [[ "$idle_stop_seconds" -gt 0 && "$idle_seconds" -ge "$idle_stop_seconds" ]]; then
        log "Idle limit reached (${idle_stop_seconds}s). Stopping watch mode."
        break
      fi

      log "Sleeping ${poll_interval}s before next poll."
      sleep "$poll_interval"
    done
  else
    process_cycle
  fi
}

main
