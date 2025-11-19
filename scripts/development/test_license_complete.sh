#!/bin/bash
# Complete License API Testing Script

set -e

LICENSE_ID="lic_71c71ab0299b4e28a56e21b7ee99009a"
MACHINE_FP="machine-001"

echo "==============================================="
echo "🧪 KillCode License System - API Test Suite"
echo "==============================================="
echo ""

# Test 1: Get License Details
echo "📋 Test 1: GET License Details"
echo "-------------------------------"
curl -s "http://localhost:8080/api/v1/license/$LICENSE_ID" | python3 -m json.tool
echo ""

# Test 2: License Verification (HMAC)
echo "🔐 Test 2: License Verification with HMAC"
echo "------------------------------------------"
TIMESTAMP=$(date +%s)
SHARED_SECRET=$(docker exec killcode-mongodb mongosh killcode --quiet --eval "print(db.licenses.findOne({license_id: '$LICENSE_ID'}).shared_secret)")
SIGNATURE_DATA="${LICENSE_ID}${TIMESTAMP}"
SIGNATURE=$(echo -n "$SIGNATURE_DATA" | openssl dgst -sha256 -hmac "$SHARED_SECRET" | awk '{print $2}')

echo "Timestamp: $TIMESTAMP"
echo "Signature: $SIGNATURE"
echo ""

VERIFY_RESPONSE=$(curl -s -X POST "http://localhost:8080/api/v1/verify" \
  -H "Content-Type: application/json" \
  -H "X-License-ID: $LICENSE_ID" \
  -H "X-Timestamp: $TIMESTAMP" \
  -H "X-Signature: $SIGNATURE" \
  -d "{\"license_id\": \"$LICENSE_ID\", \"machine_fingerprint\": \"$MACHINE_FP\", \"timestamp\": $TIMESTAMP}")

echo "$VERIFY_RESPONSE" | python3 -m json.tool
echo ""

# Test 3: Check execution counter incremented
echo "📊 Test 3: Check Execution Counter"
echo "-----------------------------------"
curl -s "http://localhost:8080/api/v1/license/$LICENSE_ID" | python3 -m json.tool | grep -A 1 '"executions_used"\|"last_check_at"\|"last_machine_fingerprint"'
echo ""

# Test 4: Verify again (should increment counter)
echo "🔄 Test 4: Second Verification"
echo "------------------------------"
sleep 2
TIMESTAMP=$(date +%s)
SIGNATURE_DATA="${LICENSE_ID}${TIMESTAMP}"
SIGNATURE=$(echo -n "$SIGNATURE_DATA" | openssl dgst -sha256 -hmac "$SHARED_SECRET" | awk '{print $2}')

curl -s -X POST "http://localhost:8080/api/v1/verify" \
  -H "Content-Type: application/json" \
  -H "X-License-ID: $LICENSE_ID" \
  -H "X-Timestamp: $TIMESTAMP" \
  -H "X-Signature: $SIGNATURE" \
  -d "{\"license_id\": \"$LICENSE_ID\", \"machine_fingerprint\": \"$MACHINE_FP\", \"timestamp\": $TIMESTAMP}" | python3 -m json.tool

echo ""

# Test 5: Test with unauthorized machine
echo "❌ Test 5: Verification with Unauthorized Machine"
echo "------------------------------------------------"
TIMESTAMP=$(date +%s)
UNAUTHORIZED_MACHINE="machine-999"
SIGNATURE_DATA="${LICENSE_ID}${TIMESTAMP}"
SIGNATURE=$(echo -n "$SIGNATURE_DATA" | openssl dgst -sha256 -hmac "$SHARED_SECRET" | awk '{print $2}')

curl -s -X POST "http://localhost:8080/api/v1/verify" \
  -H "Content-Type: application/json" \
  -H "X-License-ID: $LICENSE_ID" \
  -H "X-Timestamp: $TIMESTAMP" \
  -H "X-Signature: $SIGNATURE" \
  -d "{\"license_id\": \"$LICENSE_ID\", \"machine_fingerprint\": \"$UNAUTHORIZED_MACHINE\", \"timestamp\": $TIMESTAMP}" | python3 -m json.tool

echo ""

# Test 6: Final license state
echo "📈 Test 6: Final License State"
echo "--------------------------------"
curl -s "http://localhost:8080/api/v1/license/$LICENSE_ID" | python3 -m json.tool | head -20

echo ""
echo "==============================================="
echo "✅ Test Suite Complete!"
echo "==============================================="
