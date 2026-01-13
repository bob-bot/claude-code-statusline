#!/usr/bin/env bash
set -euo pipefail 2>/dev/null || set -eu  # Conditional pipefail for POSIX compatibility

# ============================================================
# PLATFORM DETECTION
# ============================================================

detect_platform() {
  case "${OSTYPE:-}" in
    darwin*) echo "macos" ;;
    linux*) grep -q Microsoft /proc/version 2>/dev/null && echo "wsl" || echo "linux" ;;
    msys*|mingw*|cygwin*) echo "mingw" ;;
    *) uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "unknown" ;;
  esac
}

readonly PLATFORM=$(detect_platform)

# ============================================================
# CONFIGURATION
# ============================================================
readonly BAR_WIDTH=15
readonly BAR_FILLED="█"
readonly BAR_EMPTY="░"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly ORANGE='\033[0;33m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'

# Derived constants
readonly SEPARATOR="${GRAY}|${NC}"
readonly NULL_VALUE="null"
readonly CONTEXT_DEFAULT=200000

# Platform-specific icons (ASCII fallback for MINGW)
case "$PLATFORM" in
  mingw)
    readonly MODEL_ICON=">"
    readonly CONTEXT_ICON="["
    readonly DIR_ICON="@"
    readonly GIT_ICON="*"
    ;;
  *)
    readonly MODEL_ICON="🚀"
    readonly CONTEXT_ICON="🔥"
    readonly DIR_ICON="📂"
    readonly GIT_ICON="🎋"
    ;;
esac

# Git state constants
readonly STATE_NOT_REPO="not_repo"
readonly STATE_CLEAN="clean"
readonly STATE_DIRTY="dirty"

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

# String utilities
get_dirname() { echo "${1##*/}"; }
sep() { echo -n " ${SEPARATOR} "; }

# Conditional append helper (DRY pattern)
append_if() {
  local value="$1"
  local text="$2"
  if [ "$value" != "0" ] 2>/dev/null && [ -n "$value" ] && [ "$value" != "$NULL_VALUE" ]; then
    echo -n " $text"
  fi
}

# Check git version for porcelain v2 support (requires git 2.11+)
# Cache result for performance
check_git_version() {
  # Return cached result if available
  [ -n "${GIT_VERSION_CHECKED:-}" ] && return "${GIT_VERSION_OK:-1}"

  GIT_VERSION_CHECKED=1
  command -v git >/dev/null 2>&1 || { GIT_VERSION_OK=1; return 1; }

  local version
  version=$(git --version 2>/dev/null | awk '{print $3}')
  [ -z "$version" ] && { GIT_VERSION_OK=1; return 1; }

  # Semantic version comparison: >= 2.11
  local major minor
  IFS='.' read -r major minor _ << EOF
$version
EOF

  if [ "$major" -gt 2 ] || ([ "$major" -eq 2 ] && [ "$minor" -ge 11 ]); then
    GIT_VERSION_OK=0
    return 0
  else
    GIT_VERSION_OK=1
    return 1
  fi
}

# ============================================================
# FUNCTIONS
# ============================================================

parse_claude_input() {
  local input="$1"

  local parsed
  parsed=$(echo "$input" | jq -r '
    .model.display_name,
    .workspace.current_dir,
    (.context_window.context_window_size // 200000),
    (
      (.context_window.current_usage.input_tokens // 0) +
      (.context_window.current_usage.cache_creation_input_tokens // 0) +
      (.context_window.current_usage.cache_read_input_tokens // 0)
    ),
    (.cost.total_cost_usd // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0)
  ' 2>/dev/null) || {
    echo "Error: Failed to parse JSON input" >&2
    return 1
  }

  echo "$parsed"
}

build_progress_bar() {
  local percent="$1"
  local filled=$((percent * BAR_WIDTH / 100))
  local empty=$((BAR_WIDTH - filled))

  # Simplified: single printf with tr for each part
  printf "%${filled}s" | tr ' ' "$BAR_FILLED"
  printf "%${empty}s" | tr ' ' "$BAR_EMPTY"
}

# ============================================================
# GIT OPERATIONS (Optimized - 7 calls reduced to 2)
# ============================================================

get_git_info() {
  local current_dir="$1"
  local git_opts=()

  [ -n "$current_dir" ] && [ "$current_dir" != "$NULL_VALUE" ] && git_opts=(-C "$current_dir")

  # Check if git repo
  git "${git_opts[@]}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "$STATE_NOT_REPO"
    return 0
  }

  # Single git status call with all info (replaces 5 separate calls)
  # Requires Git 2.11+ (Dec 2016) for --porcelain=v2
  local status_output
  status_output=$(git "${git_opts[@]}" status --porcelain=v2 --branch --untracked-files=all 2>/dev/null) || {
    echo "$STATE_NOT_REPO"
    return 0
  }

  # Parse porcelain v2 output
  local branch upstream ahead behind
  while IFS= read -r line; do
    case "$line" in
      "# branch.head "*)
        branch="${line#\# branch.head }"
        ;;
      "# branch.upstream "*)
        upstream="${line#\# branch.upstream }"
        ;;
      "# branch.ab "*)
        local ab="${line#\# branch.ab }"
        ahead="${ab%% *}"
        ahead="${ahead#+}"
        behind="${ab##* }"
        behind="${behind#-}"
        ;;
    esac
  done << EOF
$status_output
EOF

  # Default values
  branch="${branch:-(detached HEAD)}"
  ahead="${ahead:-0}"
  behind="${behind:-0}"

  # Count modified files (lines not starting with #)
  local file_lines
  file_lines=$(echo "$status_output" | grep -v '^#')
  local total_files=0
  [ -n "$file_lines" ] && total_files=$(echo "$file_lines" | wc -l | tr -d ' ')

  # Clean state if no files
  if [ "$total_files" -eq 0 ]; then
    echo "$STATE_CLEAN|$branch|$ahead|$behind"
    return 0
  fi

  # Get line changes (single diff HEAD call replaces 2 separate cached + unstaged calls)
  local added removed
  read -r added removed << EOF
$(git "${git_opts[@]}" diff HEAD --numstat 2>/dev/null | awk '{a+=$1; r+=$2} END {print a+0, r+0}')
EOF

  echo "$STATE_DIRTY|$branch|$total_files|$added|$removed|$ahead|$behind"
}

# ============================================================
# FORMATTING FUNCTIONS (SOLID - Single Responsibility)
# ============================================================

format_ahead_behind() {
  local ahead="$1"
  local behind="$2"
  local output=""

  [ "$ahead" -gt 0 ] 2>/dev/null && output+=" ${GREEN}↑${ahead}${NC}"
  [ "$behind" -gt 0 ] 2>/dev/null && output+=" ${RED}↓${behind}${NC}"

  [ -n "$output" ] && echo "${GRAY}|${NC}${output}"
}

format_git_not_repo() {
  echo " ${ORANGE}(not a git repository)${NC}"
}

format_git_clean() {
  local branch="$1" ahead="$2" behind="$3"

  local output="${GRAY}(${NC}${MAGENTA}${branch}${NC}"
  local ahead_behind
  ahead_behind=$(format_ahead_behind "$ahead" "$behind")
  [ -n "$ahead_behind" ] && output+=" $ahead_behind"
  output+="${GRAY})${NC}"

  echo " $output"
}

format_git_dirty() {
  local branch="$1" files="$2" added="$3" removed="$4" ahead="$5" behind="$6"

  local output="${GRAY}(${NC}${MAGENTA}${branch}${NC} ${GRAY}|${NC} ${GRAY}${files} files${NC}"
  output+=$(append_if "$added" "${GREEN}+${added}${NC}")
  output+=$(append_if "$removed" "${RED}-${removed}${NC}")

  local ahead_behind
  ahead_behind=$(format_ahead_behind "$ahead" "$behind")
  [ -n "$ahead_behind" ] && output+=" $ahead_behind"
  output+="${GRAY})${NC}"

  echo " $output"
}

format_git_info() {
  local git_data="$1"

  # Parse state
  local state
  IFS='|' read -r state _ << EOF
$git_data
EOF

  case "$state" in
    $STATE_NOT_REPO)
      format_git_not_repo
      ;;
    $STATE_CLEAN)
      local branch ahead behind
      IFS='|' read -r _ branch ahead behind << EOF
$git_data
EOF
      format_git_clean "$branch" "$ahead" "$behind"
      ;;
    $STATE_DIRTY)
      local branch files added removed ahead behind
      IFS='|' read -r _ branch files added removed ahead behind << EOF
$git_data
EOF
      format_git_dirty "$branch" "$files" "$added" "$removed" "$ahead" "$behind"
      ;;
  esac
}

# ============================================================
# COMPONENT BUILDERS (Open/Closed Principle)
# ============================================================

build_model_component() {
  local model_name="$1"
  echo "${MODEL_ICON} ${CYAN}${model_name}${NC}"
}

build_context_component() {
  local context_size="$1"
  local current_usage="$2"

  local context_percent=0
  if [[ "$current_usage" != "0" && "$context_size" -gt 0 ]]; then
    context_percent=$((current_usage * 100 / context_size))
  fi

  local bar
  bar=$(build_progress_bar "$context_percent")
  echo "${CONTEXT_ICON} ${GRAY}${bar}${NC} ${context_percent}%"
}

build_directory_component() {
  local current_dir="$1"

  local dir_name
  if [ -n "$current_dir" ] && [ "$current_dir" != "$NULL_VALUE" ]; then
    dir_name=$(get_dirname "$current_dir")
  else
    dir_name=$(get_dirname "$PWD")
  fi

  echo "${DIR_ICON} ${BLUE}${dir_name}${NC}"
}

build_git_component() {
  local current_dir="$1"
  local git_data git_info

  git_data=$(get_git_info "$current_dir")
  git_info=$(format_git_info "$git_data")

  # Extract state to determine emoji placement
  local state
  IFS='|' read -r state _ << EOF
$git_data
EOF

  if [ "$state" = "$STATE_NOT_REPO" ]; then
    echo "$git_info"
  else
    echo " ${GIT_ICON}${git_info}"
  fi
}

build_cost_component() {
  local cost_usd="$1"

  if [[ -n "$cost_usd" && "$cost_usd" != "0" && "$cost_usd" != "$NULL_VALUE" ]]; then
    echo "💵 ${GREEN}\$$(printf "%.2f" "$cost_usd")${NC}"
  fi
}

build_lines_component() {
  local lines_added="$1"
  local lines_removed="$2"

  if [[ -n "$lines_added" && -n "$lines_removed" ]] && \
     [[ "$lines_added" != "0" || "$lines_removed" != "0" ]] && \
     [[ "$lines_added" != "$NULL_VALUE" && "$lines_removed" != "$NULL_VALUE" ]]; then
    echo "✏️  ${GREEN}+${lines_added}${NC}/${RED}-${lines_removed}${NC}"
  fi
}

# ============================================================
# ASSEMBLY (KISS - Simple orchestration)
# ============================================================

assemble_statusline() {
  local model_part="$1"
  local context_part="$2"
  local dir_part="$3"
  local git_part="$4"
  local cost_part="$5"
  local lines_part="$6"

  # Build output with separators
  local output="${model_part}$(sep)${context_part}$(sep)${dir_part}${git_part}"

  # Add optional components
  [ -n "$cost_part" ] && output+="$(sep)${cost_part}"
  [ -n "$lines_part" ] && output+="$(sep)${lines_part}"

  echo -e "$output"
}

# ============================================================
# MAIN (Simplified orchestration only)
# ============================================================

main() {
  # Check dependencies
  command -v jq >/dev/null 2>&1 || {
    echo "Error: jq required" >&2
    exit 1
  }

  # Read input (POSIX-compatible: cat instead of < /dev/stdin)
  local input
  input=$(cat) || {
    echo "Error: Failed to read stdin" >&2
    exit 1
  }

  # Parse JSON
  local parsed
  parsed=$(parse_claude_input "$input") || exit 1

  # Extract fields
  local model_name current_dir context_size current_usage cost_usd lines_added lines_removed
  {
    read -r model_name
    read -r current_dir
    read -r context_size
    read -r current_usage
    read -r cost_usd
    read -r lines_added
    read -r lines_removed
  } << EOF
$parsed
EOF

  # Build components
  local model_part context_part dir_part git_part cost_part lines_part
  model_part=$(build_model_component "$model_name")
  context_part=$(build_context_component "$context_size" "$current_usage")
  dir_part=$(build_directory_component "$current_dir")
  git_part=$(build_git_component "$current_dir")
  cost_part=$(build_cost_component "$cost_usd")
  lines_part=$(build_lines_component "$lines_added" "$lines_removed")

  # Assemble and output
  assemble_statusline "$model_part" "$context_part" "$dir_part" "$git_part" "$cost_part" "$lines_part"
}

main "$@"