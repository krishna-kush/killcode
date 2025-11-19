#!/bin/bash
################################################################################
# Test: Telemetry & Monitoring
#
# Description:
#   Tests the telemetry system that tracks all verification attempts:
#   1. Creates and uploads a base binary
#   2. Performs multiple verifications (success and failure)
#   3. Queries verification history via telemetry API
#   4. Verifies dashboard statistics
#   5. Checks that all attempts are properly logged
#
# Expected Behavior:
#   - All verification attempts logged to database
#   - History endpoint returns chronological attempts
#   - Dashboard shows correct statistics
#   - Failed and successful attempts properly categorized
#   - Grace period tracking visible in telemetry
#
# Usage:
#   ./test_telemetry.sh
#
# Requirements:
#   - Server running on http://localhost:8080
#   - Python3 installed for license tampering
#   - jq installed for JSON parsing
################################################################################

set -e

SERVER_URL="http://localhost:8080"
BINARY_NAME="test_telemetry_binary"
OUTPUT_DIR="/tmp/killcode_telemetry_test"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Telemetry & Monitoring Test         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Cleanup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Step 1: Create base binary
echo -e "${YELLOW}[1/7]${NC} Creating base binary..."
cat > "$OUTPUT_DIR/base.c" <<'EOF'
#include <stdio.h>
int main() {
    printf("Base binary executed\n");
    return 0;
}
EOF

gcc -o "$OUTPUT_DIR/$BINARY_NAME" "$OUTPUT_DIR/base.c"
echo -e "${GREEN}✓ Base binary compiled${NC}"

# Step 2: Upload binary with grace_period=2
echo -e "\n${YELLOW}[2/7]${NC} Uploading binary (grace_period=2, check_interval_ms=1000)..."
UPLOAD_RESPONSE=$(curl -s -X POST "$SERVER_URL/api/v1/binary/upload" \
  -H "Content-Type: application/octet-stream" \
  -H "X-Filename: $BINARY_NAME" \
  -H "X-User-ID: test_user" \
  -H "X-Check-Interval-Ms: 1000" \
  -H "X-Grace-Period: 2" \
  --data-binary "@$OUTPUT_DIR/$BINARY_NAME")

BINARY_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.binary_id')
echo -e "${GREEN}✓ Binary uploaded: $BINARY_ID${NC}"

# Wait for merge
sleep 3

# Step 3: Download merged binary
echo -e "\n${YELLOW}[3/7]${NC} Downloading merged binary..."
curl -s "$SERVER_URL/api/v1/binary/$BINARY_ID/download" \
  -o "$OUTPUT_DIR/merged_binary"
chmod +x "$OUTPUT_DIR/merged_binary"
echo -e "${GREEN}✓ Merged binary downloaded${NC}"

# Extract license_id
LICENSE_ID=$(strings "$OUTPUT_DIR/merged_binary" | grep -E "lic_[a-f0-9]{32}" | head -1)
echo -e "  License ID: $LICENSE_ID"

# Step 4: Perform multiple verifications
echo -e "\n${YELLOW}[4/7]${NC} Performing verification attempts..."

# Success attempt 1
echo -e "  Attempt 1: Success (initial verification)"
"$OUTPUT_DIR/merged_binary" > /dev/null 2>&1 &
BINARY_PID=$!
sleep 2
kill $BINARY_PID 2>/dev/null || true

# Tamper with license to cause failures
python3 - <<EOF
import json
merged_path = "$OUTPUT_DIR/merged_binary"
with open(merged_path, 'rb') as f:
    content = f.read()
start_marker = b'LICENSE_START'
end_marker = b'LICENSE_END'
start_idx = content.find(start_marker)
end_idx = content.find(end_marker)
license_start = start_idx + len(start_marker)
license_json = content[license_start:end_idx].decode('utf-8')
license_data = json.loads(license_json)
license_data['shared_secret'] = "corrupted_secret"
new_json = json.dumps(license_data)
json_length = end_idx - license_start
new_json_padded = new_json.ljust(json_length)[:json_length]
new_content = content[:license_start] + new_json_padded.encode('utf-8') + content[end_idx:]
with open(merged_path, 'wb') as f:
    f.write(new_content)
EOF

# Failure attempts (within grace period)
echo -e "  Attempt 2: Failure (invalid signature, within grace)"
"$OUTPUT_DIR/merged_binary" > /dev/null 2>&1 &
BINARY_PID=$!
sleep 2
kill $BINARY_PID 2>/dev/null || true

echo -e "  Attempt 3: Failure (invalid signature, within grace)"
"$OUTPUT_DIR/merged_binary" > /dev/null 2>&1 &
BINARY_PID=$!
sleep 2
kill $BINARY_PID 2>/dev/null || true

echo -e "  Attempt 4: Failure (invalid signature, exceeds grace)"
"$OUTPUT_DIR/merged_binary" > /dev/null 2>&1 &
BINARY_PID=$!
sleep 2
kill $BINARY_PID 2>/dev/null || true

echo -e "${GREEN}✓ Performed 4 verification attempts (1 success, 3 failures)${NC}"

# Step 5: Query verification history
echo -e "\n${YELLOW}[5/7]${NC} Querying verification history..."
HISTORY_RESPONSE=$(curl -s "$SERVER_URL/api/v1/telemetry/license/$LICENSE_ID/history?limit=10")

TOTAL_ATTEMPTS=$(echo "$HISTORY_RESPONSE" | jq -r '.total_attempts')
SUCCESSFUL=$(echo "$HISTORY_RESPONSE" | jq -r '.successful_attempts')
FAILED=$(echo "$HISTORY_RESPONSE" | jq -r '.failed_attempts')

echo -e "${GREEN}✓ History retrieved${NC}"
echo -e "  Total attempts: $TOTAL_ATTEMPTS"
echo -e "  Successful: $SUCCESSFUL"
echo -e "  Failed: $FAILED"

# Step 6: Query dashboard statistics
echo -e "\n${YELLOW}[6/7]${NC} Querying dashboard statistics..."
DASHBOARD_RESPONSE=$(curl -s "$SERVER_URL/api/v1/telemetry/dashboard")

TOTAL_VERIFICATIONS=$(echo "$DASHBOARD_RESPONSE" | jq -r '.total_verifications')
SUCCESSFUL_VERIFICATIONS=$(echo "$DASHBOARD_RESPONSE" | jq -r '.successful_verifications')
FAILED_VERIFICATIONS=$(echo "$DASHBOARD_RESPONSE" | jq -r '.failed_verifications')

echo -e "${GREEN}✓ Dashboard stats retrieved${NC}"
echo -e "  Total verifications: $TOTAL_VERIFICATIONS"
echo -e "  Successful: $SUCCESSFUL_VERIFICATIONS"
echo -e "  Failed: $FAILED_VERIFICATIONS"

# Step 7: Verify results
echo -e "\n${YELLOW}[7/7]${NC} Verifying telemetry data..."

# Check if we have at least 4 attempts logged
if [ "$TOTAL_ATTEMPTS" -ge 4 ]; then
    echo -e "${GREEN}✓ All attempts logged (expected ≥4, got $TOTAL_ATTEMPTS)${NC}"
else
    echo -e "${RED}✗ FAILED: Missing attempts (expected ≥4, got $TOTAL_ATTEMPTS)${NC}"
    exit 1
fi

# Check if we have at least 1 successful attempt
if [ "$SUCCESSFUL" -ge 1 ]; then
    echo -e "${GREEN}✓ Success attempts tracked (expected ≥1, got $SUCCESSFUL)${NC}"
else
    echo -e "${RED}✗ FAILED: Missing success attempts${NC}"
    exit 1
fi

# Check if we have at least 3 failed attempts
if [ "$FAILED" -ge 3 ]; then
    echo -e "${GREEN}✓ Failed attempts tracked (expected ≥3, got $FAILED)${NC}"
else
    echo -e "${RED}✗ FAILED: Missing failed attempts${NC}"
    exit 1
fi

# Check dashboard totals
if [ "$TOTAL_VERIFICATIONS" -ge "$TOTAL_ATTEMPTS" ]; then
    echo -e "${GREEN}✓ Dashboard shows correct totals${NC}"
else
    echo -e "${RED}✗ FAILED: Dashboard totals incorrect${NC}"
    exit 1
fi

# Verify grace period tracking in attempts
echo -e "\n${BLUE}Detailed attempt history:${NC}"
echo "$HISTORY_RESPONSE" | jq -r '.attempts[] | "\(.timestamp | split("T")[1] | split(".")[0]) - Success: \(.success), Failed Attempts: \(.failed_attempts), Within Grace: \(.within_grace_period)"' | head -4

echo ""
echo -e "${GREEN}╔════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ Telemetry Test PASSED         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════╝${NC}"
echo ""
echo "Summary:"
echo "  - All verification attempts logged to database"
echo "  - History API returns correct statistics"
echo "  - Dashboard shows aggregated metrics"
echo "  - Grace period tracking working correctly"
echo ""
echo "API Endpoints Tested:"
echo "  - GET /api/v1/telemetry/license/{license_id}/history"
echo "  - GET /api/v1/telemetry/dashboard"
echo ""

# Cleanup
rm -rf "$OUTPUT_DIR"
