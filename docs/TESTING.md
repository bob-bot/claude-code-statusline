# Testing Guide

> Comprehensive testing documentation for statusline.sh

## Quick Start

```bash
# Run unit tests
./tests/unit.sh

# Run integration tests
./tests/integration.sh

# Run both
./tests/unit.sh && ./tests/integration.sh
```

## Test Structure

The project includes two types of tests:

- **Unit Tests** (`tests/unit.sh`) - Test individual components and functions
- **Integration Tests** (`tests/integration.sh`) - Test the complete statusline with various scenarios
- **Test Fixtures** (`tests/fixtures/`) - Sample JSON inputs for testing

---

## Manual Testing

### Test 1: Basic Functionality

```bash
# Create test input
cat > test-input.json << 'EOF'
{
  "model": {"display_name": "Opus"},
  "workspace": {"current_dir": "/Users/test/project"},
  "context_window": {
    "context_window_size": 200000,
    "current_usage": {
      "input_tokens": 50000,
      "cache_creation_input_tokens": 10000,
      "cache_read_input_tokens": 5000
    }
  },
  "cost": {
    "total_cost_usd": 0.15,
    "total_lines_added": 156,
    "total_lines_removed": 23
  }
}
EOF

# Run test
cat test-input.json | ./statusline.sh
```

**Expected output**:
```
🚀 Opus | 🔥 [████████░░░░░░░] 32% | 📂 project 🎋 (branch | ...) | 💵 $0.15 | ✏️  +156/-23
```

### Test 2: Not a Git Repo

```bash
# In a non-git directory
cd /tmp
cat test-input.json | ./statusline.sh
```

**Expected**: Shows "(not a git repository)"

### Test 3: Dirty Git Repo

```bash
# In a git repo with changes
cd /path/to/git/repo
# Make some changes
echo "test" >> file.txt

cat test-input.json | ./statusline.sh
```

**Expected**: Shows file count, +added/-removed lines

### Test 4: Null Values

```bash
# Test with missing cost data
cat > test-null.json << 'EOF'
{
  "model": {"display_name": "Haiku"},
  "workspace": {"current_dir": "/test"},
  "context_window": {
    "context_window_size": 200000
  },
  "cost": {}
}
EOF

cat test-null.json | ./statusline.sh
```

**Expected**: No cost or lines components shown (graceful null handling)

### Test 5: Platform-Specific Icons

```bash
# Test on MinGW
PLATFORM=mingw ./statusline.sh < test-input.json

# Test on macOS
PLATFORM=macos ./statusline.sh < test-input.json
```

**Expected**: ASCII characters on MinGW, emojis on macOS

---

## Automated Testing

### Creating a Test Suite

Example test suite structure:

```bash
#!/bin/bash
# tests.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

passed=0
failed=0

test_case() {
  local name="$1"
  local input="$2"
  local expected_pattern="$3"

  echo -n "Testing: $name... "

  local output
  output=$(echo "$input" | ./statusline.sh)

  if echo "$output" | grep -q "$expected_pattern"; then
    echo -e "${GREEN}PASS${NC}"
    ((passed++))
  else
    echo -e "${RED}FAIL${NC}"
    echo "  Expected pattern: $expected_pattern"
    echo "  Got: $output"
    ((failed++))
  fi
}

# Test cases
test_case "Model name display" \
  '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/test"},"context_window":{"context_window_size":200000}}' \
  "Opus"

test_case "Directory display" \
  '{"model":{"display_name":"Test"},"workspace":{"current_dir":"/home/user/project"},"context_window":{"context_window_size":200000}}' \
  "project"

# Add more test cases...

echo ""
echo "Tests passed: $passed"
echo "Tests failed: $failed"

[ $failed -eq 0 ] && exit 0 || exit 1
```

Run tests:
```bash
chmod +x tests.sh
./tests.sh
```

---

## Integration Testing

### Testing with Claude Code

1. Update `.claude/settings.json`:
```json
{
  "statusLine": {
    "command": "/path/to/statusline.sh"
  }
}
```

2. Start Claude Code session
3. Verify statusline updates on each message
4. Test different scenarios:
   - Clean git repo
   - Dirty git repo
   - Non-git directory
   - Different context usage levels
   - Cost tracking updates

---

## Platform-Specific Testing

### macOS Testing
```bash
# Test with full emoji support
./statusline.sh < tests/fixtures/test-input.json

# Verify emojis display correctly: 🚀 🔥 📂 🎋 💵 ✏️
```

### Linux Testing
```bash
# Test on Ubuntu/Debian
sudo apt-get install jq git
./tests/unit.sh && ./tests/integration.sh
```

### WSL Testing
```bash
# Test Windows Subsystem for Linux
# Verify emoji support
./statusline.sh < tests/fixtures/test-input.json
```

### MinGW/MSYS Testing
```bash
# Test ASCII fallback mode
PLATFORM=mingw ./statusline.sh < tests/fixtures/test-input.json

# Verify ASCII characters: > @ * instead of emojis
```

---

## Performance Testing

### Measuring Execution Time

Add timing to test:

```bash
# Time the statusline execution
time ./statusline.sh < tests/fixtures/test-input.json
```

**Performance Targets:**
- Total execution: < 100ms
- Git operations: < 50ms
- JSON parsing: < 10ms

### Performance Test Cases

```bash
#!/bin/bash
# performance-test.sh

# Test in clean repo
cd /path/to/clean/repo
time ./statusline.sh < test-input.json

# Test in dirty repo with many changes
cd /path/to/repo/with/changes
time ./statusline.sh < test-input.json

# Test in large repo
cd /path/to/large/repo
time ./statusline.sh < test-input.json
```

---

## Adding New Test Cases

### Unit Test Pattern

```bash
# In tests/unit.sh

test_new_function() {
  local input="test input"
  local expected="expected output"
  local result

  result=$(new_function "$input")

  if [ "$result" = "$expected" ]; then
    echo "✓ test_new_function passed"
    return 0
  else
    echo "✗ test_new_function failed"
    echo "  Expected: $expected"
    echo "  Got: $result"
    return 1
  fi
}
```

### Integration Test Pattern

```bash
# In tests/integration.sh

test_new_scenario() {
  local test_name="New Scenario Test"
  local input='{"model":{"display_name":"Test"},...}'
  local expected_pattern="expected substring"

  run_test "$test_name" "$input" "$expected_pattern"
}
```

---

## Continuous Integration

### GitHub Actions Example

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: sudo apt-get install -y jq git

      - name: Run unit tests
        run: ./tests/unit.sh

      - name: Run integration tests
        run: ./tests/integration.sh

      - name: Test statusline execution
        run: |
          cat tests/fixtures/test-input.json | ./statusline.sh
```

### Multi-Platform CI

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest]

runs-on: ${{ matrix.os }}
```

---

## Debugging Test Failures

### Enable Debug Mode

```bash
# Enable bash debug output
bash -x ./statusline.sh < tests/fixtures/test-input.json
```

### Common Test Failures

| Issue | Symptom | Solution |
|-------|---------|----------|
| **jq not found** | Error: jq command not found | Install jq: `brew install jq` |
| **Git errors** | Error: not a git repository | Run tests in git repo or check git version |
| **Path issues** | Files not found | Verify test script is run from project root |
| **Permission denied** | Cannot execute script | `chmod +x tests/*.sh` |

### Test Isolation

```bash
# Run tests in isolated environment
docker run --rm -v "$PWD:/app" -w /app bash:latest bash -c "
  apt-get update && apt-get install -y jq git
  ./tests/unit.sh && ./tests/integration.sh
"
```

---

## Test Coverage

### What's Tested

- ✅ JSON parsing and field extraction
- ✅ Progress bar rendering
- ✅ Git status parsing (clean, dirty, not a repo)
- ✅ Context usage calculation
- ✅ Platform detection
- ✅ Null value handling
- ✅ Cost and line tracking display

### What's Not Tested

- ⚠️ Actual Claude Code integration (manual verification only)
- ⚠️ Terminal color rendering (visual inspection required)
- ⚠️ Edge cases for extremely large repos (> 10,000 files)

---

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Implementation details
- [REFERENCE.md](REFERENCE.md) - Official statusline specification
- [README](../README.md) - Quick start guide
- [Tests README](../tests/README.md) - Running tests

---

*Last updated: 2026-01-13*
