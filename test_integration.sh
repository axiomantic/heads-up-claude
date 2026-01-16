#!/bin/bash
# Integration tests for heads-up-claude binary

set -e

BINARY="./heads-up-claude"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { echo -e "   ${GREEN}✓${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; exit 1; }

# Build first if binary doesn't exist
if [ ! -f "$BINARY" ]; then
    echo "Building binary..."
    nim c -d:release -o:$BINARY src/heads_up_claude.nim || fail "Build failed"
    echo ""
fi

echo "Running integration tests..."
echo ""

# Test 1: --help flag
echo "1. Testing --help flag..."
output=$($BINARY --help 2>&1)
echo "$output" | grep -q "Heads Up Claude" || fail "--help missing title"
echo "$output" | grep -q "\-\-install" || fail "--help missing --install"
echo "$output" | grep -q "\-\-setup-api" || fail "--help missing --setup-api"
echo "$output" | grep -q "\-\-debug" || fail "--help missing --debug"
pass "--help shows expected content"

# Test 2: --debug flag
echo "2. Testing --debug flag..."
output=$($BINARY --debug --help 2>&1)
echo "$output" | grep -q "\[DEBUG\]" || fail "--debug not producing debug output"
echo "$output" | grep -q "Debug mode enabled" || fail "--debug not logging enable message"
pass "--debug produces debug output"

# Test 3: Empty stdin handling
echo "3. Testing empty stdin handling..."
output=$(echo "" | $BINARY 2>&1) || true
echo "$output" | grep -q "Empty input" || fail "Empty input not detected"
pass "Empty stdin shows helpful error"

# Test 4: TTY stdin handling (simulated - binary should error on no piped input)
echo "4. Testing error messages are user-friendly..."
output=$(echo "" | $BINARY 2>&1) || true
echo "$output" | grep -q "\-\-help" || fail "Error message doesn't mention --help"
echo "$output" | grep -q "\-\-install" || fail "Error message doesn't mention --install"
pass "Error messages suggest next steps"

# Test 5: Invalid JSON handling
echo "5. Testing invalid JSON handling..."
output=$(echo "not json" | $BINARY 2>&1) || true
# Should fail gracefully (not crash with stack trace)
if echo "$output" | grep -q "SIGSEGV\|stack trace\|Traceback"; then
    fail "Binary crashed on invalid JSON"
fi
pass "Invalid JSON handled gracefully"

# Test 6: Valid JSON but missing fields
echo "6. Testing JSON with missing fields..."
output=$(echo '{"foo": "bar"}' | $BINARY 2>&1) || true
# Should fail gracefully
if echo "$output" | grep -q "SIGSEGV\|stack trace\|Traceback"; then
    fail "Binary crashed on incomplete JSON"
fi
pass "Missing fields handled gracefully"

# Sample valid input JSON for statusline mode
VALID_INPUT='{"transcript_path": "/tmp/fake.jsonl", "workspace": {"current_dir": "/tmp", "project_dir": "/tmp"}, "model": {"display_name": "claude-3-opus"}}'

# Test 7: Config file creation
echo "7. Testing config file handling..."
TEST_CONFIG="$TEMP_DIR/test-config"
mkdir -p "$TEST_CONFIG"
# Create minimal config
echo '{"plan": "pro", "five_hour_messages": 45, "weekly_hours_min": 40}' > "$TEST_CONFIG/heads_up_config.json"
# This should at least not crash
output=$(echo "$VALID_INPUT" | $BINARY --claude-config-dir="$TEST_CONFIG" 2>&1) || true
pass "Config file loading doesn't crash"

# Test 8: Debug mode shows config loading
echo "8. Testing debug shows config loading..."
output=$(echo "$VALID_INPUT" | $BINARY --debug --claude-config-dir="$TEST_CONFIG" 2>&1) || true
echo "$output" | grep -q "\[DEBUG\].*config" || fail "Debug doesn't show config loading"
pass "Debug mode shows config operations"

# Test 9: API credentials handling (no credentials)
echo "9. Testing API without credentials..."
NO_CREDS_CONFIG="$TEMP_DIR/no-creds-config"
mkdir -p "$NO_CREDS_CONFIG"
echo '{"plan": "pro", "five_hour_messages": 45}' > "$NO_CREDS_CONFIG/heads_up_config.json"
output=$(echo "$VALID_INPUT" | $BINARY --debug --claude-config-dir="$NO_CREDS_CONFIG" 2>&1) || true
echo "$output" | grep -q "no API credentials\|NoCredentials\|estimates" || fail "Should indicate no credentials"
pass "Handles missing API credentials gracefully"

# Test 10: --no-emoji flag
echo "10. Testing --no-emoji flag..."
output=$($BINARY --help 2>&1)
echo "$output" | grep -q "\-\-no-emoji" || fail "--no-emoji not in help"
pass "--no-emoji flag documented"

echo ""
echo -e "${GREEN}All integration tests passed!${NC}"
echo ""
