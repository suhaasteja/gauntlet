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
MODEL="claude-sonnet-4-5"
MAX_ROUNDS=3
MAX_PARALLEL=4
RISK_THRESHOLD=3
PRD_PATH=""
CODEBASE_PATH="."
PERSONAS="engineer,qa,pm,ux,security,devops"

# Verify phase defaults
VERIFY=false
VERIFY_ONLY=false
VERIFY_ALL=false
REPORT_PATH=""

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
      echo "Verification options:"
      echo "  --verify                Run verification phase after report generation"
      echo "  --verify-only           Run verification on existing state (no PRD required)"
      echo "  --verify-all            Also verify Medium findings (default: Critical+High only)"
      echo "  --report FILE           Existing report path, used with --verify-only"
      echo ""
      exit 0
      ;;
    --verify)
      VERIFY=true
      shift
      ;;
    --verify-only)
      VERIFY_ONLY=true
      VERIFY=true
      shift
      ;;
    --verify-all)
      VERIFY_ALL=true
      shift
      ;;
    --report)
      REPORT_PATH="$2"
      shift 2
      ;;
    --report=*)
      REPORT_PATH="${1#*=}"
      shift
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

# Validate PRD path (not required for --verify-only)
if [[ -z "$PRD_PATH" && "$VERIFY_ONLY" != "true" ]]; then
  echo "Error: --prd is required"
  echo "Usage: ./gauntlet.sh --prd path/to/prd.md --codebase path/to/code"
  echo "       ./gauntlet.sh --verify-only --codebase path/to/code"
  exit 1
fi

if [[ -n "$PRD_PATH" && ! -f "$PRD_PATH" ]]; then
  echo "Error: PRD file not found: $PRD_PATH"
  exit 1
fi

# Source libraries
source "$LIB_DIR/util.sh"
source "$LIB_DIR/agent.sh"
source "$LIB_DIR/review.sh"
source "$LIB_DIR/report.sh"
source "$LIB_DIR/verify.sh"

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
# Gauntlet Verify - Phase Runners
# =============================================================================

run_finding_classifier() {
  local severity_filter="$1"
  local classifier_id="classifier-1"

  echo ""
  separator
  echo "  Running Finding Classifier"
  separator

  register_agent "classifier" "$classifier_id"
  agent_log "$classifier_id" "Starting finding classification (filter: $severity_filter)"

  # Build context: all completed reviews as a JSON array
  local all_reviews
  all_reviews=$(for f in "$STATE_DIR/reviews"/*.json; do
    [[ -f "$f" ]] || continue
    local s
    s=$(jq -r '.status' "$f")
    [[ "$s" == "completed" ]] && cat "$f"
  done | jq -s '.')

  local context
  context=$(cat << EOF
# Finding Classification Task

## Severity Filter
Only classify findings with severity in: $severity_filter

## All Completed Reviews
$all_reviews

## Codebase Path
$CODEBASE_PATH

## Your Task
Read every finding in every review above. For each finding whose severity
matches the filter, classify it as unit-testable, integration-testable, or
untestable, then output the full JSON array.

EOF
)

  local prompt_file="$PROMPTS_DIR/finding-classifier.md"
  local output

  if [[ "$TOOL" == "amp" ]]; then
    output=$(cd "$CODEBASE_PATH" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --model "$MODEL" --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(cd "$CODEBASE_PATH" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --model "$MODEL" --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi

  agent_log "$classifier_id" "Classification complete"
  heartbeat "$classifier_id"
  deregister_agent "$classifier_id"

  if echo "$output" | grep -q "<gauntlet>CLASSIFICATION_COMPLETE</gauntlet>"; then
    local classified_json
    classified_json=$(echo "$output" | extract_json_block)

    if [[ -n "$classified_json" ]] && echo "$classified_json" | jq empty 2>/dev/null; then
      # Create a verification item for every classified finding
      echo "$classified_json" | jq -c ".[]" 2>/dev/null | while read -r item; do
        local finding_id=$(echo "$item" | jq -r ".findingId")
        local review_id=$(echo "$item" | jq -r ".reviewId")
        local section_id=$(echo "$item" | jq -r ".sectionId")
        local persona=$(echo "$item" | jq -r ".persona")
        local testability=$(echo "$item" | jq -r ".testability")
        local untestable_reason=$(echo "$item" | jq -r ".untestableReason // empty")
        local finding=$(echo "$item" | jq -c ".finding")

        create_verification_item "$finding_id" "$review_id" "$section_id" \
          "$persona" "$finding" "$testability" "$untestable_reason"
      done

      local total_count
      total_count=$(echo "$classified_json" | jq 'length')
      local testable_count
      testable_count=$(echo "$classified_json" | jq '[.[] | select(.testability != "untestable")] | length')
      log_success "Classifier: $testable_count testable / $total_count total findings classified"
      return 0
    else
      log_error "Classifier: Could not extract valid JSON from output"
      return 1
    fi
  else
    log_error "Classifier: No completion signal detected"
    return 1
  fi
}

run_test_generator_worker() {
  local worker_num="$1"
  local gen_id="test-gen-$worker_num"

  subseparator
  log_info "Test generator $gen_id starting"

  register_agent "test_gen" "$gen_id"
  agent_log "$gen_id" "Starting test generation"

  # Loop: process all available test-generation tasks
  while true; do
    local verify_id
    verify_id=$(claim_verification "$gen_id" "generate") || true

    if [[ -z "$verify_id" ]]; then
      log_debug "Test generator $gen_id: No more tasks"
      break
    fi

    log_info "Test generator $gen_id: Generating test for $verify_id"
    agent_log "$gen_id" "Generating test for: $verify_id"

    update_verification_status "$verify_id" "generating"

    local verify_json
    verify_json=$(get_verification "$verify_id")
    local finding
    finding=$(echo "$verify_json" | jq -c ".finding")
    local section_id
    section_id=$(echo "$verify_json" | jq -r ".sectionId")
    local testability
    testability=$(echo "$verify_json" | jq -r ".testability")

    # Get PRD section content
    local section_content=""
    local section_file="$STATE_DIR/prd-sections/${section_id}.json"
    [[ -f "$section_file" ]] && section_content=$(cat "$section_file")

    # Read source files referenced in the finding's codeEvidence
    local source_files_content=""
    while IFS= read -r evidence; do
      [[ -z "$evidence" ]] && continue
      # Strip :line-range suffix to get bare file path
      local file_path="${evidence%%:*}"
      local full_path="$CODEBASE_PATH/$file_path"
      if [[ -f "$full_path" ]]; then
        source_files_content+="### File: $file_path"$'\n'
        source_files_content+="$(cat "$full_path")"$'\n\n'
      fi
    done < <(echo "$finding" | jq -r '.codeEvidence[]?' 2>/dev/null)

    local context
    context=$(cat << EOF
# Test Generation Task

## Verification ID
$verify_id

## Finding
$(echo "$finding" | jq .)

## Testability Classification
$testability

## PRD Section
$section_content

## Relevant Source Files
$source_files_content

## Codebase Root
$CODEBASE_PATH

## Your Task
Inspect the codebase for the test framework, then generate one focused
adversarial test that confirms or refutes this specific finding.

EOF
)

    local prompt_file="$PROMPTS_DIR/test-generator.md"
    local output

    if [[ "$TOOL" == "amp" ]]; then
      output=$(cd "$CODEBASE_PATH" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --model "$MODEL" --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
    else
      output=$(cd "$CODEBASE_PATH" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --model "$MODEL" --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
    fi

    heartbeat "$gen_id"

    if echo "$output" | grep -q "<gauntlet>TEST_GENERATED:${verify_id}</gauntlet>"; then
      # Extract metadata JSON and raw test code
      local metadata_json
      metadata_json=$(echo "$output" | extract_json_block)
      local test_code
      test_code=$(echo "$output" | awk '/<gauntlet-test>/{p=1; next} /<\/gauntlet-test>/{p=0} p{print}')

      if [[ -n "$metadata_json" && -n "$test_code" ]] && echo "$metadata_json" | jq empty 2>/dev/null; then
        local test_name
        test_name=$(echo "$metadata_json" | jq -r ".testName")
        local test_ext
        test_ext=$(echo "$metadata_json" | jq -r ".testFileExtension")
        local test_command
        test_command=$(echo "$metadata_json" | jq -r ".testCommand")
        local test_framework
        test_framework=$(echo "$metadata_json" | jq -r ".testFramework")

        # Write test file to generated-tests dir
        local test_file="$STATE_DIR/generated-tests/${verify_id}.${test_ext}"
        printf '%s\n' "$test_code" > "$test_file"

        # Update verification record
        local verify_file="$STATE_DIR/verify/verifications/${verify_id}.json"
        local now
        now=$(timestamp)
        jq --arg testFile "$test_file" \
           --arg testName "$test_name" \
           --arg testCommand "$test_command" \
           --arg testFramework "$test_framework" \
           --arg now "$now" \
           '.testFile = $testFile | .testName = $testName | .testCommand = $testCommand
            | .testFramework = $testFramework | .status = "test_generated" | .updatedAt = $now' \
           "$verify_file" > "$verify_file.tmp" && mv "$verify_file.tmp" "$verify_file"

        log_success "Test generator $gen_id: test written → $(basename "$test_file")"
        agent_log "$gen_id" "Test written: $verify_id → $test_file"
      else
        log_warn "Test generator $gen_id: Could not extract test content for $verify_id"
        release_verification "$verify_id" "generate"
      fi
    else
      log_warn "Test generator $gen_id: No completion signal for $verify_id, releasing"
      release_verification "$verify_id" "generate"
    fi
  done

  deregister_agent "$gen_id"
}

run_tests() {
  echo ""
  separator
  echo "  Running Generated Tests"
  separator

  local tested=0 skipped=0

  for verify_file in "$STATE_DIR/verify/verifications"/*.json; do
    [[ ! -f "$verify_file" ]] && continue

    local status
    status=$(jq -r '.status' "$verify_file")
    [[ "$status" != "test_generated" ]] && continue

    local verify_id
    verify_id=$(jq -r '.id' "$verify_file")
    local test_file
    test_file=$(jq -r '.testFile' "$verify_file")
    local test_command
    test_command=$(jq -r '.testCommand' "$verify_file")

    if [[ -z "$test_file" || ! -f "$test_file" ]]; then
      log_warn "Test file missing for $verify_id, skipping"
      ((skipped++))
      continue
    fi

    # Replace TESTFILE placeholder with absolute path
    local abs_test_file
    abs_test_file="$(cd "$(dirname "$test_file")" && pwd)/$(basename "$test_file")"
    local actual_command="${test_command//TESTFILE/$abs_test_file}"

    log_info "Running: $verify_id"
    log_debug "Command: $actual_command"

    local test_output
    local test_exit_code=0
    test_output=$(cd "$CODEBASE_PATH" && timeout 120 bash -c "$actual_command" 2>&1) || test_exit_code=$?

    local test_result="passed"
    if [[ $test_exit_code -ne 0 ]]; then
      if [[ $test_exit_code -eq 124 ]]; then
        test_result="error"
        test_output="Test timed out after 120 seconds.${test_output:+ }${test_output}"
      else
        test_result="failed"
      fi
    fi

    log_info "  → $test_result (exit $test_exit_code)"

    # Persist test result; advance to verdict_pending phase
    local now
    now=$(timestamp)
    jq --arg result "$test_result" \
       --arg output "$test_output" \
       --arg now "$now" \
       '.testResult = $result | .testOutput = $output | .status = "verdict_pending" | .updatedAt = $now' \
       "$verify_file" > "$verify_file.tmp" && mv "$verify_file.tmp" "$verify_file"

    ((tested++))
  done

  log_success "Tests executed: $tested, skipped (missing file): $skipped"
}

run_verifier_worker() {
  local worker_num="$1"
  local verifier_id="verifier-$worker_num"

  subseparator
  log_info "Verifier $verifier_id starting"

  register_agent "verifier" "$verifier_id"
  agent_log "$verifier_id" "Starting verdict analysis"

  # Loop: process all available verdict tasks
  while true; do
    local verify_id
    verify_id=$(claim_verification "$verifier_id" "verdict") || true

    if [[ -z "$verify_id" ]]; then
      log_debug "Verifier $verifier_id: No more tasks"
      break
    fi

    log_info "Verifier $verifier_id: Analyzing $verify_id"
    update_verification_status "$verify_id" "verifying"

    local verify_json
    verify_json=$(get_verification "$verify_id")
    local finding
    finding=$(echo "$verify_json" | jq -c ".finding")
    local test_file
    test_file=$(echo "$verify_json" | jq -r ".testFile // empty")
    local test_name
    test_name=$(echo "$verify_json" | jq -r ".testName // empty")
    local test_result
    test_result=$(echo "$verify_json" | jq -r ".testResult // empty")
    local test_output
    test_output=$(echo "$verify_json" | jq -r ".testOutput // empty")

    # Read test code
    local test_code=""
    [[ -f "$test_file" ]] && test_code=$(cat "$test_file")

    local context
    context=$(cat << EOF
# Verdict Analysis Task

## Verification ID
$verify_id

## Original Finding
$(echo "$finding" | jq .)

## Generated Test (${test_name})
$test_code

## Test Result
$test_result

## Test Output
$test_output

## Your Task
Interpret the test result and deliver a verdict: confirmed_vulnerability,
false_positive, or inconclusive.

EOF
)

    local prompt_file="$PROMPTS_DIR/verifier.md"
    local output

    if [[ "$TOOL" == "amp" ]]; then
      output=$(cd "$SCRIPT_DIR" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --model "$MODEL" --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
    else
      output=$(cd "$SCRIPT_DIR" && echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --model "$MODEL" --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
    fi

    heartbeat "$verifier_id"

    if echo "$output" | grep -q "<gauntlet>VERDICT_COMPLETE:${verify_id}</gauntlet>"; then
      local verdict_json
      verdict_json=$(echo "$output" | extract_json_block)

      if [[ -n "$verdict_json" ]] && echo "$verdict_json" | jq empty 2>/dev/null; then
        local verdict
        verdict=$(echo "$verdict_json" | jq -r ".verdict")
        local verdict_summary
        verdict_summary=$(echo "$verdict_json" | jq -r ".verdictSummary")
        local recommended_action
        recommended_action=$(echo "$verdict_json" | jq -r ".recommendedAction // empty")
        local manual_review
        manual_review=$(echo "$verdict_json" | jq -r ".manualReviewNeeded // false")
        local manual_reason
        manual_reason=$(echo "$verdict_json" | jq -r ".manualReviewReason // empty")

        local manual_bool=false
        [[ "$manual_review" == "true" ]] && manual_bool=true

        # Write verdict back to verification file
        local verify_file="$STATE_DIR/verify/verifications/${verify_id}.json"
        local now
        now=$(timestamp)
        jq --arg verdict "$verdict" \
           --arg summary "$verdict_summary" \
           --arg action "$recommended_action" \
           --argjson manual "$manual_bool" \
           --arg reason "$manual_reason" \
           --arg now "$now" \
           '.verdict = $verdict | .verdictSummary = $summary | .recommendedAction = $action
            | .manualReviewNeeded = $manual | .manualReviewReason = $reason
            | .status = "completed" | .updatedAt = $now' \
           "$verify_file" > "$verify_file.tmp" && mv "$verify_file.tmp" "$verify_file"

        # Copy confirmed-vulnerability tests to output/verified-tests/ for developer adoption
        if [[ "$verdict" == "confirmed_vulnerability" && -f "$test_file" ]]; then
          cp "$test_file" "$OUTPUT_DIR/verified-tests/$(basename "$test_file")"
          log_success "  Confirmed test saved: output/verified-tests/$(basename "$test_file")"
        fi

        log_success "Verifier $verifier_id: $verify_id → $verdict"
        agent_log "$verifier_id" "Verdict: $verify_id → $verdict"
      else
        log_warn "Verifier $verifier_id: Could not extract verdict JSON for $verify_id"
        release_verification "$verify_id" "verdict"
      fi
    else
      log_warn "Verifier $verifier_id: No completion signal for $verify_id, releasing"
      release_verification "$verify_id" "verdict"
    fi
  done

  deregister_agent "$verifier_id"
}

generate_verified_report() {
  local base_report="$1"
  local output_file="$2"
  local now
  now=$(timestamp)

  log_info "Generating verified report: $output_file"

  # ── Counts (mirror generate_report) ──────────────────────────────────────
  local critical=0 high=0 medium=0 low=0 info=0

  for review_file in "$STATE_DIR/reviews"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    local rs
    rs=$(jq -r '.status' "$review_file")
    [[ "$rs" != "completed" ]] && continue
    critical=$((critical + $(jq '[.findings[] | select(.severity == "critical")] | length' "$review_file")))
    high=$((high + $(jq '[.findings[] | select(.severity == "high")] | length' "$review_file")))
    medium=$((medium + $(jq '[.findings[] | select(.severity == "medium")] | length' "$review_file")))
    low=$((low + $(jq '[.findings[] | select(.severity == "low")] | length' "$review_file")))
    info=$((info + $(jq '[.findings[] | select(.severity == "info")] | length' "$review_file")))
  done

  local total_findings=$((critical + high + medium + low + info))
  local total_rounds
  total_rounds=$(ls -1 "$STATE_DIR/rounds"/round-*.json 2>/dev/null | wc -l | tr -d ' ')
  local personas
  personas=$(for f in "$STATE_DIR/reviews"/*.json; do [[ -f "$f" ]] && jq -r '.persona' "$f"; done | sort -u | wc -l | tr -d ' ')

  local total_score=0 review_count=0
  for review_file in "$STATE_DIR/reviews"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    local rs
    rs=$(jq -r '.status' "$review_file")
    [[ "$rs" != "completed" ]] && continue
    local score
    score=$(jq -r '.feasibilityScore // 0' "$review_file")
    if [[ "$score" != "null" && "$score" != "0" ]]; then
      total_score=$((total_score + score))
      ((review_count++))
    fi
  done

  local avg_score=0
  (( review_count > 0 )) && avg_score=$((total_score * 10 / review_count))

  # ── Verification counts ───────────────────────────────────────────────────
  local v_confirmed=0 v_false_pos=0 v_inconclusive=0 v_untestable=0 v_failed=0

  for vf in "$STATE_DIR/verify/verifications"/*.json; do
    [[ ! -f "$vf" ]] && continue
    local testability
    testability=$(jq -r '.testability' "$vf")
    local verdict
    verdict=$(jq -r '.verdict // empty' "$vf")
    local vstatus
    vstatus=$(jq -r '.status' "$vf")

    if [[ "$testability" == "untestable" ]]; then
      ((v_untestable++))
    elif [[ "$verdict" == "confirmed_vulnerability" ]]; then
      ((v_confirmed++))
    elif [[ "$verdict" == "false_positive" ]]; then
      ((v_false_pos++))
    elif [[ "$verdict" == "inconclusive" ]]; then
      ((v_inconclusive++))
    elif [[ "$vstatus" == "failed" ]]; then
      ((v_failed++))
    fi
  done

  local total_sections
  total_sections=$(ls -1 "$STATE_DIR/prd-sections"/*.json 2>/dev/null | wc -l | tr -d ' ')
  local high_risk
  high_risk=$(for f in "$STATE_DIR/prd-sections"/*.json; do [[ -f "$f" ]] && jq -r 'select(.riskScore >= 4) | .id' "$f"; done 2>/dev/null | wc -l | tr -d ' ')
  local medium_risk
  medium_risk=$(for f in "$STATE_DIR/prd-sections"/*.json; do [[ -f "$f" ]] && jq -r 'select(.riskScore == 3) | .id' "$f"; done 2>/dev/null | wc -l | tr -d ' ')
  local low_risk
  low_risk=$(for f in "$STATE_DIR/prd-sections"/*.json; do [[ -f "$f" ]] && jq -r 'select(.riskScore <= 2) | .id' "$f"; done 2>/dev/null | wc -l | tr -d ' ')

  # ── Write report header ───────────────────────────────────────────────────
  cat > "$output_file" << EOF
# PRD Feasibility Report (Verified)

**Generated:** $now
**Rounds Completed:** $total_rounds
**Personas Active:** $personas
**Total Findings:** $total_findings

---

## Verification Summary

| Verdict | Count |
|---------|-------|
| ❌ Confirmed Vulnerability | $v_confirmed |
| ✅ False Positive | $v_false_pos |
| ⚠️ Inconclusive | $v_inconclusive |
| ⚠️ Requires Manual Verification | $v_untestable |
| ⏭️ Not Verified / Failed | $v_failed |

Confirmed tests available in: \`output/verified-tests/\`

---

## PRD Analysis Summary

**Total Sections:** $total_sections

**Risk Distribution:**
- 🔴 High Risk (4-5): $high_risk sections
- 🟡 Medium Risk (3): $medium_risk sections
- 🟢 Low Risk (1-2): $low_risk sections

EOF

  if (( total_sections > 0 )); then
    echo "**Sections Identified:**" >> "$output_file"
    echo "" >> "$output_file"
    for section_file in "$STATE_DIR/prd-sections"/*.json; do
      [[ ! -f "$section_file" ]] && continue
      local sid stitle srisk
      sid=$(jq -r '.id' "$section_file")
      stitle=$(jq -r '.title' "$section_file")
      srisk=$(jq -r '.riskScore // "N/A"' "$section_file")
      echo "- **$sid:** $stitle (Risk: $srisk/5)" >> "$output_file"
    done
    echo "" >> "$output_file"
  fi

  cat >> "$output_file" << EOF

---

## Executive Summary

**Overall Feasibility Score:** $avg_score/100

**Findings Breakdown:**
- 🔴 Critical: $critical
- 🟠 High: $high
- 🟡 Medium: $medium
- 🟢 Low: $low
- ℹ️ Info: $info

EOF

  # ── Section-by-section (same as generate_report) ─────────────────────────
  echo "" >> "$output_file"
  echo "---" >> "$output_file"
  echo "" >> "$output_file"
  echo "## Section-by-Section Analysis" >> "$output_file"
  echo "" >> "$output_file"

  for section_file in "$STATE_DIR/prd-sections"/*.json; do
    [[ ! -f "$section_file" ]] && continue

    local section_id section_title risk_score
    section_id=$(jq -r '.id' "$section_file")
    section_title=$(jq -r '.title' "$section_file")
    risk_score=$(jq -r '.riskScore // "N/A"' "$section_file")

    echo "### $section_id: $section_title" >> "$output_file"
    echo "" >> "$output_file"
    echo "**Risk Score:** $risk_score/5" >> "$output_file"
    echo "" >> "$output_file"
    echo "| Persona | Feasibility | Key Findings |" >> "$output_file"
    echo "|---------|-------------|--------------|" >> "$output_file"

    for review_file in "$STATE_DIR/reviews"/${section_id}*.json "$STATE_DIR/reviews"/*-${section_id}.json; do
      [[ ! -f "$review_file" ]] && continue
      local status
      status=$(jq -r '.status' "$review_file")
      [[ "$status" != "completed" ]] && continue

      local persona score finding_count high_severity verdict_tag
      persona=$(jq -r '.persona' "$review_file")
      score=$(jq -r '.feasibilityScore // "N/A"' "$review_file")
      finding_count=$(jq '[.findings[]] | length' "$review_file")
      high_severity=$(jq '[.findings[] | select(.severity == "critical" or .severity == "high")] | length' "$review_file")

      local verdict="✅ Good"
      if (( high_severity > 0 )); then
        verdict="❌ Blocked"
      elif [[ "$score" != "N/A" ]] && (( score < 5 )); then
        verdict="⚠️ Caution"
      fi

      echo "| $persona | $verdict ($score/10) | $finding_count findings, $high_severity high+ |" >> "$output_file"
    done

    echo "" >> "$output_file"
  done

  # ── All Findings by Severity (with verification blocks) ──────────────────
  echo "" >> "$output_file"
  echo "---" >> "$output_file"
  echo "" >> "$output_file"
  echo "## All Findings by Severity" >> "$output_file"
  echo "" >> "$output_file"

  for severity in critical high medium low info; do
    local severity_emoji="ℹ️"
    case "$severity" in
      critical) severity_emoji="🔴" ;;
      high)     severity_emoji="🟠" ;;
      medium)   severity_emoji="🟡" ;;
      low)      severity_emoji="🟢" ;;
    esac

    local sev_count
    sev_count=$(for f in "$STATE_DIR/reviews"/*.json; do
      [[ -f "$f" ]] && jq -r ".findings[] | select(.severity == \"$severity\") | .title" "$f" 2>/dev/null
    done | wc -l | tr -d ' ')

    if (( sev_count > 0 )); then
      echo "### $severity_emoji $(echo $severity | tr '[:lower:]' '[:upper:]') ($sev_count)" >> "$output_file"
      echo "" >> "$output_file"

      for review_file in "$STATE_DIR/reviews"/*.json; do
        [[ ! -f "$review_file" ]] && continue
        local status
        status=$(jq -r '.status' "$review_file")
        [[ "$status" != "completed" ]] && continue

        local persona section_id
        persona=$(jq -r '.persona' "$review_file")
        section_id=$(jq -r '.sectionId' "$review_file")

        # Iterate findings at this severity with index tracking
        local idx=0
        while IFS= read -r finding_json; do
          [[ -z "$finding_json" ]] && continue

          local title finding_text code_ev prd_ref recommendation
          title=$(echo "$finding_json" | jq -r '.title')
          finding_text=$(echo "$finding_json" | jq -r '.finding')
          code_ev=$(echo "$finding_json" | jq -r '.codeEvidence | join(", ")')
          prd_ref=$(echo "$finding_json" | jq -r '.prdReference')
          recommendation=$(echo "$finding_json" | jq -r '.recommendation')

          local finding_id="${persona}-${section_id}-f${idx}"
          local verify_block
          verify_block=$(get_verification_block "$finding_id")

          echo "**[$title]** ($section_id, $persona)" >> "$output_file"
          echo "" >> "$output_file"
          if [[ -n "$verify_block" ]]; then
            echo "$verify_block" >> "$output_file"
            echo "" >> "$output_file"
          fi
          echo "$finding_text" >> "$output_file"
          echo "" >> "$output_file"
          echo "- **Code:** $code_ev" >> "$output_file"
          echo "- **PRD:** $prd_ref" >> "$output_file"
          echo "- **Recommendation:** $recommendation" >> "$output_file"
          echo "" >> "$output_file"

          ((idx++))
        done < <(jq -c ".findings[] | select(.severity == \"$severity\")" "$review_file" 2>/dev/null)
      done
    fi
  done

  # ── Recommendations ───────────────────────────────────────────────────────
  echo "" >> "$output_file"
  echo "---" >> "$output_file"
  echo "" >> "$output_file"
  echo "## Recommendations" >> "$output_file"
  echo "" >> "$output_file"

  local rec_num=1
  for review_file in "$STATE_DIR/reviews"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    local status
    status=$(jq -r '.status' "$review_file")
    [[ "$status" != "completed" ]] && continue

    jq -r ".findings[] | select(.severity == \"critical\" or .severity == \"high\") |
      \"$rec_num. **\(.title)** — \(.recommendation)\"" \
      "$review_file" >> "$output_file" 2>/dev/null

    ((rec_num++))
  done

  # ── Review rounds ─────────────────────────────────────────────────────────
  echo "" >> "$output_file"
  echo "---" >> "$output_file"
  echo "" >> "$output_file"
  echo "## Review Rounds" >> "$output_file"
  echo "" >> "$output_file"

  for round_file in "$STATE_DIR/rounds"/round-*.json; do
    [[ ! -f "$round_file" ]] && continue

    local round decision reasoning sections
    round=$(jq -r '.round' "$round_file")
    decision=$(jq -r '.orchestratorDecision' "$round_file")
    reasoning=$(jq -r '.reasoning' "$round_file")
    sections=$(jq -r '.sectionsReviewed | join(", ")' "$round_file")

    echo "### Round $round" >> "$output_file"
    echo "" >> "$output_file"
    echo "- **Sections Reviewed:** $sections" >> "$output_file"
    echo "- **Decision:** $decision" >> "$output_file"
    echo "- **Reasoning:** $reasoning" >> "$output_file"
    echo "" >> "$output_file"
  done

  log_success "Verified report generated: $output_file"
}

run_verify_pipeline() {
  echo ""
  separator
  echo "  GAUNTLET VERIFY - Closing the Loop"
  separator

  # Initialize verify state dirs
  init_verify

  # Severity gate: critical+high by default; +medium with --verify-all
  local severity_filter="critical,high"
  [[ "$VERIFY_ALL" == "true" ]] && severity_filter="critical,high,medium"
  log_info "Verifying findings at severity: $severity_filter"

  # Step V1: Classify findings by testability
  log_info "Verify Step 1: Classifying findings..."
  if ! run_finding_classifier "$severity_filter"; then
    log_error "Finding classifier failed. Skipping verification."
    return 1
  fi

  local testable_count
  testable_count=$(for f in "$STATE_DIR/verify/verifications"/*.json 2>/dev/null; do
    [[ -f "$f" ]] && jq -r 'select(.testability != "untestable") | .id' "$f"
  done | wc -l | tr -d ' ')

  if [[ "$testable_count" == "0" ]]; then
    log_warn "No testable findings found. Generating verified report with manual-review flags only."
    local base_report="${REPORT_PATH:-$OUTPUT_DIR/report.md}"
    generate_verified_report "$base_report" "$OUTPUT_DIR/verified-report.md"
    log_success "Verified report: $OUTPUT_DIR/verified-report.md"
    return 0
  fi

  # Step V2: Generate tests (parallel workers)
  echo ""
  separator
  echo "  Verify Step 2: Generating Tests ($MAX_PARALLEL workers)"
  separator

  local pids=()
  for i in $(seq 1 $MAX_PARALLEL); do
    run_test_generator_worker $i &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait $pid 2>/dev/null || true
  done
  log_success "Test generation complete"

  # Step V3: Execute tests
  run_tests

  # Step V4: Interpret results (parallel verifier workers)
  echo ""
  separator
  echo "  Verify Step 4: Interpreting Results ($MAX_PARALLEL workers)"
  separator

  pids=()
  for i in $(seq 1 $MAX_PARALLEL); do
    run_verifier_worker $i &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait $pid 2>/dev/null || true
  done
  log_success "Verification complete"

  # Step V5: Generate verified report
  echo ""
  separator
  echo "  Verify Step 5: Generating Verified Report"
  separator

  local base_report="${REPORT_PATH:-$OUTPUT_DIR/report.md}"
  generate_verified_report "$base_report" "$OUTPUT_DIR/verified-report.md"

  # Print verification summary
  echo ""
  separator
  echo "  VERIFICATION SUMMARY"
  separator
  echo ""
  local v_confirmed=0 v_false_pos=0 v_inconclusive=0 v_untestable=0
  for vf in "$STATE_DIR/verify/verifications"/*.json; do
    [[ ! -f "$vf" ]] && continue
    local testability verdict
    testability=$(jq -r '.testability' "$vf")
    verdict=$(jq -r '.verdict // empty' "$vf")
    if [[ "$testability" == "untestable" ]]; then ((v_untestable++))
    elif [[ "$verdict" == "confirmed_vulnerability" ]]; then ((v_confirmed++))
    elif [[ "$verdict" == "false_positive" ]]; then ((v_false_pos++))
    elif [[ "$verdict" == "inconclusive" ]]; then ((v_inconclusive++))
    fi
  done
  echo "  ❌ Confirmed Vulnerabilities: $v_confirmed"
  echo "  ✅ False Positives:           $v_false_pos"
  echo "  ⚠️  Inconclusive:              $v_inconclusive"
  echo "  ⚠️  Requires Manual Review:   $v_untestable"
  echo ""
  log_success "Verified report: $OUTPUT_DIR/verified-report.md"
  [[ $v_confirmed -gt 0 ]] && log_info "Confirmed tests: $OUTPUT_DIR/verified-tests/"
  echo ""
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
  echo "  PRD: ${PRD_PATH:-<none — verify-only mode>}"
  echo "  Codebase: $CODEBASE_PATH"
  echo "  Personas: $PERSONAS"
  echo "  Tool: $TOOL"
  echo "  Max Rounds: $MAX_ROUNDS"
  echo "  Max Parallel: $MAX_PARALLEL"
  echo "  Risk Threshold: $RISK_THRESHOLD"
  echo "  Output: $OUTPUT_DIR"
  if [[ "$VERIFY" == "true" ]]; then
    echo "  Verify: enabled"
    echo "  Verify All: $VERIFY_ALL"
  fi
  echo ""

  # ── Verify-only mode: skip full PRD pipeline, run verification on existing state ──
  if [[ "$VERIFY_ONLY" == "true" ]]; then
    init_state
    if [[ -z "$(ls -1 "$STATE_DIR/reviews"/*.json 2>/dev/null)" ]]; then
      log_error "No completed reviews found in $STATE_DIR/reviews/. Run the full pipeline first."
      exit 1
    fi
    run_verify_pipeline
    return 0
  fi

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

  # Step 6: Verification phase (if requested)
  if [[ "$VERIFY" == "true" ]]; then
    run_verify_pipeline
  fi
}

# Run main
main
