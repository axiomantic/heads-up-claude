#!/bin/bash
# Test script to verify usage data extraction works

set -e

echo "Testing usage data extraction..."
echo ""

# Test 1: Run the expect script
echo "1. Testing get_usage.exp..."
if ./get_usage.exp > /tmp/test_usage_raw.txt 2>&1; then
    echo "   ✓ Expect script executed successfully"
else
    echo "   ✗ Expect script failed"
    exit 1
fi

# Test 2: Check if we got usage data
echo "2. Checking for usage data in output..."
if grep -q "Current session" /tmp/test_usage_raw.txt; then
    echo "   ✓ Found 'Current session' in output"
else
    echo "   ✗ Missing 'Current session' in output"
    cat /tmp/test_usage_raw.txt
    exit 1
fi

if grep -q "Current week" /tmp/test_usage_raw.txt; then
    echo "   ✓ Found 'Current week' in output"
else
    echo "   ✗ Missing 'Current week' in output"
    exit 1
fi

# Test 3: Parse the data
echo "3. Parsing usage data..."
./test_parse.sh > /tmp/test_parsed.txt
cat /tmp/test_parsed.txt

# Test 4: Verify parsed data format
echo "4. Verifying parsed data format..."
if grep -qE "Session: [0-9]+%" /tmp/test_parsed.txt; then
    echo "   ✓ Session percentage found"
else
    echo "   ✗ Session percentage format incorrect"
    exit 1
fi

if grep -qE "Weekly: [0-9]+%" /tmp/test_parsed.txt; then
    echo "   ✓ Weekly percentage found"
else
    echo "   ✗ Weekly percentage format incorrect"
    exit 1
fi

echo ""
echo "All tests passed! ✓"
echo ""
echo "Usage data extraction is working correctly."
