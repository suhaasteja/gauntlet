#!/bin/bash
# Gauntlet - Utility Functions
# Shared helpers for logging, timestamps, and common operations

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
  if [[ "${DEBUG:-}" == "1" ]]; then
    echo -e "${CYAN}[DEBUG]${NC} $1"
  fi
}

# Get current timestamp in ISO 8601 format
timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Check if jq is installed
check_jq() {
  if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Install it with: brew install jq"
    exit 1
  fi
}

# Check if a file exists and is not empty
file_exists_nonempty() {
  [[ -f "$1" && -s "$1" ]]
}

# Safe jq read with error handling
jq_read() {
  local file="$1"
  local query="$2"
  
  if [[ ! -f "$file" ]]; then
    echo "null"
    return 1
  fi
  
  jq -r "$query" "$file" 2>/dev/null || echo "null"
}

# Safe jq update with atomic write
jq_update() {
  local file="$1"
  local update="$2"
  
  if [[ ! -f "$file" ]]; then
    log_error "File not found: $file"
    return 1
  fi
  
  jq "$update" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Generate a unique ID
generate_id() {
  local prefix="$1"
  echo "${prefix}-$(date +%s)-$$"
}

# Print a separator line
separator() {
  echo "=============================================="
}

# Print a subseparator line
subseparator() {
  echo "----------------------------------------"
}
