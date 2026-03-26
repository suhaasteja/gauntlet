#!/bin/bash
# Gauntlet - Agent Lifecycle Management
# Manages analyzer, triage, scenario-generator, orchestrator, and persona agent instances

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(dirname "$SCRIPT_DIR")/state"
AGENTS_DIR="$STATE_DIR/agents"
LOGS_DIR="$STATE_DIR/logs"

source "$SCRIPT_DIR/util.sh"

# Agent types
AGENT_TYPE_ANALYZER="analyzer"
AGENT_TYPE_TRIAGE="triage"
AGENT_TYPE_SCENARIO="scenario"
AGENT_TYPE_ORCHESTRATOR="orchestrator"
AGENT_TYPE_PERSONA="persona"

# Initialize agent directories
init_agents() {
  mkdir -p "$AGENTS_DIR" "$LOGS_DIR"
}

# Register a new agent
# Usage: register_agent "persona" "engineer-1" ["engineer"]
register_agent() {
  local agent_type="$1"
  local agent_id="$2"
  local persona="${3:-}"
  
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  local now=$(timestamp)
  
  cat > "$agent_file" << EOF
{
  "id": "$agent_id",
  "type": "$agent_type",
  "persona": "$persona",
  "status": "active",
  "currentReview": null,
  "reviewsCompleted": 0,
  "reviewsFailed": 0,
  "startedAt": "$now",
  "lastHeartbeat": "$now",
  "pid": $$
}
EOF
  
  log_debug "Registered agent: $agent_id ($agent_type)"
}

# Update agent heartbeat
# Usage: heartbeat "engineer-1"
heartbeat() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ ! -f "$agent_file" ]]; then
    return 1
  fi
  
  local now=$(timestamp)
  jq_update "$agent_file" --arg now "$now" '.lastHeartbeat = $now'
}

# Update agent's current review
# Usage: set_agent_review "engineer-1" "engineer-SEC-001"
set_agent_review() {
  local agent_id="$1"
  local review_id="$2"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ ! -f "$agent_file" ]]; then
    return 1
  fi
  
  local now=$(timestamp)
  
  if [[ -z "$review_id" || "$review_id" == "null" ]]; then
    jq_update "$agent_file" --arg now "$now" '.currentReview = null | .lastHeartbeat = $now'
  else
    jq_update "$agent_file" --arg review "$review_id" --arg now "$now" \
      '.currentReview = $review | .lastHeartbeat = $now'
  fi
}

# Increment agent review counters
# Usage: agent_review_completed "engineer-1"
# Usage: agent_review_failed "engineer-1"
agent_review_completed() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ -f "$agent_file" ]]; then
    jq_update "$agent_file" '.reviewsCompleted += 1 | .currentReview = null'
  fi
}

agent_review_failed() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ -f "$agent_file" ]]; then
    jq_update "$agent_file" '.reviewsFailed += 1 | .currentReview = null'
  fi
}

# Deregister an agent
# Usage: deregister_agent "engineer-1"
deregister_agent() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ -f "$agent_file" ]]; then
    local now=$(timestamp)
    jq_update "$agent_file" --arg now "$now" '.status = "stopped" | .stoppedAt = $now'
    log_debug "Deregistered agent: $agent_id"
  fi
}

# Get agent info
# Usage: get_agent "engineer-1"
get_agent() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ -f "$agent_file" ]]; then
    cat "$agent_file"
  else
    return 1
  fi
}

# List all agents by type
# Usage: list_agents [type]
list_agents() {
  local filter_type="$1"
  
  for agent_file in "$AGENTS_DIR"/*.json; do
    [[ ! -f "$agent_file" ]] && continue
    
    if [[ -n "$filter_type" ]]; then
      local type=$(jq -r '.type' "$agent_file")
      [[ "$type" != "$filter_type" ]] && continue
    fi
    
    jq -c '{id, type, persona, status, currentReview, reviewsCompleted}' "$agent_file"
  done | jq -s '.'
}

# Count active agents by type
# Usage: count_active_agents "persona"
count_active_agents() {
  local agent_type="$1"
  local count=0
  
  for agent_file in "$AGENTS_DIR"/*.json; do
    [[ ! -f "$agent_file" ]] && continue
    
    local type=$(jq -r '.type' "$agent_file")
    local status=$(jq -r '.status' "$agent_file")
    
    if [[ "$type" == "$agent_type" && "$status" == "active" ]]; then
      ((count++))
    fi
  done
  
  echo "$count"
}

# Generate next agent ID for a type
# Usage: next_agent_id "engineer" -> "engineer-3"
next_agent_id() {
  local agent_type="$1"
  local max_num=0
  
  for agent_file in "$AGENTS_DIR"/${agent_type}-*.json; do
    [[ ! -f "$agent_file" ]] && continue
    local id=$(basename "$agent_file" .json)
    local num=${id#${agent_type}-}
    (( num > max_num )) && max_num=$num
  done
  
  echo "${agent_type}-$((max_num + 1))"
}

# Log to agent's log file
# Usage: agent_log "engineer-1" "Started review of SEC-001"
agent_log() {
  local agent_id="$1"
  local message="$2"
  local log_file="$LOGS_DIR/${agent_id}.log"
  local timestamp=$(timestamp)
  
  echo "[$timestamp] $message" >> "$log_file"
}

# Check for stale agents (no heartbeat in X seconds)
# Usage: check_stale_agents 300
check_stale_agents() {
  local timeout_seconds="${1:-300}"
  local now=$(date +%s)
  local stale_agents=()
  
  for agent_file in "$AGENTS_DIR"/*.json; do
    [[ ! -f "$agent_file" ]] && continue
    
    local status=$(jq -r '.status' "$agent_file")
    [[ "$status" != "active" ]] && continue
    
    local last_heartbeat=$(jq -r '.lastHeartbeat' "$agent_file")
    local heartbeat_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_heartbeat" +%s 2>/dev/null || echo 0)
    local age=$((now - heartbeat_epoch))
    
    if (( age > timeout_seconds )); then
      local agent_id=$(jq -r '.id' "$agent_file")
      stale_agents+=("$agent_id")
    fi
  done
  
  printf '%s\n' "${stale_agents[@]}"
}

# Clean up stale agents and release their reviews
# Usage: cleanup_stale_agents 300
cleanup_stale_agents() {
  local timeout_seconds="${1:-300}"
  
  source "$(dirname "${BASH_SOURCE[0]}")/review.sh"
  
  for agent_id in $(check_stale_agents "$timeout_seconds"); do
    local agent_file="$AGENTS_DIR/${agent_id}.json"
    local current_review=$(jq -r '.currentReview // empty' "$agent_file")
    
    # Release the review if agent had one
    if [[ -n "$current_review" ]]; then
      release_review "$current_review"
      log_warn "Released review $current_review from stale agent $agent_id"
    fi
    
    # Mark agent as stale
    jq_update "$agent_file" '.status = "stale"'
    log_warn "Marked agent $agent_id as stale"
  done
}
