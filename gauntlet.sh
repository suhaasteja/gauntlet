#!/bin/bash
# Gauntlet - PRD Red-Teaming CLI Tool
# Multi-persona adversarial PRD review system
#
# Usage: ./gauntlet.sh [options]
#   --prd FILE              Path to PRD document
#   --codebase DIR          Path to codebase root
#   --personas LIST         Comma-separated personas (default: all)
#   --tool amp|claude       AI tool to use (default: amp)
#   --max-rounds N          Maximum review rounds (default: 3)
#   --parallel N            Max parallel agents (default: 4)
#   --risk-threshold N      Min risk score for deep review (default: 3)
#   --output DIR            Report output directory (default: ./output)

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/state"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
LIB_DIR="$SCRIPT_DIR/lib"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Defaults
TOOL="claude"
MODEL="claude-sonnet"
MAX_ROUNDS=3
MAX_PARALLEL=4
RISK_THRESHOLD=3
PRD_PATH=""
CODEBASE_PATH="."
PERSONAS="engineer,qa,pm,ux,security,devops"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --prd)
      PRD_PATH="$2"
      shift 2
      ;;
    --prd=*)
      PRD_PATH="${1#*=}"
      shift
      ;;
    --codebase)
      CODEBASE_PATH="$2"
      shift 2
      ;;
    --codebase=*)
      CODEBASE_PATH="${1#*=}"
      shift
      ;;
    --personas)
      PERSONAS="$2"
      shift 2
      ;;
    --personas=*)
      PERSONAS="${1#*=}"
      shift
      ;;
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --model=*)
      MODEL="${1#*=}"
      shift
      ;;
    --max-rounds)
      MAX_ROUNDS="$2"
      shift 2
      ;;
    --max-rounds=*)
      MAX_ROUNDS="${1#*=}"
      shift
      ;;
    --parallel)
      MAX_PARALLEL="$2"
      shift 2
      ;;
    --parallel=*)
      MAX_PARALLEL="${1#*=}"
      shift
      ;;
    --risk-threshold)
      RISK_THRESHOLD="$2"
      shift 2
      ;;
    --risk-threshold=*)
      RISK_THRESHOLD="${1#*=}"
      shift
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --output=*)
      OUTPUT_DIR="${1#*=}"
      shift
      ;;
    --help|-h)
      echo "Gauntlet - PRD Red-Teaming CLI Tool"
      echo ""
      echo "Usage: ./gauntlet.sh [options]"
      echo ""
      echo "Options:"
      echo "  --prd FILE              Path to PRD document"
      echo "  --codebase DIR          Path to codebase root (default: .)"
      echo "  --personas LIST         Comma-separated (default: all)"
      echo "  --tool amp|claude       AI tool to use (default: claude)"
      echo "  --model MODEL           AI model to use (default: claude-sonnet)"
      echo "  --max-rounds N          Max review rounds (default: 3)"
      echo "  --parallel N            Max parallel agents (default: 4)"
      echo "  --risk-threshold N      Min risk score for deep review (default: 3)"
      echo "  --output DIR            Report output dir (default: ./output)"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

# Validate PRD path
if [[ -z "$PRD_PATH" ]]; then
  echo "Error: --prd is required"
  echo "Usage: ./gauntlet.sh --prd path/to/prd.md --codebase path/to/code"
  exit 1
fi

if [[ ! -f "$PRD_PATH" ]]; then
  echo "Error: PRD file not found: $PRD_PATH"
  exit 1
fi

# Source libraries
source "$LIB_DIR/util.sh"
source "$LIB_DIR/agent.sh"
source "$LIB_DIR/review.sh"
source "$LIB_DIR/report.sh"

# Check dependencies
check_jq

# =============================================================================
# Initialization
# =============================================================================

init_state() {
  log_info "Initializing Gauntlet state..."
  
  mkdir -p "$STATE_DIR/prd-sections" "$STATE_DIR/scenarios" "$STATE_DIR/reviews" \
           "$STATE_DIR/agents" "$STATE_DIR/rounds" "$STATE_DIR/logs" "$OUTPUT_DIR"
  
  log_success "State initialized."
}

# =============================================================================
# Agent Runners
# =============================================================================

run_analyzer() {
  local analyzer_id="analyzer-1"
  
  echo ""
  separator
  echo "  Running Analyzer Agent"
  separator
  
  register_agent "analyzer" "$analyzer_id"
  agent_log "$analyzer_id" "Starting PRD analysis"
  
  # Read PRD content
  local prd_content=$(cat "$PRD_PATH")
  
  # Build context
  local context=$(cat << EOF
# PRD Analysis Task

## PRD Document
Path: $PRD_PATH

## PRD Content
$prd_content

## Your Task
Split this PRD into logical sections and create JSON files in state/prd-sections/.

EOF
)
  
  # Run the AI tool
  local prompt_file="$PROMPTS_DIR/analyzer.md"
  local output
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(cd "$SCRIPT_DIR" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --model "$MODEL" --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(cd "$SCRIPT_DIR" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --model "$MODEL" --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  agent_log "$analyzer_id" "Analysis complete"
  heartbeat "$analyzer_id"
  deregister_agent "$analyzer_id"
  
  # Check for completion signal
  if echo "$output" | grep -q "<gauntlet>ANALYSIS_COMPLETE</gauntlet>"; then
    # Extract JSON array from output (between ```json and the next ```)
    local sections_json=$(echo "$output" | extract_json_block)
    
    if [[ -n "$sections_json" ]] && echo "$sections_json" | jq empty 2>/dev/null; then
      # Parse JSON and create individual section files
      echo "$sections_json" | jq -c ".[]" 2>/dev/null | while read -r section; do
        local section_id=$(echo "$section" | jq -r ".id")
        echo "$section" | jq . > "$STATE_DIR/prd-sections/${section_id}.json"
        log_debug "Created section file: ${section_id}.json"
      done
      
      local section_count=$(ls -1 "$STATE_DIR/prd-sections"/*.json 2>/dev/null | wc -l | xargs)
      log_success "Analyzer: Created $section_count PRD sections"
      return 0
    else
      log_error "Analyzer: Could not extract valid JSON from output"
      log_debug "Extracted JSON: $sections_json"
      return 1
    fi
  else
    log_error "Analyzer: No completion signal detected"
    return 1
  fi
}

run_triage() {
  local triage_id="triage-1"
  
  echo ""
  separator
  echo "  Running Triage Agent"
  separator
  
  register_agent "triage" "$triage_id"
  agent_log "$triage_id" "Starting risk assessment"
  
  # Build context
  local context=$(cat << EOF
# Triage Task

## Codebase Path
$CODEBASE_PATH

## PRD Sections
$(for f in "$STATE_DIR/prd-sections"/*.json; do [[ -f "$f" ]] && cat "$f"; done | jq -s .)

## Your Task
Score each section by risk (1-5) and update the section files with riskScore and riskFactors.

EOF
)
  
  # Run the AI tool
  local prompt_file="$PROMPTS_DIR/triage.md"
  local output
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(cd "$CODEBASE_PATH" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --model "$MODEL" --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(cd "$CODEBASE_PATH" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --model "$MODEL" --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  agent_log "$triage_id" "Triage complete"
  heartbeat "$triage_id"
  deregister_agent "$triage_id"
  
  if echo "$output" | grep -q "<gauntlet>TRIAGE_COMPLETE</gauntlet>"; then
    # Extract JSON array from output (between ```json and the next ```)
    local triage_json=$(echo "$output" | extract_json_block)
    
    if [[ -n "$triage_json" ]] && echo "$triage_json" | jq empty 2>/dev/null; then
      # Parse JSON and update section files with risk scores
      echo "$triage_json" | jq -c ".[]" 2>/dev/null | while read -r risk_data; do
        local section_id=$(echo "$risk_data" | jq -r ".id")
        local section_file="$STATE_DIR/prd-sections/${section_id}.json"
        
        if [[ -f "$section_file" ]]; then
          local risk_score=$(echo "$risk_data" | jq -r ".riskScore")
          local risk_factors=$(echo "$risk_data" | jq -c ".riskFactors")
          
          # Update section file with risk data
          jq --argjson score "$risk_score" --argjson factors "$risk_factors" \
".riskScore = \$score | .riskFactors = \$factors" \
            "$section_file" > "$section_file.tmp" && mv "$section_file.tmp" "$section_file"
          
          log_debug "Updated ${section_id} with risk score: $risk_score"
        fi
      done
      
      log_success "Triage: Risk scores assigned"
      return 0
    else
      log_error "Triage: Could not extract valid JSON from output"
      log_debug "Extracted JSON: $triage_json"
      return 1
    fi
  else
    log_error "Triage: No completion signal detected"
    return 1
  fi
}

run_scenario_generator() {
  local section_id="$1"
  local gen_id="scenario-gen-${section_id}"
  
  log_info "Generating scenarios for $section_id"
  
  register_agent "scenario" "$gen_id"
  agent_log "$gen_id" "Generating scenarios for $section_id"
  
  # Get section details
  local section_file="$STATE_DIR/prd-sections/${section_id}.json"
  if [[ ! -f "$section_file" ]]; then
    log_error "Section file not found: $section_file"
    return 1
  fi
  
  local section_content=$(cat "$section_file")
  
  # Build context
  local context=$(cat << EOF
# Scenario Generation Task

## PRD Section
$section_content

## Your Task
Generate 5-10 adversarial stress-test scenarios for this section.
Write the output to state/scenarios/${section_id}-scenarios.json

EOF
)
  
  # Run the AI tool
  local prompt_file="$PROMPTS_DIR/scenario-generator.md"
  local output
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(cd "$SCRIPT_DIR" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --model "$MODEL" --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(cd "$SCRIPT_DIR" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --model "$MODEL" --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  agent_log "$gen_id" "Scenarios generated for $section_id"
  heartbeat "$gen_id"
  deregister_agent "$gen_id"
  
  if echo "$output" | grep -q "<gauntlet>SCENARIOS_GENERATED</gauntlet>"; then
    # Extract JSON from output
    local scenario_json=$(echo "$output" | extract_json_block)
    
    if [[ -n "$scenario_json" ]] && echo "$scenario_json" | jq empty 2>/dev/null; then
      echo "$scenario_json" | jq . > "$STATE_DIR/scenarios/${section_id}-scenarios.json"
      log_success "Scenario generator: Created scenarios for $section_id"
    else
      log_warn "Scenario generator: Could not extract JSON for $section_id"
    fi
    return 0
  fi
}

run_persona_review() {
  local worker_num="$1"
  local persona_id="persona-$worker_num"
  
  subseparator
  log_info "Persona agent $persona_id starting"
  
  register_agent "persona" "$persona_id"
  agent_log "$persona_id" "Starting review"
  
  # Try to claim a review
  local review_id=$(claim_review "$persona_id")
  
  if [[ -z "$review_id" ]]; then
    log_debug "Persona $persona_id: No reviews available"
    agent_log "$persona_id" "No reviews available"
    deregister_agent "$persona_id"
    return 0
  fi
  
  log_info "Persona $persona_id: Claimed review $review_id"
  set_agent_review "$persona_id" "$review_id"
  agent_log "$persona_id" "Claimed review: $review_id"
  
  # Update review status
  update_review_status "$review_id" "in_progress"
  
  # Get review details
  local review_json=$(get_review "$review_id")
  local section_id=$(echo "$review_json" | jq -r ".sectionId")
  local persona=$(echo "$review_json" | jq -r ".persona")
  
  # Get section content
  local section_file="$STATE_DIR/prd-sections/${section_id}.json"
  local section_content=$(cat "$section_file" 2>/dev/null || echo "{}")
  
  # Get scenarios if they exist
  local scenarios_file="$STATE_DIR/scenarios/${section_id}-scenarios.json"
  local scenarios_content=""
  if [[ -f "$scenarios_file" ]]; then
    scenarios_content=$(cat "$scenarios_file")
  fi
  
  # Build context
  local context=$(cat << EOF
# Review Task

## Your Assignment
Review ID: $review_id
Persona: $persona
Section: $section_id

## PRD Section
$section_content

## Scenarios to Test Against
$scenarios_content

## Codebase Path
$CODEBASE_PATH

## Your Task
Review this PRD section from your persona perspective. Explore the codebase, test against scenarios, and document findings.

EOF
)
  
  # Run the AI tool with persona prompt
  local prompt_file="$PROMPTS_DIR/personas/${persona}.md"
  local output
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(cd "$CODEBASE_PATH" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --model "$MODEL" --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(cd "$CODEBASE_PATH" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --model "$MODEL" --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  heartbeat "$persona_id"
  
  # Parse persona result
  if echo "$output" | grep -q "<gauntlet>REVIEW_COMPLETE:${section_id}:${persona}</gauntlet>"; then
    # Extract findings JSON from output
    local findings_json=$(echo "$output" | extract_json_block)
    
    if [[ -n "$findings_json" ]] && echo "$findings_json" | jq empty 2>/dev/null; then
      # Save findings to review file
      local review_file="$STATE_DIR/reviews/${review_id}.json"
      if [[ -f "$review_file" ]]; then
        local feasibility=$(echo "$findings_json" | jq -r ".feasibilityScore // 0")
        local findings=$(echo "$findings_json" | jq -c ".findings // []")
        local summary=$(echo "$findings_json" | jq -r ".summary // empty")
        
        jq --argjson score "$feasibility" --argjson findings "$findings" --arg summary "$summary" \
".feasibilityScore = \$score | .findings = \$findings | .summary = \$summary" \
          "$review_file" > "$review_file.tmp" && mv "$review_file.tmp" "$review_file"
      fi
    else
      log_warn "Persona $persona_id: Could not extract JSON from review output"
    fi
    
    log_success "Persona $persona_id: Review $review_id COMPLETED"
    update_review_status "$review_id" "completed"
    agent_review_completed "$persona_id"
    agent_log "$persona_id" "Completed review: $review_id"
    
  elif echo "$output" | grep -q "<gauntlet>REVIEW_FAILED:${section_id}:${persona}"; then
    local reason=$(echo "$output" | grep -o "<gauntlet>REVIEW_FAILED:${section_id}:${persona}:[^<]*</gauntlet>" | sed "s/<gauntlet>REVIEW_FAILED:${section_id}:${persona}:\([^<]*\)<\/gauntlet>/\1/")
    log_warn "Persona $persona_id: Review $review_id FAILED - $reason"
    agent_review_failed "$persona_id"
    agent_log "$persona_id" "Failed review: $review_id - $reason"
    release_review "$review_id"
    
  else
    # No clear signal - treat as incomplete, release review
    log_warn "Persona $persona_id: Review $review_id - no completion signal, releasing"
    agent_log "$persona_id" "No completion signal for: $review_id"
    release_review "$review_id"
  fi
  
  set_agent_review "$persona_id" ""
  deregister_agent "$persona_id"
}

run_orchestrator() {
  local round="$1"
  local orch_id="orchestrator-1"
  
  echo ""
  separator
  echo "  Running Orchestrator - Round $round"
  separator
  
  register_agent "orchestrator" "$orch_id"
  agent_log "$orch_id" "Starting round $round evaluation"
  
  # Build context
  local context=$(cat << EOF
# Orchestrator Task - Round $round

## Configuration
Max Rounds: $MAX_ROUNDS
Current Round: $round

## PRD Sections
$(for f in "$STATE_DIR/prd-sections"/*.json; do [[ -f "$f" ]] && cat "$f"; done | jq -s .)

## All Reviews
$(for f in "$STATE_DIR/reviews"/*.json; do [[ -f "$f" ]] && cat "$f"; done | jq -s .)

## Previous Rounds
$(for f in "$STATE_DIR/rounds"/*.json; do [[ -f "$f" ]] && cat "$f"; done | jq -s .)

## Your Task
Evaluate the current round findings and decide: MORE_ROUNDS, SUFFICIENT, or STUCK.
Create a round summary file in state/rounds/round-${round}.json

EOF
)
  
  # Run the AI tool
  local prompt_file="$PROMPTS_DIR/orchestrator.md"
  local output
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(cd "$SCRIPT_DIR" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --model "$MODEL" --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(cd "$SCRIPT_DIR" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --model "$MODEL" --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  agent_log "$orch_id" "Round $round evaluation complete"
  heartbeat "$orch_id"
  deregister_agent "$orch_id"
  
  # Extract round summary JSON from output
  local round_json
  round_json=$(echo "$output" | extract_json_block)
  
  if [[ -n "$round_json" ]] && echo "$round_json" | jq empty 2>/dev/null; then
    echo "$round_json" | jq . > "$STATE_DIR/rounds/round-${round}.json"
    log_debug "Saved round $round summary"
  fi
  
  # Parse orchestrator decision
  if echo "$output" | grep -q "<gauntlet>SUFFICIENT</gauntlet>"; then
    log_success "Orchestrator: Analysis SUFFICIENT"
    return 0
  elif echo "$output" | grep -q "<gauntlet>STUCK"; then
    log_error "Orchestrator: Analysis STUCK"
    return 2
  elif echo "$output" | grep -q "<gauntlet>MORE_ROUNDS</gauntlet>"; then
    log_info "Orchestrator: MORE_ROUNDS needed"
    return 1
  fi
  
  # Default: continue
  return 1
}

# =============================================================================
# Main Loop
# =============================================================================

main() {
  echo ""
  separator
  echo "  GAUNTLET - PRD Red-Teaming Tool"
  separator
  echo ""
  echo "Configuration:"
  echo "  PRD: $PRD_PATH"
  echo "  Codebase: $CODEBASE_PATH"
  echo "  Personas: $PERSONAS"
  echo "  Tool: $TOOL"
  echo "  Max Rounds: $MAX_ROUNDS"
  echo "  Max Parallel: $MAX_PARALLEL"
  echo "  Risk Threshold: $RISK_THRESHOLD"
  echo "  Output: $OUTPUT_DIR"
  echo ""
  
  # Initialize
  init_state
  
  # Step 1: Analyze PRD
  log_info "Step 1: Analyzing PRD..."
  if ! run_analyzer; then
    log_error "Analyzer failed. Exiting."
    exit 1
  fi
  
  # Step 2: Triage sections
  log_info "Step 2: Triaging sections by risk..."
  if ! run_triage; then
    log_error "Triage failed. Exiting."
    exit 1
  fi
  
  # Step 3: Generate scenarios for high-risk sections
  log_info "Step 3: Generating scenarios for high-risk sections..."
  for section_file in "$STATE_DIR/prd-sections"/*.json; do
    [[ ! -f "$section_file" ]] && continue
    
    local section_id=$(jq -r ".id" "$section_file")
    local risk_score=$(jq -r ".riskScore // 0" "$section_file")
    
    if (( risk_score >= RISK_THRESHOLD )); then
      run_scenario_generator "$section_id" &
    fi
  done
  
  # Wait for all scenario generators
  wait
  
  # Step 4: Review rounds
  local round=0
  while (( round < MAX_ROUNDS )); do
    ((round++))
    
    echo ""
    separator
    echo "  Round $round of $MAX_ROUNDS"
    separator
    
    # Create review items for this round
    log_info "Creating review queue for round $round..."
    
    IFS=',' read -ra PERSONA_ARRAY <<< "$PERSONAS"
    
    for section_file in "$STATE_DIR/prd-sections"/*.json; do
      [[ ! -f "$section_file" ]] && continue
      
      local section_id=$(jq -r ".id" "$section_file")
      local risk_score=$(jq -r ".riskScore // 0" "$section_file")
      
      # Determine which personas should review this section
      for persona in "${PERSONA_ARRAY[@]}"; do
        persona=$(echo "$persona" | xargs)  # Trim whitespace
        
        # High-risk sections: all personas
        # Low-risk sections: skip some personas
        if (( risk_score >= RISK_THRESHOLD )); then
          create_review_item "${persona}-${section_id}" "$section_id" "$persona" "$round" "$risk_score"
        elif [[ "$persona" == "engineer" || "$persona" == "qa" ]]; then
          # Low-risk sections: only engineer and qa do quick pass
          create_review_item "${persona}-${section_id}" "$section_id" "$persona" "$round" "$risk_score"
        fi
      done
    done
    
    # Check if there are reviews to do
    local pending=$(count_reviews | jq -r ".pending")
    
    if [[ "$pending" == "0" ]]; then
      log_info "No reviews to perform in round $round"
      break
    fi
    
    log_info "Spawning $MAX_PARALLEL persona agents..."
    
    # Run persona agents in parallel
    local pids=()
    for i in $(seq 1 $MAX_PARALLEL); do
      run_persona_review $i &
      pids+=($!)
    done
    
    # Wait for all persona agents
    for pid in "${pids[@]}"; do
      wait $pid 2>/dev/null || true
    done
    
    log_success "Round $round reviews complete"
    
    # Run orchestrator to evaluate
    run_orchestrator "$round"
    local orch_result=$?
    
    if [[ $orch_result -eq 0 ]]; then
      log_success "Orchestrator: Analysis sufficient, stopping"
      break
    elif [[ $orch_result -eq 2 ]]; then
      log_error "Orchestrator: Analysis stuck, stopping"
      break
    fi
    
    # Clean up completed reviews for next round
    rm -f "$STATE_DIR/reviews"/*.json 2>/dev/null || true
    
    # Brief pause between rounds
    sleep 2
  done
  
  # Step 5: Generate report
  echo ""
  separator
  echo "  Generating Report"
  separator
  
  local report_file="$OUTPUT_DIR/report.md"
  generate_report "$report_file"
  
  # Print summary
  print_summary
  
  echo ""
  log_success "Report saved to: $report_file"
  echo ""
}

# Run main
main
