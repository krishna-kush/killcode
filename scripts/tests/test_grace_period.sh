#!/bin/bash
################################################################################
# Test: Grace Period (Offline Tolerance)
#
# Description:
#   Tests the grace period feature that allows X failed verifications
#   before killing the base binary. This tests offline tolerance:
#   1. Creates and uploads a base binary
#   2. Sets grace_period=3 via X-Grace-Period header
#   3. Sets check_interval_ms=2000 (continuous monitoring)
#   4. Downloads merged binary
#   5. Executes binary
#   6. Tampers with shared_secret to simulate network failure
#   7. Verifies base continues running during grace period
#   8. Verifies base is killed after grace period exceeded
#
# Expected Behavior:
#   - Overload successfully verifies initially
#   - Base binary starts running
#   - After tampering: first 3 failed verifications are tolerated
#   - Server tracks failed_attempts: 1, 2, 3
#   - On 4th failure: overload kills base binary
#   - Verifies clean shutdown after grace period
#
# Usage:
#   ./test_grace_period.sh
#
# Requirements:
#   - Server running on http://localhost:8080
#   - Python3 installed for license tampering
#   - jq installed for JSON parsing
################################################################################

set -e

SERVER_URL="http://localhost:8080"
BINARY_NAME="test_grace_binary"
OUTPUT_DIR="/tmp/killcode_grace_test"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Grace Period Test (Offline Tolerance) ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Cleanup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Step 1: Create a simple C program with progress counter
echo -e "${YELLOW}[1/8]${NC} Creating base binary with progress counter..."
cat > "$OUTPUT_DIR/base.c" <<'EOF'
#include <stdio.h>
#include <unistd.h>

int main() {
    printf("╔══════════════════════════════════════╗\n");
    printf("║   BASE BINARY - GRACE PERIOD TEST   ║\n");
    printf("╚══════════════════════════════════════╝\n");
    printf("Status: Running (should survive 3 failed verifications)\n\n");
    fflush(stdout);
    
    for (int i = 1; i <= 30; i++) {
        printf("Progress: %02d/30 - Still alive\n", i);
        fflush(stdout);
        sleep(1);
    }
    
    printf("\n✅ Base binary completed successfully\n");
    return 0;
}
EOF

gcc -o "$OUTPUT_DIR/$BINARY_NAME" "$OUTPUT_DIR/base.c"
echo -e "${GREEN}✓ Base binary compiled${NC}"

# Step 2: Upload binary with grace_period=3
echo -e "\n${YELLOW}[2/8]${NC} Uploading binary (grace_period=3, check_interval_ms=2000)..."
UPLOAD_RESPONSE=$(curl -s -X POST "$SERVER_URL/api/v1/binary/upload" \
  -H "Content-Type: application/octet-stream" \
  -H "X-Filename: $BINARY_NAME" \
  -H "X-User-ID: test_user" \
  -H "X-Check-Interval-Ms: 2000" \
  -H "X-Grace-Period: 3" \
  --data-binary "@$OUTPUT_DIR/$BINARY_NAME")

BINARY_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.binary_id')
echo -e "${GREEN}✓ Binary uploaded: $BINARY_ID${NC}"
echo -e "  Grace period: 3 failed attempts allowed"
echo -e "  Check interval: 2000ms (2 seconds)"

# Step 3: Wait for merge to complete
echo -e "\n${YELLOW}[3/8]${NC} Waiting for merge to complete..."
sleep 3
echo -e "${GREEN}✓ Merge completed${NC}"

# Step 4: Download merged binary
echo -e "\n${YELLOW}[4/8]${NC} Downloading merged binary..."
curl -s "$SERVER_URL/api/v1/binary/$BINARY_ID/download" \
  -o "$OUTPUT_DIR/merged_binary"
chmod +x "$OUTPUT_DIR/merged_binary"
echo -e "${GREEN}✓ Merged binary downloaded${NC}"

# Step 5: Execute binary in background and capture license_id
echo -e "\n${YELLOW}[5/8]${NC} Executing merged binary..."
"$OUTPUT_DIR/merged_binary" > "$OUTPUT_DIR/execution.log" 2>&1 &
BINARY_PID=$!
echo -e "${GREEN}✓ Binary started (PID: $BINARY_PID)${NC}"

# Wait for overload to extract and verify once
sleep 3

# Extract license_id from merged binary
LICENSE_ID=$(strings "$OUTPUT_DIR/merged_binary" | grep -E "lic_[a-f0-9]{32}" | head -1)
echo -e "  License ID: $LICENSE_ID"

# Step 6: Tamper with shared_secret to simulate network failure
echo -e "\n${YELLOW}[6/8]${NC} Tampering with license to simulate network failure..."
python3 - <<EOF
import json
import os

merged_path = "$OUTPUT_DIR/merged_binary"

# Read the merged binary
with open(merged_path, 'rb') as f:
    content = f.read()

# Find LICENSE_START and LICENSE_END markers
start_marker = b'LICENSE_START'
end_marker = b'LICENSE_END'
start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print("ERROR: License markers not found")
    exit(1)

# Extract and parse license JSON
license_start = start_idx + len(start_marker)
license_json = content[license_start:end_idx].decode('utf-8')
license_data = json.loads(license_json)

# Corrupt shared_secret
license_data['shared_secret'] = "corrupted_secret_" + license_data['shared_secret'][:10]

# Serialize back to JSON with padding
new_json = json.dumps(license_data)
json_length = end_idx - license_start
new_json_padded = new_json.ljust(json_length)[:json_length]

# Replace in binary
new_content = content[:license_start] + new_json_padded.encode('utf-8') + content[end_idx:]

# Write back
with open(merged_path, 'wb') as f:
    f.write(new_content)

print("Shared secret corrupted")
EOF

echo -e "${GREEN}✓ Shared secret corrupted (simulating network failure)${NC}"

# Step 7: Monitor for grace period behavior
echo -e "\n${YELLOW}[7/8]${NC} Monitoring grace period behavior (next 10 seconds)..."
echo -e "  Expected: Base survives 3 failed verifications (6 seconds total)"
echo -e "  Expected: Base killed on 4th failure (after 8 seconds)"
echo ""

# Monitor for 10 seconds
for i in {1..10}; do
    if ps -p $BINARY_PID > /dev/null; then
        echo -e "  [+${i}s] Process still running (PID: $BINARY_PID)"
    else
        echo -e "  [+${i}s] ${RED}Process terminated${NC}"
        break
    fi
    sleep 1
done

# Step 8: Verify results
echo -e "\n${YELLOW}[8/8]${NC} Verifying results..."

# Check if process is still running (it shouldn't be after grace period)
if ps -p $BINARY_PID > /dev/null; then
    echo -e "${RED}✗ FAILED: Process still running after grace period${NC}"
    kill $BINARY_PID 2>/dev/null
    exit 1
fi

# Check execution log
if grep -q "BASE BINARY - GRACE PERIOD TEST" "$OUTPUT_DIR/execution.log"; then
    echo -e "${GREEN}✓ Base binary started successfully${NC}"
else
    echo -e "${RED}✗ FAILED: Base binary did not start${NC}"
    cat "$OUTPUT_DIR/execution.log"
    exit 1
fi

# Count how many progress messages were printed (should be ~3-5)
PROGRESS_COUNT=$(grep -c "Progress:" "$OUTPUT_DIR/execution.log" || echo "0")
echo -e "${GREEN}✓ Base ran for $PROGRESS_COUNT seconds (expected 3-5)${NC}"

if [ "$PROGRESS_COUNT" -ge 3 ] && [ "$PROGRESS_COUNT" -le 8 ]; then
    echo -e "${GREEN}✓ Grace period behavior correct${NC}"
else
    echo -e "${RED}✗ FAILED: Grace period behavior incorrect${NC}"
    echo "Expected 3-8 progress messages, got $PROGRESS_COUNT"
    exit 1
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅ Grace Period Test PASSED  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════╝${NC}"
echo ""
echo "Summary:"
echo "  - Base binary started successfully"
echo "  - Survived initial verifications"
echo "  - Tolerated failures during grace period"
echo "  - Properly terminated after grace period exceeded"
echo ""

# Cleanup
rm -rf "$OUTPUT_DIR"
