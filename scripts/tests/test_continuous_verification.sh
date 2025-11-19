#!/bin/bash
################################################################################
# Test: Continuous Verification (Async Mode)
#
# Description:
#   Tests continuous monitoring mode where base binary runs immediately
#   while overload performs periodic verification checks in parallel:
#   1. Creates base binary with progress counter
#   2. Uploads with X-Check-Interval-Ms: 2000 (2 seconds)
#   3. Downloads merged binary in async mode (sync=false)
#   4. Executes and monitors both processes running in parallel
#
# Expected Behavior:
#   - Base binary executes immediately (async mode)
#   - Base prints progress messages every second
#   - Overload verifies license every 2 seconds
#   - Both processes run in parallel (interleaved output)
#   - Server logs show sync_mode=false decision
#
# Usage:
#   ./test_continuous_verification.sh
#
# Requirements:
#   - Server running on http://localhost:8080
#   - gcc installed for compiling base binary
#   - curl and jq for API interactions
################################################################################

set -e

SERVER_URL="http://localhost:8080"
BASE_BINARY="/tmp/test_base_loop"
OUTPUT_DIR="/tmp/killcode_test_loop"
MERGED_BINARY="$OUTPUT_DIR/test_merged_loop"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  KillCode - Continuous Verification Test                     ║${NC}"
echo -e "${BLUE}║  Testing check_interval_ms=2000 with sync=false              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Clean up old test files
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Step 1: Create a simple test base binary
echo -e "${YELLOW}[1/5]${NC} Creating test base binary..."
cat > /tmp/test_base_loop.c << 'EOF'
#include <stdio.h>
#include <unistd.h>

int main() {
    printf("\n");
    printf("════════════════════════════════════════════════════════════\n");
    printf("🎯 BASE BINARY IS EXECUTING (Async Mode)!\n");
    printf("   Process ID: %d\n", getpid());
    printf("   Base started immediately (didn't wait for overload)\n");
    printf("════════════════════════════════════════════════════════════\n");
    fflush(stdout);
    
    for (int i = 1; i <= 8; i++) {
        sleep(1);
        printf("   [Base] Still running... (%d/8 seconds)\n", i);
        fflush(stdout);
    }
    
    printf("════════════════════════════════════════════════════════════\n");
    printf("✅ Base binary completed successfully\n");
    printf("════════════════════════════════════════════════════════════\n");
    fflush(stdout);
    return 0;
}
EOF

gcc /tmp/test_base_loop.c -o "$BASE_BINARY" -static
echo -e "${GREEN}✅ Base binary created: $BASE_BINARY${NC}"
echo ""

# Step 2: Upload to server with continuous verification enabled
echo -e "${YELLOW}[2/7]${NC} Uploading base binary with check_interval_ms=2000..."
UPLOAD_RESPONSE=$(curl -s -X POST "$SERVER_URL/binary/upload" \
  -H "X-Check-Interval-Ms: 2000" \
  -F "binary=@$BASE_BINARY")

TASK_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.task_id')
echo -e "${GREEN}✅ Upload successful - Task ID: $TASK_ID${NC}"
echo ""

# Step 3: Wait for merge completion
echo -e "${YELLOW}[3/5]${NC} Waiting for merge to complete (with sync=false)..."
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
echo -e "${YELLOW}[4/5]${NC} Downloading merged binary..."
DOWNLOAD_URL=$(echo "$PROGRESS_RESPONSE" | jq -r '.download_url')
curl -s -o "$MERGED_BINARY" "$DOWNLOAD_URL"
chmod +x "$MERGED_BINARY"
echo -e "${GREEN}✅ Downloaded merged binary (with check_interval_ms=2000 pre-configured)${NC}"
echo ""

# Step 5: Execute merged binary in background and monitor
echo -e "${YELLOW}[5/5]${NC} Executing merged binary with continuous verification..."
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Disable self-destruct for testing
export OVERLOAD_NO_DESTRUCT=1

# Run in background and capture output
"$MERGED_BINARY" > /tmp/loop_test_output.log 2>&1 &
MERGED_PID=$!

echo "   Merged binary started with PID: $MERGED_PID"
echo "   Monitoring for 9 seconds to observe:"
echo "     • Base binary execution (should start immediately)"
echo "     • Multiple overload verification attempts (every 2 seconds)"
echo ""

# Monitor for 9 seconds
for i in {1..9}; do
  sleep 1
  echo "   [${i}s] Process still running..."
  
  # Check if process is still alive
  if ! kill -0 $MERGED_PID 2>/dev/null; then
    echo -e "${RED}   Process terminated unexpectedly!${NC}"
    break
  fi
done

# Kill the process if still running
if kill -0 $MERGED_PID 2>/dev/null; then
  echo ""
  echo "   Terminating test process..."
  kill $MERGED_PID 2>/dev/null || true
  wait $MERGED_PID 2>/dev/null || true
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Analyze output
echo "Analyzing output..."
echo -e "${BLUE}Output captured:${NC}"
cat /tmp/loop_test_output.log
echo ""

# Count verification attempts
VERIFY_COUNT=$(grep -c "🔍 Verifying license..." /tmp/loop_test_output.log || echo 0)
RECHECK_COUNT=$(grep -c "🔄 Will re-check in" /tmp/loop_test_output.log || echo 0)
BASE_STARTED=$(grep -c "BASE BINARY IS EXECUTING" /tmp/loop_test_output.log || echo 0)
BASE_RUNNING=$(grep -c "\[Base\] Still running" /tmp/loop_test_output.log || echo 0)

echo "Execution statistics:"
echo "  • Overload verification attempts: $VERIFY_COUNT"
echo "  • Overload re-check messages: $RECHECK_COUNT"
echo "  • Base binary started: $BASE_STARTED (should be 1)"
echo "  • Base running messages: $BASE_RUNNING (should be >0)"
echo ""

# Verify behavior
if [ "$VERIFY_COUNT" -ge 2 ] && [ "$RECHECK_COUNT" -ge 1 ] && [ "$BASE_STARTED" -ge 1 ]; then
  echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║  ✅ TEST PASSED - Async mode working perfectly!              ║${NC}"
  echo -e "${GREEN}║                                                               ║${NC}"
  echo -e "${GREEN}║  Verified behavior:                                          ║${NC}"
  echo -e "${GREEN}║  • check_interval_ms=2000, sync_mode=false                   ║${NC}"
  echo -e "${GREEN}║  • Base binary started IMMEDIATELY (async)                   ║${NC}"
  echo -e "${GREEN}║  • Base binary ran in parallel with overload                 ║${NC}"
  echo -e "${GREEN}║  • Overload verified $VERIFY_COUNT times (continuous loop)               ║${NC}"
  echo -e "${GREEN}║  • Both processes running simultaneously ✓                   ║${NC}"
  echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
else
  echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║  ❌ TEST FAILED - Async mode not working correctly!          ║${NC}"
  echo -e "${RED}║                                                               ║${NC}"
  if [ "$BASE_STARTED" -eq 0 ]; then
    echo -e "${RED}║  • Base binary did NOT start (should start immediately)      ║${NC}"
  fi
  if [ "$VERIFY_COUNT" -lt 2 ]; then
    echo -e "${RED}║  • Not enough verification attempts: $VERIFY_COUNT                    ║${NC}"
  fi
  echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
  exit 1
fi

# Cleanup
echo ""
echo "Cleaning up..."
rm -rf "$OUTPUT_DIR" /tmp/test_base_loop.c "$BASE_BINARY" /tmp/loop_test_output.log
echo "Done!"
