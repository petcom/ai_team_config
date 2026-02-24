#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ai_team_config/scripts/qa_poll_cycle.sh [options]

Poll QA-ready items and run QA gate verification for frontend_qa/backend_qa roles.

Options:
  --repo-root PATH          Project root (default: current directory)
  --team TEAM               Team id (frontend|backend). Auto-detected from active-role.json if omitted.
  --role ROLE               Role id (frontend-qa|backend-qa). Auto-detected from active-role.json if omitted.
  --interval SECONDS        Poll interval when --watch is used (default: 240)
  --watch                   Run continuously
  --once                    Run a single poll cycle (default)
  --approve                 If gates pass, set issue to COMPLETE and move active -> completed
  --manual-ok               Confirm manual code review is complete for this run
  --manual-notes TEXT       Manual review notes appended to QA evidence
  --issue ISSUE_ID          Evaluate only one issue id (for example UI-ISS-190)
  --recheck-existing        Re-run QA on issues that already have QA Verification entries
  --emit-dev-message        Write QA pass/blocked messages to team inbox (default)
  --no-emit-dev-message     Do not write QA pass/blocked messages
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
watch_mode=0
approve_mode=0
manual_ok=0
manual_notes=""
issue_filter=""
recheck_existing=0
emit_dev_message=1
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) repo_root="$2"; shift 2 ;;
    --team) team_id="$2"; shift 2 ;;
    --role) role_id="$2"; shift 2 ;;
    --interval) poll_interval="$2"; shift 2 ;;
    --watch) watch_mode=1; shift 1 ;;
    --once) watch_mode=0; shift 1 ;;
    --approve) approve_mode=1; shift 1 ;;
    --manual-ok) manual_ok=1; shift 1 ;;
    --manual-notes) manual_notes="$2"; shift 2 ;;
    --issue) issue_filter="$2"; shift 2 ;;
    --recheck-existing) recheck_existing=1; shift 1 ;;
    --emit-dev-message) emit_dev_message=1; shift 1 ;;
    --no-emit-dev-message) emit_dev_message=0; shift 1 ;;
    --dry-run) dry_run=1; shift 1 ;;
    --help|-h) usage; exit 0 ;;
    *) err "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if ! [[ "$poll_interval" =~ ^[0-9]+$ ]]; then
  err "--interval must be a positive integer"
  exit 1
fi

repo_root="$(cd "$repo_root" && pwd)"
active_role_file="$repo_root/active-role.json"

if [[ -z "$role_id" || -z "$team_id" ]]; then
  if [[ -f "$active_role_file" ]]; then
    detected_role="$(extract_json_field "$active_role_file" "role_id" || true)"
    detected_team="$(extract_json_field "$active_role_file" "team_id" || true)"
    role_id="${role_id:-$detected_role}"
    team_id="${team_id:-$detected_team}"
  fi
fi

if [[ -z "$team_id" && -n "$role_id" ]]; then
  team_id="${role_id%%-*}"
fi

if [[ -z "$role_id" || -z "$team_id" ]]; then
  err "Could not resolve role/team. Provide --role and --team or set active-role.json."
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

ready_regex='Development Complete|Awaiting QA|QA Ready|Ready for QA'
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

  log "Running $gate gate: $cmd"
  if (cd "$repo_root" && eval "$cmd") >"$log_file" 2>&1; then
    printf -v "$result_var" "PASS"
    printf -v "$reason_var" "$cmd"
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

  local qa_state
  qa_state="$(extract_issue_field_value "$issue_file" "QA" | tr '[:lower:]' '[:upper:]')"
  [[ "$qa_state" == "PENDING" ]]
}

issue_already_reviewed() {
  local issue_file="$1"
  grep -Eq '^## QA Verification \(' "$issue_file"
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

  printf '%s\n' "${issue_files[@]}" | awk 'NF' | sort -u
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
  if [[ "$manual_ok" -ne 1 ]]; then
    blockers+=("Manual QA review not confirmed. Re-run with --manual-ok after completing code review checklist.")
  fi

  local verdict="Blocked"
  local qa_state="BLOCKED"
  local recommendations="Address failed gates and attach evidence in issue QA section."
  local unblock_note="All required QA gates pass and manual review is completed."
  if [[ "${#blockers[@]}" -eq 0 ]]; then
    verdict="Pass"
    qa_state="PASS"
    recommendations="No blockers identified. Keep tests and evidence attached to issue."
    unblock_note="N/A"
  else
    recommendations="$(printf '%s; ' "${blockers[@]}" | sed 's/; $//')"
    unblock_note="$(printf '%s; ' "${blockers[@]}" | sed 's/; $//')"
  fi

  set_issue_qa_state "$issue_file" "$qa_state"
  append_qa_verification_section \
    "$issue_file" "$issue_id" "$verdict" \
    "$typecheck_result" "$unit_result" "$integration_result" "$uat_result" \
    "$coverage_note" "$manual_note" "$unblock_note" "$recommendations"

  if [[ "$emit_dev_message" -eq 1 ]]; then
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
  else
    log "Issue $issue_id is BLOCKED. See appended QA Verification section for details."
  fi
}

process_cycle() {
  log "Polling QA-ready items for team=$team_id role=$role_id project=$project_name"

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

  local candidate
  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    local issue_id
    issue_id="$(extract_issue_id_from_file "$candidate")"

    if [[ -n "$issue_filter" && "$issue_filter" != "$issue_id" ]]; then
      continue
    fi

    if [[ -z "$issue_filter" ]] && ! issue_has_qa_marker "$candidate"; then
      continue
    fi

    if [[ "$recheck_existing" -eq 0 ]] && issue_already_reviewed "$candidate"; then
      log "Skipping $issue_id (already has QA Verification; use --recheck-existing to force)."
      continue
    fi

    evaluate_issue "$candidate" "$issue_id"
  done <<<"$candidate_files"
}

main() {
  if [[ "$watch_mode" -eq 1 ]]; then
    while true; do
      process_cycle
      log "Sleeping ${poll_interval}s before next poll."
      sleep "$poll_interval"
    done
  else
    process_cycle
  fi
}

main
