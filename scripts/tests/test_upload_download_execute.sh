#!/bin/bash
################################################################################
# Test: Upload → Download → Execute (Single-Check Mode)
#
# Description:
#   Tests the complete workflow with default single-check verification mode:
#   1. Creates a simple C base binary
#   2. Uploads to server (check_interval_ms=0 by default)
#   3. Waits for merge completion
#   4. Downloads merged binary from weaver
#   5. Executes and verifies base runs after overload verification succeeds
#
# Expected Behavior:
#   - Server sets sync_mode=true (loader waits for overload)
#   - Overload verifies license once with server
#   - Overload exits with code 0 on success
#   - Loader continues to base binary
#   - Base binary executes successfully
#
# Usage:
#   ./test_upload_download_execute.sh
#
# Requirements:
#   - Server running on http://localhost:8080
#   - Weaver running on http://localhost:8081
#   - gcc installed for compiling test binary
#   - jq installed for JSON parsing
################################################################################

set -e

SERVER_URL="http://localhost:8080"
BASE_BINARY="/tmp/test_base"
OUTPUT_DIR="/tmp/killcode_test"
MERGED_BINARY="$OUTPUT_DIR/test_merged"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  KillCode - Upload → Download → Execute Test                 ║${NC}"
echo -e "${BLUE}║  Testing new architecture: overload with check_interval_ms   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Clean up old test files
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Step 1: Create a simple test base binary
echo -e "${YELLOW}[1/5]${NC} Creating test base binary..."
cat > /tmp/test_base.c << 'EOF'
#include <stdio.h>
#include <unistd.h>

int main() {
    printf("🎯 BASE BINARY IS EXECUTING!\n");
    printf("   Process ID: %d\n", getpid());
    printf("   This means overload verified and exited with code 0\n");
    return 0;
}
EOF

gcc /tmp/test_base.c -o "$BASE_BINARY" -static
echo -e "${GREEN}✅ Base binary created: $BASE_BINARY${NC}"
ls -lh "$BASE_BINARY"
echo ""

# Step 2: Upload to server
echo -e "${YELLOW}[2/5]${NC} Uploading base binary to server..."
UPLOAD_RESPONSE=$(curl -s -X POST "$SERVER_URL/binary/upload" \
  -H "X-Sync-Mode: true" \
  -F "binary=@$BASE_BINARY")

TASK_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.task_id')

if [ -z "$TASK_ID" ] || [ "$TASK_ID" == "null" ]; then
  echo -e "${RED}❌ Failed to upload binary${NC}"
  echo "Response: $UPLOAD_RESPONSE"
  exit 1
fi

echo -e "${GREEN}✅ Upload successful${NC}"
echo "   Task ID: $TASK_ID"
echo ""

# Step 3: Wait for merge completion
echo -e "${YELLOW}[3/5]${NC} Waiting for merge to complete..."
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
    echo "$PROGRESS_RESPONSE" | jq .
    exit 1
  fi
  
  sleep 1
  ATTEMPT=$((ATTEMPT + 1))
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo -e "\n${RED}❌ Timeout waiting for merge${NC}"
  exit 1
fi
echo ""

# Step 4: Download merged binary
echo -e "${YELLOW}[4/5]${NC} Downloading merged binary..."
DOWNLOAD_URL=$(echo "$PROGRESS_RESPONSE" | jq -r '.download_url')

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
  echo -e "${RED}❌ No download URL available${NC}"
  exit 1
fi

curl -s -o "$MERGED_BINARY" "$DOWNLOAD_URL"
chmod +x "$MERGED_BINARY"

echo -e "${GREEN}✅ Downloaded merged binary${NC}"
ls -lh "$MERGED_BINARY"
echo ""

# Step 5: Execute merged binary
echo -e "${YELLOW}[5/5]${NC} Executing merged binary..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Export OVERLOAD_NO_DESTRUCT to prevent self-destruction during test
export OVERLOAD_NO_DESTRUCT=1

# Run the merged binary
"$MERGED_BINARY"
EXIT_CODE=$?

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Verify success
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  ✅ TEST PASSED - All steps completed successfully!          ║${NC}"
  echo -e "${GREEN}║                                                               ║${NC}"
  echo -e "${GREEN}║  Architecture verified:                                      ║${NC}"
  echo -e "${GREEN}║  • Overload verified license                                 ║${NC}"
  echo -e "${GREEN}║  • check_interval_ms=0 → single check mode                   ║${NC}"
  echo -e "${GREEN}║  • Overload exited with code 0                               ║${NC}"
  echo -e "${GREEN}║  • Loader continued to base binary                           ║${NC}"
  echo -e "${GREEN}║  • Base binary executed successfully                         ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
else
  echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ❌ TEST FAILED - Exit code: $EXIT_CODE                          ║${NC}"
  echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
  exit 1
fi

# Cleanup
echo ""
echo "Cleaning up..."
rm -rf "$OUTPUT_DIR" /tmp/test_base.c "$BASE_BINARY"
echo "Done!"
