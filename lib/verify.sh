#!/bin/bash
# Gauntlet - Verification Queue Operations
# Lock-free verification management for the Gauntlet Verify phase
# Mirrors the patterns from lib/review.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(dirname "$SCRIPT_DIR")/state"
VERIFY_DIR="$STATE_DIR/verify"

source "$SCRIPT_DIR/util.sh"

# Initialize verify state directories
init_verify() {
  mkdir -p "$VERIFY_DIR/verifications" \
           "$STATE_DIR/generated-tests" \
           "$(dirname "$SCRIPT_DIR")/output/verified-tests"
}

# Create a new verification item
# Usage: create_verification_item "id" "review_id" "section_id" "persona" "$finding_json" "unit-testable" ["reason"]
create_verification_item() {
  local verify_id="$1"
  local review_id="$2"
  local section_id="$3"
  local persona="$4"
  local finding_json="$5"
  local testability="$6"
  local untestable_reason="${7:-}"

  local verify_file="$VERIFY_DIR/verifications/${verify_id}.json"
  local now=$(timestamp)

  # Don't overwrite existing verification
  if [[ -f "$verify_file" ]]; then
    log_debug "Verification $verify_id already exists"
    return 1
  fi

  # For untestable findings, start at a terminal status so they pass through to report
  local initial_status="pending"
  [[ "$testability" == "untestable" ]] && initial_status="untestable"

  jq -n \
    --arg id "$verify_id" \
    --arg reviewId "$review_id" \
    --arg sectionId "$section_id" \
    --arg persona "$persona" \
    --argjson finding "$finding_json" \
    --arg testability "$testability" \
    --arg untestableReason "$untestable_reason" \
    --arg status "$initial_status" \
    --arg now "$now" \
    '{
      id: $id,
      reviewId: $reviewId,
      sectionId: $sectionId,
      persona: $persona,
      finding: $finding,
      testability: $testability,
      untestableReason: $untestableReason,
      status: $status,
      assignedTo: null,
      testFile: null,
      testName: null,
      testCommand: null,
      testFramework: null,
      testResult: null,
      testOutput: null,
      verdict: null,
      verdictSummary: null,
      verdictReason: null,
      recommendedAction: null,
      manualReviewNeeded: false,
      manualReviewReason: null,
      attempts: 0,
      maxAttempts: 2,
      createdAt: $now,
      updatedAt: $now
    }' > "$verify_file"

  log_debug "Created verification: $verify_id ($testability)"
}

# Claim a verification item atomically (lock-free using mv)
# Usage: claim_verification "agent-id" "generate|verdict"
# Returns: verification ID if successful, empty if none available
claim_verification() {
  local agent_id="$1"
  local phase="${2:-generate}"

  # Each phase targets a different status
  local target_status="pending"
  [[ "$phase" == "verdict" ]] && target_status="verdict_pending"

  for verify_file in $(ls -1 "$VERIFY_DIR/verifications"/*.json 2>/dev/null | sort); do
    local status=$(jq -r '.status' "$verify_file" 2>/dev/null)
    [[ "$status" != "$target_status" ]] && continue

    local verify_id=$(jq -r '.id' "$verify_file")
    local claimed_file="$VERIFY_DIR/verifications/${verify_id}.claimed.json"

    # Atomic move — only the first agent to succeed claims it
    if mv "$verify_file" "$claimed_file" 2>/dev/null; then
      local now=$(timestamp)
      jq --arg agent "$agent_id" --arg now "$now" \
        '.status = "claimed" | .assignedTo = $agent | .updatedAt = $now | .attempts += 1' \
        "$claimed_file" > "$claimed_file.tmp" && mv "$claimed_file.tmp" "$claimed_file"

      # Move back to standard name
      mv "$claimed_file" "$verify_file"

      echo "$verify_id"
      return 0
    fi
  done

  # No verifications available for this phase
  return 1
}

# Update verification status
# Usage: update_verification_status "verify-id" "generating|test_generated|verdict_pending|verifying|completed|failed"
update_verification_status() {
  local verify_id="$1"
  local new_status="$2"
  local verify_file="$VERIFY_DIR/verifications/${verify_id}.json"

  if [[ ! -f "$verify_file" ]]; then
    log_error "Verification $verify_id not found"
    return 1
  fi

  local now=$(timestamp)
  jq --arg status "$new_status" --arg now "$now" \
    '.status = $status | .updatedAt = $now' \
    "$verify_file" > "$verify_file.tmp" && mv "$verify_file.tmp" "$verify_file"
}

# Release a claimed verification back to its pending state (on failure)
# Usage: release_verification "verify-id" "generate|verdict"
release_verification() {
  local verify_id="$1"
  local phase="${2:-generate}"
  local verify_file="$VERIFY_DIR/verifications/${verify_id}.json"

  if [[ ! -f "$verify_file" ]]; then
    log_error "Verification $verify_id not found"
    return 1
  fi

  local attempts=$(jq -r '.attempts' "$verify_file")
  local max_attempts=$(jq -r '.maxAttempts' "$verify_file")
  local now=$(timestamp)

  if (( attempts >= max_attempts )); then
    jq --arg now "$now" \
      '.status = "failed" | .assignedTo = null | .updatedAt = $now | .error = "Max attempts exceeded"' \
      "$verify_file" > "$verify_file.tmp" && mv "$verify_file.tmp" "$verify_file"
    log_warn "Verification $verify_id failed after $max_attempts attempts"
  else
    local release_status="pending"
    [[ "$phase" == "verdict" ]] && release_status="verdict_pending"

    jq --arg status "$release_status" --arg now "$now" \
      '.status = $status | .assignedTo = null | .updatedAt = $now' \
      "$verify_file" > "$verify_file.tmp" && mv "$verify_file.tmp" "$verify_file"
    log_debug "Verification $verify_id released to $release_status (attempt $attempts/$max_attempts)"
  fi
}

# Get verification details
# Usage: get_verification "verify-id"
get_verification() {
  local verify_id="$1"
  local verify_file="$VERIFY_DIR/verifications/${verify_id}.json"

  if [[ -f "$verify_file" ]]; then
    cat "$verify_file"
  else
    log_error "Verification $verify_id not found"
    return 1
  fi
}

# List all verifications with optional status filter
# Usage: list_verifications [status]
list_verifications() {
  local filter_status="$1"

  for verify_file in "$VERIFY_DIR/verifications"/*.json; do
    [[ ! -f "$verify_file" ]] && continue

    if [[ -n "$filter_status" ]]; then
      local status=$(jq -r '.status' "$verify_file")
      [[ "$status" != "$filter_status" ]] && continue
    fi

    jq -c '{id, sectionId, persona, testability, status, verdict}' "$verify_file"
  done | jq -s '.'
}

# Count verifications by phase
# Usage: count_verifications "generate|verdict"
count_verifications() {
  local phase="${1:-generate}"
  local pending=0 active=0 done=0 failed=0

  for verify_file in "$VERIFY_DIR/verifications"/*.json; do
    [[ ! -f "$verify_file" ]] && continue
    local status=$(jq -r '.status' "$verify_file")

    if [[ "$phase" == "generate" ]]; then
      case "$status" in
        pending)                                  ((pending++)) ;;
        claimed|generating)                       ((active++)) ;;
        test_generated|test_run|verdict_pending|verifying|completed) ((done++)) ;;
        failed)                                   ((failed++)) ;;
      esac
    else
      # verdict phase
      case "$status" in
        verdict_pending) ((pending++)) ;;
        verifying)       ((active++)) ;;
        completed)       ((done++)) ;;
        failed)          ((failed++)) ;;
      esac
    fi
  done

  echo "{\"pending\":$pending,\"active\":$active,\"done\":$done,\"failed\":$failed}"
}

# Check if all testable verifications are complete for a phase
# Usage: all_verifications_complete "generate|verdict"
all_verifications_complete() {
  local phase="${1:-generate}"
  local counts
  counts=$(count_verifications "$phase")
  local pending=$(echo "$counts" | jq -r '.pending')
  local active=$(echo "$counts" | jq -r '.active')
  [[ "$pending" == "0" && "$active" == "0" ]]
}

# Look up a verification by finding ID and return the markdown verification block
# Usage: get_verification_block "security-SEC-001-f0"
# Outputs: markdown string (empty if no verification found)
get_verification_block() {
  local finding_id="$1"
  local verify_file="$VERIFY_DIR/verifications/${finding_id}.json"

  [[ ! -f "$verify_file" ]] && return 0

  local testability=$(jq -r '.testability' "$verify_file")
  local verdict=$(jq -r '.verdict // empty' "$verify_file")
  local verdict_summary=$(jq -r '.verdictSummary // empty' "$verify_file")
  local test_name=$(jq -r '.testName // empty' "$verify_file")
  local manual_review=$(jq -r '.manualReviewNeeded // false' "$verify_file")
  local manual_reason=$(jq -r '.manualReviewReason // empty' "$verify_file")

  if [[ "$testability" == "untestable" ]]; then
    local reason=$(jq -r '.untestableReason // "requires human judgment"' "$verify_file")
    printf '**Verification: ⚠️ Requires Manual Verification** — %s\n' "$reason"
  elif [[ -z "$verdict" ]]; then
    printf '**Verification: ⏭️ Not Verified** (below severity threshold or test generation failed)\n'
  elif [[ "$verdict" == "confirmed_vulnerability" ]]; then
    printf '**Verification: ❌ CONFIRMED VULNERABILITY**\n'
    printf '> %s\n' "$verdict_summary"
    if [[ -n "$test_name" ]]; then
      printf '> Test file: `output/verified-tests/%s`\n' "$(basename "$test_name")"
    fi
  elif [[ "$verdict" == "false_positive" ]]; then
    printf '**Verification: ✅ FALSE POSITIVE**\n'
    printf '> %s\n' "$verdict_summary"
  elif [[ "$verdict" == "inconclusive" ]]; then
    printf '**Verification: ⚠️ INCONCLUSIVE**\n'
    printf '> %s\n' "$verdict_summary"
    if [[ "$manual_review" == "true" && -n "$manual_reason" ]]; then
      printf '> Manual review recommended: %s\n' "$manual_reason"
    fi
  fi
}
