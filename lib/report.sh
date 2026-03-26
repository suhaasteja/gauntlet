#!/bin/bash
# Gauntlet - Report Generation
# Aggregates review findings into structured markdown report

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(dirname "$SCRIPT_DIR")/state"
REVIEWS_DIR="$STATE_DIR/reviews"
SECTIONS_DIR="$STATE_DIR/prd-sections"
ROUNDS_DIR="$STATE_DIR/rounds"

source "$SCRIPT_DIR/util.sh"

# Generate the final report
# Usage: generate_report "output/report.md"
generate_report() {
  local output_file="$1"
  local now=$(timestamp)
  
  log_info "Generating report: $output_file"
  
  # Count findings by severity
  local critical=0 high=0 medium=0 low=0 info=0
  
  for review_file in "$REVIEWS_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    local status=$(jq -r '.status' "$review_file")
    [[ "$status" != "completed" ]] && continue
    
    critical=$((critical + $(jq '[.findings[] | select(.severity == "critical")] | length' "$review_file")))
    high=$((high + $(jq '[.findings[] | select(.severity == "high")] | length' "$review_file")))
    medium=$((medium + $(jq '[.findings[] | select(.severity == "medium")] | length' "$review_file")))
    low=$((low + $(jq '[.findings[] | select(.severity == "low")] | length' "$review_file")))
    info=$((info + $(jq '[.findings[] | select(.severity == "info")] | length' "$review_file")))
  done
  
  local total_findings=$((critical + high + medium + low + info))
  
  # Count rounds
  local total_rounds=$(ls -1 "$ROUNDS_DIR"/round-*.json 2>/dev/null | wc -l | tr -d ' ')
  
  # Count personas used
  local personas=$(for f in "$REVIEWS_DIR"/*.json; do [[ -f "$f" ]] && jq -r '.persona' "$f"; done | sort -u | wc -l | tr -d ' ')
  
  # Calculate overall feasibility score (weighted average)
  local total_score=0
  local review_count=0
  for review_file in "$REVIEWS_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    local status=$(jq -r '.status' "$review_file")
    [[ "$status" != "completed" ]] && continue
    local score=$(jq -r '.feasibilityScore // 0' "$review_file")
    if [[ "$score" != "null" && "$score" != "0" ]]; then
      total_score=$((total_score + score))
      ((review_count++))
    fi
  done
  
  local avg_score=0
  if (( review_count > 0 )); then
    avg_score=$((total_score * 10 / review_count))
  fi
  
  # Count sections and get risk distribution
  local total_sections=$(ls -1 "$SECTIONS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
  local high_risk=$(for f in "$SECTIONS_DIR"/*.json; do [[ -f "$f" ]] && jq -r 'select(.riskScore >= 4) | .id' "$f"; done 2>/dev/null | wc -l | tr -d ' ')
  local medium_risk=$(for f in "$SECTIONS_DIR"/*.json; do [[ -f "$f" ]] && jq -r 'select(.riskScore == 3) | .id' "$f"; done 2>/dev/null | wc -l | tr -d ' ')
  local low_risk=$(for f in "$SECTIONS_DIR"/*.json; do [[ -f "$f" ]] && jq -r 'select(.riskScore <= 2) | .id' "$f"; done 2>/dev/null | wc -l | tr -d ' ')
  
  # Start writing report
  cat > "$output_file" << EOF
# PRD Feasibility Report

**Generated:** $now  
**Rounds Completed:** $total_rounds  
**Personas Active:** $personas  
**Total Findings:** $total_findings

---

## PRD Analysis Summary

**Total Sections:** $total_sections

**Risk Distribution:**
- 🔴 High Risk (4-5): $high_risk sections
- 🟡 Medium Risk (3): $medium_risk sections
- 🟢 Low Risk (1-2): $low_risk sections

EOF

  # Add section list with risk scores
  if (( total_sections > 0 )); then
    echo "**Sections Identified:**" >> "$output_file"
    echo "" >> "$output_file"
    for section_file in "$SECTIONS_DIR"/*.json; do
      [[ ! -f "$section_file" ]] && continue
      local sid=$(jq -r '.id' "$section_file")
      local stitle=$(jq -r '.title' "$section_file")
      local srisk=$(jq -r '.riskScore // "N/A"' "$section_file")
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

  # Section-by-section analysis
  echo "" >> "$output_file"
  echo "---" >> "$output_file"
  echo "" >> "$output_file"
  echo "## Section-by-Section Analysis" >> "$output_file"
  echo "" >> "$output_file"
  
  for section_file in "$SECTIONS_DIR"/*.json; do
    [[ ! -f "$section_file" ]] && continue
    
    local section_id=$(jq -r '.id' "$section_file")
    local section_title=$(jq -r '.title' "$section_file")
    local risk_score=$(jq -r '.riskScore // "N/A"' "$section_file")
    
    echo "### $section_id: $section_title" >> "$output_file"
    echo "" >> "$output_file"
    echo "**Risk Score:** $risk_score/5" >> "$output_file"
    echo "" >> "$output_file"
    
    # Table of persona verdicts
    echo "| Persona | Feasibility | Key Findings |" >> "$output_file"
    echo "|---------|-------------|--------------|" >> "$output_file"
    
    for review_file in "$REVIEWS_DIR"/${section_id}*.json "$REVIEWS_DIR"/*-${section_id}.json; do
      [[ ! -f "$review_file" ]] && continue
      local status=$(jq -r '.status' "$review_file")
      [[ "$status" != "completed" ]] && continue
      
      local persona=$(jq -r '.persona' "$review_file")
      local score=$(jq -r '.feasibilityScore // "N/A"' "$review_file")
      local finding_count=$(jq '[.findings[]] | length' "$review_file")
      local high_severity=$(jq '[.findings[] | select(.severity == "critical" or .severity == "high")] | length' "$review_file")
      
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
  
  # All findings by severity
  echo "" >> "$output_file"
  echo "---" >> "$output_file"
  echo "" >> "$output_file"
  echo "## All Findings by Severity" >> "$output_file"
  echo "" >> "$output_file"
  
  for severity in critical high medium low info; do
    local severity_emoji="ℹ️"
    case "$severity" in
      critical) severity_emoji="🔴" ;;
      high) severity_emoji="🟠" ;;
      medium) severity_emoji="🟡" ;;
      low) severity_emoji="🟢" ;;
    esac
    
    local count=$(for f in "$REVIEWS_DIR"/*.json; do [[ -f "$f" ]] && jq -r ".findings[] | select(.severity == \"$severity\") | .title" "$f" 2>/dev/null; done | wc -l | tr -d ' ')
    
    if (( count > 0 )); then
      echo "### $severity_emoji $(echo $severity | tr '[:lower:]' '[:upper:]') ($count)" >> "$output_file"
      echo "" >> "$output_file"
      
      for review_file in "$REVIEWS_DIR"/*.json; do
        [[ ! -f "$review_file" ]] && continue
        local status=$(jq -r '.status' "$review_file")
        [[ "$status" != "completed" ]] && continue
        
        local persona=$(jq -r '.persona' "$review_file")
        local section_id=$(jq -r '.sectionId' "$review_file")
        
        jq -r ".findings[] | select(.severity == \"$severity\") | 
          \"**[\(.title)]** ($section_id, $persona)\\n\\n\(.finding)\\n\\n- **Code:** \(.codeEvidence | join(\", \"))\\n- **PRD:** \(.prdReference)\\n- **Recommendation:** \(.recommendation)\\n\"" \
          "$review_file" >> "$output_file" 2>/dev/null
      done
      
      echo "" >> "$output_file"
    fi
  done
  
  # Recommendations section
  echo "" >> "$output_file"
  echo "---" >> "$output_file"
  echo "" >> "$output_file"
  echo "## Recommendations" >> "$output_file"
  echo "" >> "$output_file"
  
  local rec_num=1
  for review_file in "$REVIEWS_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    local status=$(jq -r '.status' "$review_file")
    [[ "$status" != "completed" ]] && continue
    
    jq -r ".findings[] | select(.severity == \"critical\" or .severity == \"high\") | 
      \"$rec_num. **\(.title)** - \(.recommendation)\"" \
      "$review_file" >> "$output_file" 2>/dev/null
    
    ((rec_num++))
  done
  
  # Round summaries
  echo "" >> "$output_file"
  echo "---" >> "$output_file"
  echo "" >> "$output_file"
  echo "## Review Rounds" >> "$output_file"
  echo "" >> "$output_file"
  
  for round_file in "$ROUNDS_DIR"/round-*.json; do
    [[ ! -f "$round_file" ]] && continue
    
    local round=$(jq -r '.round' "$round_file")
    local decision=$(jq -r '.orchestratorDecision' "$round_file")
    local reasoning=$(jq -r '.reasoning' "$round_file")
    local sections=$(jq -r '.sectionsReviewed | join(", ")' "$round_file")
    
    echo "### Round $round" >> "$output_file"
    echo "" >> "$output_file"
    echo "- **Sections Reviewed:** $sections" >> "$output_file"
    echo "- **Decision:** $decision" >> "$output_file"
    echo "- **Reasoning:** $reasoning" >> "$output_file"
    echo "" >> "$output_file"
  done
  
  log_success "Report generated: $output_file"
}

# Generate a quick summary for terminal output
# Usage: print_summary
print_summary() {
  local counts=$(count_reviews)
  local completed=$(echo "$counts" | jq -r '.completed')
  local failed=$(echo "$counts" | jq -r '.failed')
  
  echo ""
  separator
  echo "  GAUNTLET SUMMARY"
  separator
  echo ""
  echo "Reviews Completed: $completed"
  echo "Reviews Failed: $failed"
  echo ""
  
  # Count findings
  local critical=0 high=0 medium=0 low=0 info=0
  
  for review_file in "$REVIEWS_DIR"/*.json; do
    [[ ! -f "$review_file" ]] && continue
    local status=$(jq -r '.status' "$review_file")
    [[ "$status" != "completed" ]] && continue
    
    critical=$((critical + $(jq '[.findings[] | select(.severity == "critical")] | length' "$review_file")))
    high=$((high + $(jq '[.findings[] | select(.severity == "high")] | length' "$review_file")))
    medium=$((medium + $(jq '[.findings[] | select(.severity == "medium")] | length' "$review_file")))
    low=$((low + $(jq '[.findings[] | select(.severity == "low")] | length' "$review_file")))
    info=$((info + $(jq '[.findings[] | select(.severity == "info")] | length' "$review_file")))
  done
  
  echo "Findings:"
  echo "  🔴 Critical: $critical"
  echo "  🟠 High: $high"
  echo "  🟡 Medium: $medium"
  echo "  🟢 Low: $low"
  echo "  ℹ️  Info: $info"
  echo ""
}
