#!/bin/bash
# Test license verification endpoint with HMAC authentication

LICENSE_ID="lic_201ed38709e04200a11f7017c8f7ea4b"
TIMESTAMP=$(date +%s)
MACHINE_FP="dev-machine-001"

echo "=== Testing License Verification ==="
echo "License ID: $LICENSE_ID"
echo "Timestamp: $TIMESTAMP"
echo "Machine: $MACHINE_FP"
echo ""

# Get shared secret from MongoDB
SHARED_SECRET=$(docker exec killcode-mongodb mongosh killcode --quiet --eval "print(db.licenses.findOne({license_id: '$LICENSE_ID'}).shared_secret)")

if [ -z "$SHARED_SECRET" ]; then
    echo "❌ Failed to get shared_secret from database"
    exit 1
fi

echo "Secret: ${SHARED_SECRET:0:16}..."
echo ""

# Generate HMAC-SHA256 signature
SIGNATURE_DATA="${LICENSE_ID}${TIMESTAMP}"
SIGNATURE=$(echo -n "$SIGNATURE_DATA" | openssl dgst -sha256 -hmac "$SHARED_SECRET" -binary | xxd -p -c 256)

echo "Signature data: $SIGNATURE_DATA"
echo "Signature: $SIGNATURE"
echo ""

# Make verification request
echo "=== Verification Response ==="
curl -s -X POST "http://localhost:8080/api/v1/verify" \
  -H "Content-Type: application/json" \
  -H "X-License-ID: $LICENSE_ID" \
  -H "X-Timestamp: $TIMESTAMP" \
  -H "X-Signature: $SIGNATURE" \
  -d "{\"machine_fingerprint\": \"$MACHINE_FP\"}" | jq .

echo ""
echo "=== License Status After Verification ==="
curl -s "http://localhost:8080/api/v1/license/$LICENSE_ID" | jq '{executions_used, max_executions, last_check_at, last_machine_fingerprint}'
