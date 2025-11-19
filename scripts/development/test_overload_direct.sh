#!/bin/bash

# Direct test of Rust overload binary using existing license from DB

set -e

BASE_URL="http://localhost:8080"
OVERLOAD_BIN="overload/target/release/overload"
TEST_BIN="/tmp/test_rust_overload"
TEST_CONFIG="/tmp/test_rust_overload.config"

echo "🧪 Testing Rust Overload Binary"
echo "================================="
echo ""

# Step 1: Create a fresh license through MongoDB
echo "📝 Step 1: Creating test license in database..."

# Generate IDs using system tools
TMP_UUID=$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]')
LICENSE_ID_VALUE="lic_${TMP_UUID}"
SHARED_SECRET=$(openssl rand -hex 32)
BINARY_ID="bin_test_overload"

# Insert into MongoDB with RFC3339 formatted dates
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
EXPIRES_AT=$(date -u -d "+24 hours" +"%Y-%m-%dT%H:%M:%S.%3NZ")

docker exec killcode-mongodb mongosh killcode --quiet --eval "
db.licenses.insertOne({
    license_id: '$LICENSE_ID_VALUE',
    binary_id: '$BINARY_ID',
    user_id: 'test_user',
    shared_secret: '$SHARED_SECRET',
    executions_used: 0,
    max_executions: 10,
    allowed_machines: [],
    created_at: '$CREATED_AT',
    expires_at: '$EXPIRES_AT',
    updated_at: '$CREATED_AT',
    revoked: false
});
" >/dev/null

echo "✅ License created:"
echo "   License ID: $LICENSE_ID_VALUE"
echo "   Shared Secret: $SHARED_SECRET"
echo ""

# Step 2: Copy overload binary
echo "📦 Step 2: Preparing test binary..."
cp "$OVERLOAD_BIN" "$TEST_BIN"
chmod +x "$TEST_BIN"
echo "✅ Binary ready: $TEST_BIN"
echo ""

# Step 3: Create config file
echo "🔧 Step 3: Creating config file..."
cat > "$TEST_CONFIG" << EOF
{
  "license_id": "$LICENSE_ID_VALUE",
  "server_url": "$BASE_URL",
  "shared_secret": "$SHARED_SECRET"
}
EOF
echo "✅ Config created"
cat "$TEST_CONFIG" | jq .
echo ""

# Step 4: Test successful verification
echo "✅ Step 4: Testing license verification..."
echo ""
OUTPUT=$("$TEST_BIN" 2>&1 || true)
echo "$OUTPUT"
echo ""

if echo "$OUTPUT" | grep -q "License verified successfully"; then
    echo "✅ SUCCESS: License verification passed!"
    
    # Check execution count
    COUNT=$(docker exec killcode-mongodb mongosh killcode --quiet --eval "print(db.licenses.findOne({license_id: '$LICENSE_ID_VALUE'}).executions_used)")
    echo "📊 Execution count: $COUNT (should be 1)"
else
    echo "❌ FAILED: License verification did not pass"
fi
echo ""

# Cleanup
echo "🧹 Cleaning up..."
rm -f "$TEST_BIN" "$TEST_CONFIG"
docker exec killcode-mongodb mongosh killcode --quiet --eval "db.licenses.deleteOne({license_id: '$LICENSE_ID_VALUE'})"
echo "✅ Cleanup complete"
echo ""

echo "================================="
echo "✅ Test completed!"
