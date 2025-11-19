#!/bin/bash
# Test DELETE/Revoke endpoint

set -e

echo "🗑️  Testing License REVOKE Endpoint"
echo "====================================="
echo ""

# Create a new license to revoke
echo "Creating a test license to revoke..."
NEW_LICENSE=$(curl -s -X POST http://localhost:8080/api/v1/license/create \
  -H "Content-Type: application/json" \
  -d '{"binary_id": "bin_to_revoke", "max_executions": 5}' | python3 -c "import sys,json; print(json.load(sys.stdin)['license_id'])")

echo "Created license: $NEW_LICENSE"
echo ""

echo "License state before revoke:"
curl -s "http://localhost:8080/api/v1/license/$NEW_LICENSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"Revoked: {d['revoked']}\")"

echo ""
echo "Revoking license..."
curl -s -X DELETE "http://localhost:8080/api/v1/license/$NEW_LICENSE" | python3 -m json.tool

echo ""
echo "License state after revoke:"
curl -s "http://localhost:8080/api/v1/license/$NEW_LICENSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"Revoked: {d['revoked']}\")"

echo ""
echo "Testing verification of revoked license (should fail)..."
TIMESTAMP=$(date +%s)
SHARED_SECRET=$(docker exec killcode-mongodb mongosh killcode --quiet --eval "print(db.licenses.findOne({license_id: '$NEW_LICENSE'}).shared_secret)")
SIGNATURE=$(echo -n "${NEW_LICENSE}${TIMESTAMP}" | openssl dgst -sha256 -hmac "$SHARED_SECRET" | awk '{print $2}')

curl -s -X POST "http://localhost:8080/api/v1/verify" \
  -H "Content-Type: application/json" \
  -H "X-License-ID: $NEW_LICENSE" \
  -H "X-Timestamp: $TIMESTAMP" \
  -H "X-Signature: $SIGNATURE" \
  -d "{\"license_id\": \"$NEW_LICENSE\", \"machine_fingerprint\": \"test-machine\", \"timestamp\": $TIMESTAMP}" | python3 -m json.tool

echo ""
echo "✅ Test complete!"
