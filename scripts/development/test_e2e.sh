#!/bin/bash
# Complete End-to-End Test of KillCode Binary Protection

set -e

echo "================================================="
echo "🚀 KillCode - Complete E2E Test"
echo "================================================="
echo ""

# Step 1: Upload binary
echo "📤 Step 1: Uploading test binary..."
RESPONSE=$(curl -s -X POST http://localhost:8080/binary/upload \
  -F "binary=@test_hello" \
  -F "name=e2e_test_binary" \
  -F "description=End-to-end test binary")

BINARY_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['binary_id'])")
LICENSE_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('license_id', 'N/A'))")

echo "✅ Binary uploaded!"
echo "   Binary ID: $BINARY_ID"
if [ "$LICENSE_ID" != "N/A" ]; then
    echo "   License ID: $LICENSE_ID"
fi
echo ""

# Step 2: Create a license for the binary (if not already created)
if [ "$LICENSE_ID" == "N/A" ]; then
    echo "📋 Step 2: Creating license for binary..."
    LICENSE_RESPONSE=$(curl -s -X POST http://localhost:8080/api/v1/license/create \
      -H "Content-Type: application/json" \
      -d "{
        \"binary_id\": \"$BINARY_ID\",
        \"max_executions\": 10,
        \"expires_in_seconds\": 3600,
        \"allowed_machines\": [\"e2e-test-machine\"]
      }")
    
    LICENSE_ID=$(echo "$LICENSE_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['license_id'])")
    echo "✅ License created: $LICENSE_ID"
else
    echo "📋 Step 2: License already created during upload: $LICENSE_ID"
fi
echo ""

# Step 3: Check license details
echo "🔍 Step 3: Checking license details..."
curl -s "http://localhost:8080/api/v1/license/$LICENSE_ID" | python3 -m json.tool | head -12
echo ""

# Step 4: Verify the license (simulate overload binary checking in)
echo "🔐 Step 4: Simulating license verification..."
TIMESTAMP=$(date +%s)
MACHINE_FP="e2e-test-machine"
SHARED_SECRET=$(docker exec killcode-mongodb mongosh killcode --quiet --eval "print(db.licenses.findOne({license_id: '$LICENSE_ID'}).shared_secret)")
SIGNATURE_DATA="${LICENSE_ID}${TIMESTAMP}"
SIGNATURE=$(echo -n "$SIGNATURE_DATA" | openssl dgst -sha256 -hmac "$SHARED_SECRET" | awk '{print $2}')

VERIFY_RESPONSE=$(curl -s -X POST "http://localhost:8080/api/v1/verify" \
  -H "Content-Type: application/json" \
  -H "X-License-ID: $LICENSE_ID" \
  -H "X-Timestamp: $TIMESTAMP" \
  -H "X-Signature: $SIGNATURE" \
  -d "{\"license_id\": \"$LICENSE_ID\", \"machine_fingerprint\": \"$MACHINE_FP\", \"timestamp\": $TIMESTAMP}")

echo "$VERIFY_RESPONSE" | python3 -m json.tool
echo ""

# Step 5: Check if binary is ready for download
echo "📥 Step 5: Checking if protected binary is ready..."
sleep 2  # Give weaver time to process
BINARY_INFO=$(curl -s "http://localhost:8080/binary/$BINARY_ID")
echo "$BINARY_INFO" | python3 -m json.tool | grep -E '"status"|"wrapped"' || echo "Binary info: $BINARY_INFO"
echo ""

# Step 6: List all binaries
echo "📚 Step 6: Listing all binaries..."
curl -s "http://localhost:8080/binaries" | python3 -m json.tool | head -30
echo ""

# Step 7: Get execution history
echo "📊 Step 7: Getting execution history..."
curl -s "http://localhost:8080/binary/$BINARY_ID/executions" | python3 -m json.tool | head -20
echo ""

echo "================================================="
echo "✅ End-to-End Test Complete!"
echo "================================================="
echo ""
echo "Summary:"
echo "  • Binary ID: $BINARY_ID"
echo "  • License ID: $LICENSE_ID"
echo "  • Verification: $(echo $VERIFY_RESPONSE | python3 -c 'import sys,json; print(json.load(sys.stdin)[\"message\"])')"
