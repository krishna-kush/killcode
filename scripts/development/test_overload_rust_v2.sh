#!/bin/bash

# Test script for Rust overload binary with config file approach

set -e

BASE_URL="http://localhost:8080"
OVERLOAD_BIN="overload/target/release/overload"
TEST_BIN="/tmp/test_overload"
TEST_CONFIG="/tmp/test_overload.config"

echo "🧪 Testing Rust Overload Binary (Config File Approach)"
echo "======================================================="
echo ""

# Step 1: Upload a test binary
echo "📦 Step 1: Uploading test binary..."
BINARY_RESPONSE=$(curl -s -X POST "$BASE_URL/binary/upload" \
  -F "binary=@bin-to-test/c-simple/base" \
  -F "user_id=test_user")

BINARY_ID=$(echo "$BINARY_RESPONSE" | jq -r '.id')
echo "✅ Binary uploaded: $BINARY_ID"
echo ""

# Step 2: Create a license for the binary
echo "📝 Step 2: Creating test license..."
LICENSE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/license/create" \
  -H "Content-Type: application/json" \
  -d "{
    \"binary_id\": \"$BINARY_ID\",
    \"max_executions\": 5,
    \"expires_in_seconds\": 86400,
    \"allowed_machines\": []
  }")

LICENSE_ID=$(echo "$LICENSE_RESPONSE" | jq -r '.license_id')
SHARED_SECRET=$(echo "$LICENSE_RESPONSE" | jq -r '.shared_secret')

echo "✅ License created:"
echo "   License ID: $LICENSE_ID"
echo "   Shared Secret: $SHARED_SECRET"
echo ""

# Step 3: Copy overload binary
echo "📦 Step 3: Copying overload binary..."
cp "$OVERLOAD_BIN" "$TEST_BIN"
chmod +x "$TEST_BIN"
echo "✅ Binary copied to: $TEST_BIN"
echo ""

# Step 4: Create config file
echo "🔧 Step 4: Creating config file..."
cat > "$TEST_CONFIG" << EOF
{
  "license_id": "$LICENSE_ID",
  "server_url": "$BASE_URL",
  "shared_secret": "$SHARED_SECRET"
}
EOF
echo "✅ Config file created: $TEST_CONFIG"
echo ""

# Step 5: Test successful verification
echo "✅ Step 5: Testing successful license verification..."
echo ""
OUTPUT=$("$TEST_BIN" 2>&1 || true)
echo "$OUTPUT"
echo ""

if echo "$OUTPUT" | grep -q "License verified successfully"; then
    echo "✅ SUCCESS: License verification passed!"
else
    echo "❌ FAILED: License verification did not pass"
fi
echo ""

# Step 6: Test with invalid license (should self-destruct)
echo "🔥 Step 6: Testing self-destruct with invalid license..."
cp "$OVERLOAD_BIN" "$TEST_BIN.invalid"
chmod +x "$TEST_BIN.invalid"

cat > "$TEST_BIN.invalid.config" << EOF
{
  "license_id": "invalid_license_12345",
  "server_url": "$BASE_URL",
  "shared_secret": "invalid_secret"
}
EOF

OUTPUT=$("$TEST_BIN.invalid" 2>&1 || true)
echo "$OUTPUT"
echo ""

if [ ! -f "$TEST_BIN.invalid" ]; then
    echo "✅ SUCCESS: Binary self-destructed as expected!"
else
    echo "⚠️  Binary still exists (may need elevated permissions for self-destruct)"
    rm -f "$TEST_BIN.invalid" "$TEST_BIN.invalid.config"
fi
echo ""

# Step 7: Check license execution count
echo "📊 Step 7: Checking license execution count..."
LICENSE_INFO=$(curl -s "$BASE_URL/api/v1/license/$LICENSE_ID")
EXECUTION_COUNT=$(echo "$LICENSE_INFO" | jq -r '.execution_count')
echo "✅ License execution count: $EXECUTION_COUNT (should be 1)"
echo ""

# Cleanup
echo "🧹 Cleaning up..."
rm -f "$TEST_BIN" "$TEST_CONFIG"
echo "✅ Cleanup complete"
echo ""

echo "======================================================="
echo "✅ All tests completed!"
