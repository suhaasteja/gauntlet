#!/bin/bash
# Gauntlet - Review Queue Operations
# Lock-free review management using filesystem atomic operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(dirname "$SCRIPT_DIR")/state"
REVIEWS_DIR="$STATE_DIR/reviews"

source "$SCRIPT_DIR/util.sh"

# Initialize review directory
init_reviews() {
  mkdir -p "$REVIEWS_DIR"
}

# Create a new review item (persona × section pair)
# Usage: create_review_item "engineer-SEC-001" "SEC-001" "engineer" 1 3
create_review_item() {
  local review_id="$1"
  local section_id="$2"
  local persona="$3"
  local round="$4"
  local priority="${5:-5}"
  
  local review_file="$REVIEWS_DIR/${review_id}.json"
  local now=$(timestamp)
  
  # Don't overwrite existing review
  if [[ -f "$review_file" ]]; then
    log_debug "Review $review_id already exists"
    return 1
  fi
  
  cat > "$review_file" << EOF
{
  "id": "$review_id",
  "sectionId": "$section_id",
  "persona": "$persona",
  "round": $round,
  "priority": $priority,
  "status": "pending",
  "assignedTo": null,
  "findings": [],
  "summary": null,
  "feasibilityScore": null,
  "attempts": 0,
  "maxAttempts": 3,
  "createdAt": "$now",
  "updatedAt": "$now"
}
EOF
  
  log_debug "Created review: $review_id"
}

# Claim a review atomically (lock-free using mv)
# Usage: claim_review "engineer-1"
# Returns: review ID if successful, empty if no reviews available
claim_review() {
  local agent_id="$1"
  
  # Find pending reviews sorted by priority
  for review_file in $(ls -1 "$REVIEWS_DIR"/*.json 2>/dev/null | sort); do
    # Skip if not a pending review
    local status=$(jq -r '.status' "$review_file" 2>/dev/null)
    [[ "$status" != "pending" ]] && continue
    
    # Try to claim using atomic rename
    local review_id=$(jq -r '.id' "$review_file")
    local claimed_file="$REVIEWS_DIR/${review_id}.claimed.json"
    
    # Atomic move - fails if another agent claimed first
    if mv "$review_file" "$claimed_file" 2>/dev/null; then
      # Update review status
      local now=$(timestamp)
      jq --arg agent "$agent_id" --arg now "$now" \
        '.status = "claimed" | .assignedTo = $agent | .updatedAt = $now | .attempts += 1' \
        "$claimed_file" > "$claimed_file.tmp" && mv "$claimed_file.tmp" "$claimed_file"
      
      # Move back to standard name
      mv "$claimed_file" "$review_file"
      
      echo "$review_id"
      return 0
    fi
  done
  
  # No reviews available
  return 1
}

# Update review status
# Usage: update_review_status "engineer-SEC-001" "in_progress|completed|failed" ["error message"]
update_review_status() {
  local review_id="$1"
  local new_status="$2"
  local error_msg="${3:-}"
  local review_file="$REVIEWS_DIR/${review_id}.json"
  
  if [[ ! -f "$review_file" ]]; then
    log_error "Review $review_id not found"
    return 1
  fi
  
  local now=$(timestamp)
  
  if [[ -n "$error_msg" ]]; then
    jq --arg status "$new_status" --arg now "$now" --arg err "$error_msg" \
      '.status = $status | .updatedAt = $now | .error = $err' \
      "$review_file" > "$review_file.tmp" && mv "$review_file.tmp" "$review_file"
  else
    jq --arg status "$new_status" --arg now "$now" \
      '.status = $status | .updatedAt = $now' \
      "$review_file" > "$review_file.tmp" && mv "$review_file.tmp" "$review_file"
  fi
}

# Release a claimed review (on failure/timeout)
# Usage: release_review "engineer-SEC-001"
release_review() {
  local review_id="$1"
  local review_file="$REVIEWS_DIR/${review_id}.json"
  
  if [[ ! -f "$review_file" ]]; then
    log_error "Review $review_id not found"
    return 1
  fi
  
  local attempts=$(jq -r '.attempts' "$review_file")
  local max_attempts=$(jq -r '.maxAttempts' "$review_file")
  local now=$(timestamp)
  
  if (( attempts >= max_attempts )); then
    # Mark as failed after max attempts
    jq --arg now "$now" \
      '.status = "failed" | .assignedTo = null | .updatedAt = $now | .error = "Max attempts exceeded"' \
      "$review_file" > "$review_file.tmp" && mv "$review_file.tmp" "$review_file"
    log_warn "Review $review_id failed after $max_attempts attempts"
  else
    # Release back to pending
    jq --arg now "$now" \
      '.status = "pending" | .assignedTo = null | .updatedAt = $now' \
      "$review_file" > "$review_file.tmp" && mv "$review_file.tmp" "$review_file"
    log_debug "Review $review_id released (attempt $attempts of $max_attempts)"
  fi
}

# Get review details
# Usage: get_review "engineer-SEC-001"
get_review() {
  local review_id="$1"
  local review_file="$REVIEWS_DIR/${review_id}.json"
  
  if [[ -f "$review_file" ]]; then
    cat "$review_file"
  else
    log_error "Review $review_id not found"
    return 1
  fi
}

# List all reviews with optional status filter
# Usage: list_reviews [status]
list_reviews() {
  local filter_status="$1"
  
  for review_file in "$REVIEWS_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    
    if [[ -n "$filter_status" ]]; then
      local status=$(jq -r '.status' "$review_file")
      [[ "$status" != "$filter_status" ]] && continue
    fi
    
    jq -c '{id, sectionId, persona, round, status, priority, assignedTo}' "$review_file"
  done | jq -s 'sort_by(.priority)'
}

# Count reviews by status
# Usage: count_reviews
count_reviews() {
  local pending=0 claimed=0 in_progress=0 completed=0 failed=0
  
  for review_file in "$REVIEWS_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    local status=$(jq -r '.status' "$review_file")
    case "$status" in
      pending) ((pending++)) ;;
      claimed) ((claimed++)) ;;
      in_progress) ((in_progress++)) ;;
      completed) ((completed++)) ;;
      failed) ((failed++)) ;;
    esac
  done
  
  echo "{\"pending\":$pending,\"claimed\":$claimed,\"in_progress\":$in_progress,\"completed\":$completed,\"failed\":$failed}"
}

# Check if all reviews are complete
# Usage: all_reviews_complete && echo "Done!"
all_reviews_complete() {
  local counts=$(count_reviews)
  local pending=$(echo "$counts" | jq -r '.pending')
  local claimed=$(echo "$counts" | jq -r '.claimed')
  local in_progress=$(echo "$counts" | jq -r '.in_progress')
  
  [[ "$pending" == "0" && "$claimed" == "0" && "$in_progress" == "0" ]]
}

# Update review with findings
# Usage: update_review_findings "engineer-SEC-001" "$findings_json" "$summary" 7
update_review_findings() {
  local review_id="$1"
  local findings_json="$2"
  local summary="$3"
  local feasibility_score="$4"
  local review_file="$REVIEWS_DIR/${review_id}.json"
  
  if [[ ! -f "$review_file" ]]; then
    log_error "Review $review_id not found"
    return 1
  fi
  
  local now=$(timestamp)
  
  # Create temp file with findings
  jq --argjson findings "$findings_json" \
     --arg summary "$summary" \
     --arg score "$feasibility_score" \
     --arg now "$now" \
     '.findings = $findings | .summary = $summary | .feasibilityScore = ($score | tonumber) | .reviewedAt = $now | .updatedAt = $now' \
     "$review_file" > "$review_file.tmp" && mv "$review_file.tmp" "$review_file"
}
