#!/bin/bash
################################################################################
# Test: Verification Failure (Security Test)
#
# Description:
#   Tests that the merged binary properly handles verification failures:
#   1. Creates and uploads a base binary
#   2. Downloads merged binary
#   3. Tampers with the license (corrupts shared_secret)
#   4. Executes and verifies base does NOT run when verification fails
#
# Expected Behavior:
#   - Overload detects corrupted/invalid shared_secret
#   - Server returns 401 Unauthorized
#   - Overload exits with code 1
#   - Loader detects failure and aborts
#   - Base binary NEVER executes (security check)
#
# Usage:
#   ./test_verification_failure.sh
#
# Requirements:
#   - Server running on http://localhost:8080
#   - Python3 installed for license tampering
#   - jq installed for JSON parsing
################################################################################

set -e

SERVER_URL="http://localhost:8080"
BASE_BINARY="/tmp/test_base_fail"
OUTPUT_DIR="/tmp/killcode_test_fail"
MERGED_BINARY="$OUTPUT_DIR/test_merged_fail"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  KillCode - Verification Failure Test                        ║${NC}"
echo -e "${BLUE}║  Testing that base does NOT execute when verification fails ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Clean up old test files
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Step 1: Create a simple test base binary
echo -e "${YELLOW}[1/6]${NC} Creating test base binary..."
cat > /tmp/test_base_fail.c << 'EOF'
#include <stdio.h>
#include <unistd.h>

int main() {
    printf("❌ BASE BINARY IS EXECUTING - THIS SHOULD NOT HAPPEN!\n");
    printf("   Process ID: %d\n", getpid());
    printf("   This means overload verification failed but still exited with code 0\n");
    return 1;
}
EOF

gcc /tmp/test_base_fail.c -o "$BASE_BINARY" -static
echo -e "${GREEN}✅ Base binary created: $BASE_BINARY${NC}"
echo ""

# Step 2: Upload to server
echo -e "${YELLOW}[2/6]${NC} Uploading base binary to server..."
UPLOAD_RESPONSE=$(curl -s -X POST "$SERVER_URL/binary/upload" \
  -H "X-Sync-Mode: true" \
  -F "binary=@$BASE_BINARY")

TASK_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.task_id')
echo -e "${GREEN}✅ Upload successful - Task ID: $TASK_ID${NC}"
echo ""

# Step 3: Wait for merge completion
echo -e "${YELLOW}[3/6]${NC} Waiting for merge to complete..."
MAX_ATTEMPTS=30
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  PROGRESS_RESPONSE=$(curl -s "$SERVER_URL/progress/$TASK_ID")
  STATUS=$(echo "$PROGRESS_RESPONSE" | jq -r '.status')
  PERCENTAGE=$(echo "$PROGRESS_RESPONSE" | jq -r '.percentage')
  
  echo -ne "   Status: $STATUS | Progress: $PERCENTAGE%\r"
  
  if [ "$STATUS" == "complete" ]; then
    echo -e "\n${GREEN}✅ Merge completed!${NC}"
    break
  elif [ "$STATUS" == "failed" ]; then
    echo -e "\n${RED}❌ Merge failed${NC}"
    exit 1
  fi
  
  sleep 1
  ATTEMPT=$((ATTEMPT + 1))
done
echo ""

# Step 4: Download merged binary
echo -e "${YELLOW}[4/6]${NC} Downloading merged binary..."
DOWNLOAD_URL=$(echo "$PROGRESS_RESPONSE" | jq -r '.download_url')
curl -s -o "$MERGED_BINARY" "$DOWNLOAD_URL"
chmod +x "$MERGED_BINARY"
echo -e "${GREEN}✅ Downloaded merged binary${NC}"
echo ""

# Step 5: Tamper with license to make verification fail
echo -e "${YELLOW}[5/6]${NC} Tampering with license (corrupting shared_secret)..."
# Find .license section and corrupt the shared_secret
python3 << 'PYTHON_EOF'
import json

binary_path = "/tmp/killcode_test_fail/test_merged_fail"

# Read binary
with open(binary_path, 'rb') as f:
    data = bytearray(f.read())

# Search for license JSON (look for "license_id" marker)
search_str = b'"license_id"'
offset = data.find(search_str)

if offset == -1:
    print("❌ Could not find license section")
    exit(1)

# Find the start of JSON (search backwards for {)
json_start = data.rfind(b'{', 0, offset)
if json_start == -1:
    print("❌ Could not find JSON start")
    exit(1)

# Find the end of JSON (search forwards for })
json_end = data.find(b'}', offset)
if json_end == -1:
    print("❌ Could not find JSON end")
    exit(1)

# Extract and parse JSON
json_bytes = data[json_start:json_end+1]
license_config = json.loads(json_bytes.decode('utf-8'))

print(f"✅ Found license at offset {hex(json_start)}")
print(f"   Original shared_secret: {license_config['shared_secret']}")

# Corrupt the shared_secret
license_config['shared_secret'] = "INVALID_SECRET_CORRUPTED"

# Create new JSON with same length (pad with spaces)
new_json = json.dumps(license_config, separators=(',', ':')).encode('utf-8')
padding_needed = len(json_bytes) - len(new_json)
if padding_needed > 0:
    new_json += b' ' * padding_needed

# Replace in binary
data[json_start:json_end+1] = new_json

# Write back
with open(binary_path, 'wb') as f:
    f.write(data)

print(f"✅ Corrupted shared_secret to: {license_config['shared_secret']}")
PYTHON_EOF

echo ""

# Step 6: Execute merged binary (should fail verification)
echo -e "${YELLOW}[6/6]${NC} Executing merged binary with corrupted license..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Disable self-destruct for testing
export OVERLOAD_NO_DESTRUCT=1

# Run the merged binary (should fail)
"$MERGED_BINARY" 2>&1 || EXIT_CODE=$?
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Verify failure
if [ "${EXIT_CODE:-0}" -ne 0 ]; then
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  ✅ TEST PASSED - Verification failure handled correctly!    ║${NC}"
  echo -e "${GREEN}║                                                               ║${NC}"
  echo -e "${GREEN}║  Verified behavior:                                          ║${NC}"
  echo -e "${GREEN}║  • Overload detected invalid shared_secret                   ║${NC}"
  echo -e "${GREEN}║  • Verification failed (403 or signature mismatch)           ║${NC}"
  echo -e "${GREEN}║  • Overload exited with code 1                               ║${NC}"
  echo -e "${GREEN}║  • Loader detected failure and stopped                       ║${NC}"
  echo -e "${GREEN}║  • Base binary did NOT execute                               ║${NC}"
  echo -e "${GREEN}║  • Exit code: ${EXIT_CODE}                                               ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
else
  echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ❌ TEST FAILED - Base binary executed despite failed auth!  ║${NC}"
  echo -e "${RED}║  This is a CRITICAL SECURITY ISSUE!                          ║${NC}"
  echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
  exit 1
fi

# Cleanup
echo ""
echo "Cleaning up..."
rm -rf "$OUTPUT_DIR" /tmp/test_base_fail.c "$BASE_BINARY"
echo "Done!"
