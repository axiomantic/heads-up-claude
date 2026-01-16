#!/bin/bash
set -e

echo "=== Integration Tests ==="

# Build binaries
echo "Building binaries..."
nim c -d:release -o:/tmp/huc src/huc.nim
nim c -d:release -o:/tmp/hucd src/hucd.nim

# Test huc help
echo "Testing huc --help..."
/tmp/huc --help | grep -q "statusline"

# Test hucd help
echo "Testing hucd --help..."
/tmp/hucd --help | grep -q "daemon"

# Create test environment
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/.claude/heads-up-cache"
mkdir -p "$TEST_DIR/.claude/projects/-test"

# Create minimal config
cat > "$TEST_DIR/.claude/heads_up_config.json" << 'EOF'
{"plan": "pro", "five_hour_messages": 45, "weekly_hours_min": 40}
EOF

# Create minimal daemon config
cat > "$TEST_DIR/.claude/heads-up-cache/hucd.json" << EOF
{
  "version": 1,
  "config_dirs": ["$TEST_DIR/.claude"],
  "scan_interval_minutes": 1,
  "api_interval_minutes": 1,
  "prune_interval_minutes": 1,
  "debug": true
}
EOF

# Create test transcript
cat > "$TEST_DIR/.claude/projects/-test/session.jsonl" << 'EOF'
{"type":"user","timestamp":"2026-01-16T10:00:00.000Z"}
{"type":"assistant","timestamp":"2026-01-16T10:01:00.000Z","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":500,"output_tokens":50}}}
EOF

# Start daemon in background
echo "Starting daemon..."
HOME="$TEST_DIR" /tmp/hucd --config="$TEST_DIR/.claude/heads-up-cache/hucd.json" &
DAEMON_PID=$!

# Wait for status file
echo "Waiting for status file..."
for i in {1..30}; do
    if [ -f "$TEST_DIR/.claude/heads-up-cache/status.json" ]; then
        break
    fi
    sleep 1
done

# Verify status file created
if [ ! -f "$TEST_DIR/.claude/heads-up-cache/status.json" ]; then
    echo "FAIL: Status file not created"
    kill $DAEMON_PID 2>/dev/null
    rm -rf "$TEST_DIR"
    exit 1
fi

echo "Status file created"

# Verify status file has expected content
if ! grep -q '"version": 1' "$TEST_DIR/.claude/heads-up-cache/status.json"; then
    echo "FAIL: Status file invalid"
    kill $DAEMON_PID 2>/dev/null
    rm -rf "$TEST_DIR"
    exit 1
fi

echo "Status file valid"

# Test huc reads status
echo "Testing huc reads status..."
echo '{"workspace":{"project_dir":"'"$TEST_DIR"'"},"model":{"display_name":"claude-sonnet-4"}}' | \
    HOME="$TEST_DIR" /tmp/huc --claude-config-dir="$TEST_DIR/.claude" | grep -q "Pro"

# Cleanup
kill $DAEMON_PID 2>/dev/null || true
rm -rf "$TEST_DIR"
rm -f /tmp/huc /tmp/hucd

echo ""
echo "=== All integration tests passed ==="
