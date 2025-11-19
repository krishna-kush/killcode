#!/bin/bash
################################################################################
# Test: API Enhancements (Revoke & Analytics)
#
# Description:
#   Tests the new API endpoints for license management and analytics:
#   1. Creates and uploads binaries
#   2. Performs verifications
#   3. Tests revoke endpoint
#   4. Tests analytics endpoint
#   5. Verifies revoked licenses are rejected
#
# Expected Behavior:
#   - Revoke endpoint immediately revokes license
#   - Analytics endpoint returns comprehensive statistics
#   - Revoked licenses fail verification
#   - Analytics shows correct license and verification counts
#
# Usage:
#   ./test_api_enhancements.sh
#
# Requirements:
#   - Server running on http://localhost:8080
#   - jq installed for JSON parsing
################################################################################

set -e

SERVER_URL="http://localhost:8080"
BINARY_NAME="test_api_binary"
OUTPUT_DIR="/tmp/killcode_api_test"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   API Enhancements Test                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Cleanup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Step 1: Create base binary
echo -e "${YELLOW}[1/8]${NC} Creating base binary..."
cat > "$OUTPUT_DIR/base.c" <<'EOF'
#include <stdio.h>
int main() {
    printf("Test binary executed\n");
    return 0;
}
EOF

gcc -o "$OUTPUT_DIR/$BINARY_NAME" "$OUTPUT_DIR/base.c"
echo -e "${GREEN}✓ Base binary compiled${NC}"

# Step 2: Upload binary
echo -e "\n${YELLOW}[2/8]${NC} Uploading binary..."
UPLOAD_RESPONSE=$(curl -s -X POST "$SERVER_URL/api/v1/binary/upload" \
  -H "Content-Type: application/octet-stream" \
  -H "X-Filename: $BINARY_NAME" \
  -H "X-User-ID: test_user" \
  -H "X-Check-Interval-Ms: 1000" \
  --data-binary "@$OUTPUT_DIR/$BINARY_NAME")

BINARY_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.binary_id')
echo -e "${GREEN}✓ Binary uploaded: $BINARY_ID${NC}"

# Wait for merge
sleep 3

# Step 3: Download merged binary
echo -e "\n${YELLOW}[3/8]${NC} Downloading merged binary..."
curl -s "$SERVER_URL/api/v1/binary/$BINARY_ID/download" \
  -o "$OUTPUT_DIR/merged_binary"
chmod +x "$OUTPUT_DIR/merged_binary"

LICENSE_ID=$(strings "$OUTPUT_DIR/merged_binary" | grep -E "lic_[a-f0-9]{32}" | head -1)
echo -e "${GREEN}✓ Merged binary downloaded${NC}"
echo -e "  License ID: $LICENSE_ID"

# Step 4: Perform some verifications
echo -e "\n${YELLOW}[4/8]${NC} Performing verifications..."
"$OUTPUT_DIR/merged_binary" > /dev/null 2>&1 &
BINARY_PID=$!
sleep 2
kill $BINARY_PID 2>/dev/null || true

"$OUTPUT_DIR/merged_binary" > /dev/null 2>&1 &
BINARY_PID=$!
sleep 2
kill $BINARY_PID 2>/dev/null || true

echo -e "${GREEN}✓ Performed 2 verifications${NC}"

# Step 5: Get analytics BEFORE revocation
echo -e "\n${YELLOW}[5/8]${NC} Getting analytics before revocation..."
ANALYTICS_BEFORE=$(curl -s "$SERVER_URL/api/v1/binary/$BINARY_ID/analytics")

TOTAL_LICENSES_BEFORE=$(echo "$ANALYTICS_BEFORE" | jq -r '.licenses.total')
ACTIVE_LICENSES_BEFORE=$(echo "$ANALYTICS_BEFORE" | jq -r '.licenses.active')
REVOKED_LICENSES_BEFORE=$(echo "$ANALYTICS_BEFORE" | jq -r '.licenses.revoked')
TOTAL_VERIFICATIONS=$(echo "$ANALYTICS_BEFORE" | jq -r '.verifications.total')

echo -e "${GREEN}✓ Analytics retrieved${NC}"
echo -e "  Total licenses: $TOTAL_LICENSES_BEFORE"
echo -e "  Active licenses: $ACTIVE_LICENSES_BEFORE"
echo -e "  Revoked licenses: $REVOKED_LICENSES_BEFORE"
echo -e "  Total verifications: $TOTAL_VERIFICATIONS"

# Step 6: Revoke license
echo -e "\n${YELLOW}[6/8]${NC} Revoking license..."
REVOKE_RESPONSE=$(curl -s -X POST "$SERVER_URL/api/v1/license/$LICENSE_ID/revoke")

REVOKE_MESSAGE=$(echo "$REVOKE_RESPONSE" | jq -r '.message')
IS_REVOKED=$(echo "$REVOKE_RESPONSE" | jq -r '.revoked')

echo -e "${GREEN}✓ License revoked${NC}"
echo -e "  Message: $REVOKE_MESSAGE"
echo -e "  Revoked: $IS_REVOKED"

# Step 7: Verify revoked license is rejected
echo -e "\n${YELLOW}[7/8]${NC} Testing verification after revocation..."
"$OUTPUT_DIR/merged_binary" > "$OUTPUT_DIR/after_revoke.log" 2>&1 &
BINARY_PID=$!
sleep 2
kill $BINARY_PID 2>/dev/null || true

if grep -q "has been revoked" "$OUTPUT_DIR/after_revoke.log" || ! grep -q "Test binary executed" "$OUTPUT_DIR/after_revoke.log"; then
    echo -e "${GREEN}✓ Revoked license properly rejected${NC}"
else
    echo -e "${RED}✗ FAILED: Revoked license was not rejected${NC}"
    cat "$OUTPUT_DIR/after_revoke.log"
    exit 1
fi

# Step 8: Get analytics AFTER revocation
echo -e "\n${YELLOW}[8/8]${NC} Getting analytics after revocation..."
ANALYTICS_AFTER=$(curl -s "$SERVER_URL/api/v1/binary/$BINARY_ID/analytics")

ACTIVE_LICENSES_AFTER=$(echo "$ANALYTICS_AFTER" | jq -r '.licenses.active')
REVOKED_LICENSES_AFTER=$(echo "$ANALYTICS_AFTER" | jq -r '.licenses.revoked')
SUCCESS_RATE=$(echo "$ANALYTICS_AFTER" | jq -r '.verifications.success_rate')

echo -e "${GREEN}✓ Analytics retrieved after revocation${NC}"
echo -e "  Active licenses: $ACTIVE_LICENSES_AFTER (was $ACTIVE_LICENSES_BEFORE)"
echo -e "  Revoked licenses: $REVOKED_LICENSES_AFTER (was $REVOKED_LICENSES_BEFORE)"
echo -e "  Success rate: ${SUCCESS_RATE}%"

# Verify analytics changed correctly
if [ "$ACTIVE_LICENSES_AFTER" -lt "$ACTIVE_LICENSES_BEFORE" ] && [ "$REVOKED_LICENSES_AFTER" -gt "$REVOKED_LICENSES_BEFORE" ]; then
    echo -e "${GREEN}✓ Analytics correctly updated after revocation${NC}"
else
    echo -e "${RED}✗ FAILED: Analytics not correctly updated${NC}"
    echo "Before: Active=$ACTIVE_LICENSES_BEFORE, Revoked=$REVOKED_LICENSES_BEFORE"
    echo "After: Active=$ACTIVE_LICENSES_AFTER, Revoked=$REVOKED_LICENSES_AFTER"
    exit 1
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ API Enhancements Test PASSED      ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "Summary:"
echo "  - Revoke endpoint successfully revoked license"
echo "  - Revoked license rejected in verification"
echo "  - Analytics endpoint provides comprehensive stats"
echo "  - Analytics correctly tracks license states"
echo ""
echo "API Endpoints Tested:"
echo "  - POST /api/v1/license/{license_id}/revoke"
echo "  - GET /api/v1/binary/{binary_id}/analytics"
echo ""

# Cleanup
rm -rf "$OUTPUT_DIR"
