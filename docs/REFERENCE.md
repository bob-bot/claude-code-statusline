# Claude Code Statusline - Official Documentation Reference

> Comprehensive reference documentation for Claude Code's custom statusline feature
> Source: https://code.claude.com/docs/en/statusline
> Last updated: 2026-01-13

## Table of Contents

- [Overview](#overview)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [JSON Input Structure](#json-input-structure)
- [Example Scripts](#example-scripts)
  - [Simple Status Line](#simple-status-line)
  - [Git-Aware Status Line](#git-aware-status-line)
  - [Python Example](#python-example)
  - [Node.js Example](#nodejs-example)
  - [Helper Function Approach](#helper-function-approach)
  - [Context Window Usage](#context-window-usage)
- [Tips](#tips)
- [Troubleshooting](#troubleshooting)

---

## Overview

The Claude Code statusline is a customizable status display that appears at the bottom of the Claude Code interface, similar to how terminal prompts (PS1) work in shells like Oh-my-zsh. It allows you to display contextual information about your current session, including:

- Model information
- Current working directory
- Git repository status
- Context window usage
- Cost tracking
- Lines added/removed
- And more...

## Configuration

There are two ways to set up a custom status line:

### Method 1: Interactive Setup (Recommended)

Run the `/statusline` command in Claude Code:

```bash
/statusline
```

Claude Code will help you set up a custom status line. By default, it tries to reproduce your terminal's prompt, but you can provide additional instructions:

```bash
/statusline show the model name in orange
```

### Method 2: Manual Configuration

Add a `statusLine` configuration to your `.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
```

**Configuration Options:**

- `type`: Must be `"command"`
- `command`: Path to your statusline script (can be relative or absolute)
- `padding` (optional): Set to `0` to let status line extend to the edge, or use a positive integer for padding

## How It Works

Understanding the statusline execution model:

1. **Update Trigger**: The status line is updated when conversation messages update
2. **Rate Limiting**: Updates run at most every 300 milliseconds (prevents excessive calls)
3. **Input Method**: Claude Code passes contextual information as JSON via **stdin**
4. **Output Method**: The first line of **stdout** from your command becomes the status line text
5. **Styling**: ANSI color codes are supported for styling your status line
6. **Execution**: Your script runs synchronously and should complete quickly

**Important Notes:**

- Only the **first line** of stdout is used
- Subsequent lines are ignored
- Output to stderr is not displayed
- Script must be executable (`chmod +x`)
- Keep execution time minimal to avoid UI lag

## JSON Input Structure

Your statusline command receives a comprehensive JSON object via stdin containing all session context:

```json
{
  "hook_event_name": "Status",
  "session_id": "abc123...",
  "transcript_path": "/path/to/transcript.json",
  "cwd": "/current/working/directory",
  "model": {
    "id": "claude-opus-4-1",
    "display_name": "Opus"
  },
  "workspace": {
    "current_dir": "/current/working/directory",
    "project_dir": "/original/project/directory"
  },
  "version": "1.0.80",
  "output_style": {
    "name": "default"
  },
  "cost": {
    "total_cost_usd": 0.01234,
    "total_duration_ms": 45000,
    "total_api_duration_ms": 2300,
    "total_lines_added": 156,
    "total_lines_removed": 23
  },
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": 4521,
    "context_window_size": 200000,
    "current_usage": {
      "input_tokens": 8500,
      "output_tokens": 1200,
      "cache_creation_input_tokens": 5000,
      "cache_read_input_tokens": 2000
    }
  }
}
```

### Field Descriptions

#### Top-Level Fields

- `hook_event_name`: Always `"Status"` for statusline updates
- `session_id`: Unique identifier for the current session
- `transcript_path`: Path to the conversation transcript JSON file
- `cwd`: Current working directory
- `version`: Claude Code version number

#### `model` Object

- `id`: Full model identifier (e.g., `"claude-opus-4-1"`)
- `display_name`: Human-readable model name (e.g., `"Opus"`)

#### `workspace` Object

- `current_dir`: Current working directory (can change during session)
- `project_dir`: Original project directory where session started

#### `output_style` Object

- `name`: Current output style mode (e.g., `"default"`, `"concise"`, `"explanatory"`)

#### `cost` Object

Session-wide cumulative metrics:

- `total_cost_usd`: Total cost in USD for the session (float)
- `total_duration_ms`: Total time elapsed in milliseconds
- `total_api_duration_ms`: Total API call duration in milliseconds
- `total_lines_added`: Total lines of code added by Claude
- `total_lines_removed`: Total lines of code removed by Claude

#### `context_window` Object

Token usage information:

- `total_input_tokens`: Cumulative input tokens across entire session
- `total_output_tokens`: Cumulative output tokens across entire session
- `context_window_size`: Maximum context window size (e.g., 200000 for Claude Opus)
- `current_usage`: Object containing current context window state (may be `null` before first message)
  - `input_tokens`: Input tokens in current context
  - `output_tokens`: Output tokens generated
  - `cache_creation_input_tokens`: Tokens written to prompt cache
  - `cache_read_input_tokens`: Tokens read from prompt cache

**Important**: Use `current_usage` (not `total_*`) for accurate context percentage calculations, as it reflects the actual context window state.

## Example Scripts

### Simple Status Line

Minimal bash implementation showing model and directory:

```bash
#!/bin/bash
# Read JSON input from stdin
input=$(cat)

# Extract values using jq
MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir')

echo "[$MODEL_DISPLAY] 📁 ${CURRENT_DIR##*/}"
```

**Output Example:**
```
[Opus] 📁 my-project
```

### Git-Aware Status Line

Adds git branch information:

```bash
#!/bin/bash
# Read JSON input from stdin
input=$(cat)

# Extract values using jq
MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir')

# Show git branch if in a git repo
GIT_BRANCH=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        GIT_BRANCH=" | 🌿 $BRANCH"
    fi
fi

echo "[$MODEL_DISPLAY] 📁 ${CURRENT_DIR##*/}$GIT_BRANCH"
```

**Output Example:**
```
[Opus] 📁 my-project | 🌿 main
```

### Python Example

Python implementation with git branch detection:

```python
#!/usr/bin/env python3
import json
import sys
import os

# Read JSON from stdin
data = json.load(sys.stdin)

# Extract values
model = data['model']['display_name']
current_dir = os.path.basename(data['workspace']['current_dir'])

# Check for git branch
git_branch = ""
if os.path.exists('.git'):
    try:
        with open('.git/HEAD', 'r') as f:
            ref = f.read().strip()
            if ref.startswith('ref: refs/heads/'):
                git_branch = f" | 🌿 {ref.replace('ref: refs/heads/', '')}"
    except:
        pass

print(f"[{model}] 📁 {current_dir}{git_branch}")
```

**Output Example:**
```
[Opus] 📁 my-project | 🌿 main
```

### Node.js Example

JavaScript/Node.js implementation:

```javascript
#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Read JSON from stdin
let input = '';
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
    const data = JSON.parse(input);

    // Extract values
    const model = data.model.display_name;
    const currentDir = path.basename(data.workspace.current_dir);

    // Check for git branch
    let gitBranch = '';
    try {
        const headContent = fs.readFileSync('.git/HEAD', 'utf8').trim();
        if (headContent.startsWith('ref: refs/heads/')) {
            gitBranch = ` | 🌿 ${headContent.replace('ref: refs/heads/', '')}`;
        }
    } catch (e) {
        // Not a git repo or can't read HEAD
    }

    console.log(`[${model}] 📁 ${currentDir}${gitBranch}`);
});
```

**Output Example:**
```
[Opus] 📁 my-project | 🌿 main
```

### Helper Function Approach

For more complex bash scripts, create reusable helper functions:

```bash
#!/bin/bash
# Read JSON input once
input=$(cat)

# Helper functions for common extractions
get_model_name() { echo "$input" | jq -r '.model.display_name'; }
get_current_dir() { echo "$input" | jq -r '.workspace.current_dir'; }
get_project_dir() { echo "$input" | jq -r '.workspace.project_dir'; }
get_version() { echo "$input" | jq -r '.version'; }
get_cost() { echo "$input" | jq -r '.cost.total_cost_usd'; }
get_duration() { echo "$input" | jq -r '.cost.total_duration_ms'; }
get_lines_added() { echo "$input" | jq -r '.cost.total_lines_added'; }
get_lines_removed() { echo "$input" | jq -r '.cost.total_lines_removed'; }
get_input_tokens() { echo "$input" | jq -r '.context_window.total_input_tokens'; }
get_output_tokens() { echo "$input" | jq -r '.context_window.total_output_tokens'; }
get_context_window_size() { echo "$input" | jq -r '.context_window.context_window_size'; }

# Use the helpers
MODEL=$(get_model_name)
DIR=$(get_current_dir)
echo "[$MODEL] 📁 ${DIR##*/}"
```

**Benefits:**
- DRY principle (Don't Repeat Yourself)
- Easier to maintain and extend
- Self-documenting code
- Reusable extraction logic

### Context Window Usage

Display accurate context window usage percentage:

```bash
#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size')
USAGE=$(echo "$input" | jq '.context_window.current_usage')

if [ "$USAGE" != "null" ]; then
    # Calculate current context from current_usage fields
    CURRENT_TOKENS=$(echo "$USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    PERCENT_USED=$((CURRENT_TOKENS * 100 / CONTEXT_SIZE))
    echo "[$MODEL] Context: ${PERCENT_USED}%"
else
    echo "[$MODEL] Context: 0%"
fi
```

**Important Notes:**

1. **Use `current_usage`, not `total_*`**: The `current_usage` object reflects the actual context window state
2. **Handle `null` values**: `current_usage` may be `null` before the first message
3. **Include all token types**: Sum `input_tokens`, `cache_creation_input_tokens`, and `cache_read_input_tokens`
4. **Context calculation formula**:
   ```
   current_tokens = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
   percentage = (current_tokens * 100) / context_window_size
   ```

**Output Example:**
```
[Opus] Context: 42%
```

## Tips

### Best Practices

1. **Keep it concise**: Status line should fit on one line
2. **Use color wisely**: ANSI colors make information scannable
3. **Use emojis**: If your terminal supports them, emojis provide visual cues
4. **Parse with jq**: Use `jq` for JSON parsing in bash (more reliable than pure bash)
5. **Test offline**: Test your script by running it manually with mock JSON:
   ```bash
   echo '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/test"}}' | ./statusline.sh
   ```
6. **Cache expensive operations**: If you need expensive operations (like complex git queries), consider caching results
7. **Handle null values**: Always check for `null` values in JSON fields
8. **Make it executable**: Don't forget `chmod +x statusline.sh`

### Performance Considerations

- Status line updates frequently (every message update)
- Keep execution time under 100ms for best UX
- Minimize external command calls
- Cache results when possible
- Avoid network operations

### ANSI Color Codes Reference

Common ANSI color codes for styling:

```bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'  # No Color (reset)

# Usage example
echo -e "${CYAN}Model${NC} | ${GREEN}Active${NC}"
```

### Bash String Manipulation

Useful bash patterns for statusline scripts:

```bash
# Get basename (last component of path)
DIR_NAME="${CURRENT_DIR##*/}"

# Remove prefix
BRANCH="${REF#refs/heads/}"

# Remove suffix
FILE="${PATH%.*}"

# Check if variable is set and not empty
[ -n "$VARIABLE" ] && echo "Variable is set"

# Check if variable equals value
[ "$VAR" = "value" ] && echo "Match"

# Null coalescing (use default if null)
VALUE="${VARIABLE:-default}"
```

## Troubleshooting

### Status Line Doesn't Appear

**Check:** Script is executable
```bash
chmod +x ~/.claude/statusline.sh
```

**Check:** Script path in settings.json is correct
```json
{
  "statusLine": {
    "command": "/absolute/path/to/statusline.sh"
  }
}
```

**Check:** Script outputs to stdout (not stderr)
```bash
# Wrong - outputs to stderr
echo "Status" >&2

# Correct - outputs to stdout
echo "Status"
```

### Script Errors

**Check:** Script has proper shebang
```bash
#!/bin/bash
```

**Check:** Dependencies are installed
```bash
# Check for jq
command -v jq >/dev/null || echo "jq not found"

# Check for git
command -v git >/dev/null || echo "git not found"
```

**Check:** JSON parsing works
```bash
# Test manually
echo '{"model":{"display_name":"Test"}}' | jq -r '.model.display_name'
```

### Debugging

**Method 1:** Log to file
```bash
#!/bin/bash
input=$(cat)
echo "$input" > /tmp/statusline-debug.json
# ... rest of script
```

**Method 2:** Test with mock data
```bash
cat > test-input.json << 'EOF'
{
  "model": {"display_name": "Opus"},
  "workspace": {"current_dir": "/test"},
  "context_window": {
    "context_window_size": 200000,
    "current_usage": {
      "input_tokens": 50000,
      "cache_creation_input_tokens": 0,
      "cache_read_input_tokens": 0
    }
  }
}
EOF

cat test-input.json | ./statusline.sh
```

**Method 3:** Check exit code
```bash
./statusline.sh < test-input.json
echo "Exit code: $?"
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No output | Script not executable | `chmod +x statusline.sh` |
| JSON parse error | Invalid JSON handling | Use `jq` for parsing |
| Git errors | Not in git repo | Check `git rev-parse --git-dir` first |
| Color codes visible | Terminal doesn't support ANSI | Remove color codes or detect terminal |
| Slow updates | Script takes too long | Optimize or cache expensive operations |

---

## Additional Resources

- **Claude Code Documentation**: https://code.claude.com/docs
- **jq Manual**: https://jqlang.github.io/jq/manual/
- **ANSI Color Codes**: https://en.wikipedia.org/wiki/ANSI_escape_code
- **Git Porcelain Commands**: https://git-scm.com/docs/git-status#_porcelain_format_version_2

---

*This reference document is based on the official Claude Code statusline documentation. For the most up-to-date information, always refer to the official documentation at https://code.claude.com/docs/en/statusline*
