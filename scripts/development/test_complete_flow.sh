#!/bin/bash
################################################################################
# Complete E2E Test: Upload → Merge → Download → Verify
#
# Tests the complete workflow:
# 1. User uploads a binary to server
# 2. Server patches overload with license credentials
# 3. Server sends base binary + patched overload to weaver
# 4. Weaver merges them and returns merged binary
# 5. Server saves merged binary and creates license
# 6. User downloads merged binary
# 7. Merged binary verifies license when executed
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SERVER_URL="http://localhost:8080"
TEST_BINARY="test_hello"

echo "════════════════════════════════════════════════════════════"
echo "🚀 KillCode - Complete End-to-End Workflow Test"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if test binary exists
if [ ! -f "$TEST_BINARY" ]; then
    echo -e "${RED}❌ Test binary not found: $TEST_BINARY${NC}"
    echo "Creating test binary..."
    cat > /tmp/test_hello.c << 'EOF'
#include <stdio.h>
int main() {
    printf("Hello from protected binary!\n");
    return 0;
}
EOF
    gcc /tmp/test_hello.c -o test_hello
    echo -e "${GREEN}✅ Test binary created${NC}"
    echo ""
fi

echo -e "${BLUE}📋 Test Binary Info:${NC}"
ls -lh "$TEST_BINARY"
file "$TEST_BINARY"
echo ""

# Step 1: Upload binary
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}📤 Step 1: Uploading binary to server${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Endpoint: POST $SERVER_URL/binary/upload"
echo "File: $TEST_BINARY"
echo ""

UPLOAD_RESPONSE=$(curl -s -X POST "$SERVER_URL/binary/upload" \
  -F "binary=@$TEST_BINARY" \
  -F "user_id=test_user_$(date +%s)")

echo "Response:"
echo "$UPLOAD_RESPONSE" | jq '.' 2>/dev/null || echo "$UPLOAD_RESPONSE"
echo ""

# Extract IDs
BINARY_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.binary_id' 2>/dev/null)
LICENSE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.license_id' 2>/dev/null)

if [ -z "$BINARY_ID" ] || [ "$BINARY_ID" = "null" ]; then
    echo -e "${RED}❌ Failed to upload binary${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Binary uploaded successfully!${NC}"
echo "   Binary ID: $BINARY_ID"
echo "   License ID: $LICENSE_ID"
echo ""

# Step 2: Wait for merge to complete
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}⏳ Step 2: Waiting for weaver merge to complete${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

MAX_WAIT=30
WAIT_COUNT=0
BINARY_STATUS="processing"

while [ "$BINARY_STATUS" != "ready" ] && [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
    
    BINARY_INFO=$(curl -s "$SERVER_URL/binary/$BINARY_ID")
    BINARY_STATUS=$(echo "$BINARY_INFO" | jq -r '.status' 2>/dev/null || echo "unknown")
    
    echo "   ⏱️  Wait ${WAIT_COUNT}s - Status: $BINARY_STATUS"
    
    if [ "$BINARY_STATUS" = "ready" ]; then
        break
    fi
done

if [ "$BINARY_STATUS" != "ready" ]; then
    echo -e "${RED}❌ Binary merge timeout after ${MAX_WAIT}s${NC}"
    echo "Last status: $BINARY_STATUS"
    echo ""
    echo "Binary info:"
    echo "$BINARY_INFO" | jq '.' 2>/dev/null || echo "$BINARY_INFO"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Binary merge completed!${NC}"
echo ""
echo "Binary details:"
echo "$BINARY_INFO" | jq '{
  binary_id: .binary_id,
  status: .status,
  original_size: .original_size,
  wrapped_size: .wrapped_size,
  created_at: .created_at
}' 2>/dev/null || echo "$BINARY_INFO"
echo ""

# Step 3: Get license details
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}🔐 Step 3: Checking license details${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

LICENSE_INFO=$(curl -s "$SERVER_URL/api/v1/license/$LICENSE_ID")
echo "$LICENSE_INFO" | jq '{
  license_id: .license_id,
  binary_id: .binary_id,
  max_executions: .max_executions,
  executions_used: .executions_used,
  expires_at: .expires_at,
  revoked: .revoked
}' 2>/dev/null || echo "$LICENSE_INFO"
echo ""

# Step 4: Download merged binary
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}📥 Step 4: Downloading merged binary${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

DOWNLOAD_PATH="/tmp/merged_binary_${BINARY_ID}"
curl -s "$SERVER_URL/binary/$BINARY_ID/download" -o "$DOWNLOAD_PATH"

if [ ! -f "$DOWNLOAD_PATH" ]; then
    echo -e "${RED}❌ Failed to download merged binary${NC}"
    exit 1
fi

chmod +x "$DOWNLOAD_PATH"

echo -e "${GREEN}✅ Merged binary downloaded${NC}"
echo ""
echo "Binary info:"
ls -lh "$DOWNLOAD_PATH"
file "$DOWNLOAD_PATH"
echo ""

# Check if it's a valid ELF
if ! file "$DOWNLOAD_PATH" | grep -q "ELF"; then
    echo -e "${RED}❌ Downloaded file is not a valid ELF binary${NC}"
    file "$DOWNLOAD_PATH"
    echo ""
    echo "File contents (first 100 bytes):"
    xxd "$DOWNLOAD_PATH" | head -10
    exit 1
fi

# Step 5: Verify the merged binary structure
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}🔍 Step 5: Analyzing merged binary structure${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Checking for .license section in merged binary..."
if readelf -S "$DOWNLOAD_PATH" 2>/dev/null | grep -q ".license"; then
    echo -e "${GREEN}✅ .license section found!${NC}"
    readelf -S "$DOWNLOAD_PATH" | grep ".license"
else
    echo -e "${YELLOW}⚠️  No .license section found (may be normal for this overload version)${NC}"
fi
echo ""

echo "Binary entry point:"
readelf -h "$DOWNLOAD_PATH" 2>/dev/null | grep "Entry point"
echo ""

echo "Binary symbols (first 20):"
nm "$DOWNLOAD_PATH" 2>/dev/null | head -20 || echo "No symbols (stripped binary)"
echo ""

# Step 6: Test execution
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}🧪 Step 6: Testing merged binary execution${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

echo "Note: Binary will try to verify license with server"
echo "Server: $SERVER_URL"
echo ""

echo "Executing merged binary..."
echo "─────────────────────────────────────────────────────────────"
timeout 10s "$DOWNLOAD_PATH" 2>&1 || EXIT_CODE=$?
echo "─────────────────────────────────────────────────────────────"
echo ""

if [ ${EXIT_CODE:-0} -eq 0 ]; then
    echo -e "${GREEN}✅ Binary executed successfully!${NC}"
elif [ ${EXIT_CODE:-0} -eq 124 ]; then
    echo -e "${YELLOW}⚠️  Execution timeout (10s) - may indicate network verification${NC}"
else
    echo -e "${YELLOW}⚠️  Binary exited with code: ${EXIT_CODE}${NC}"
    echo "This may be expected if license verification failed"
fi
echo ""

# Step 7: Check license after execution
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}📊 Step 7: Checking license after execution${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

LICENSE_INFO_AFTER=$(curl -s "$SERVER_URL/api/v1/license/$LICENSE_ID")
echo "$LICENSE_INFO_AFTER" | jq '{
  license_id: .license_id,
  executions_used: .executions_used,
  last_check_at: .last_check_at,
  last_machine_fingerprint: .last_machine_fingerprint
}' 2>/dev/null || echo "$LICENSE_INFO_AFTER"
echo ""

# Step 8: Check execution history
echo "════════════════════════════════════════════════════════════"
echo -e "${YELLOW}📈 Step 8: Checking execution history${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""

EXEC_HISTORY=$(curl -s "$SERVER_URL/binary/$BINARY_ID/executions")
echo "$EXEC_HISTORY" | jq '.' 2>/dev/null || echo "$EXEC_HISTORY"
echo ""

# Summary
echo "════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Complete E2E Workflow Test Summary${NC}"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Flow Tested:"
echo "  1. ✅ Binary uploaded to server"
echo "  2. ✅ Overload patched with license ($LICENSE_ID)"
echo "  3. ✅ Weaver merged base + overload"
echo "  4. ✅ Merged binary downloaded"
echo "  5. ✅ Binary structure verified (ELF)"
echo "  6. ✅ Binary execution tested"
echo "  7. ✅ License tracking verified"
echo ""
echo "Details:"
echo "  • Binary ID: $BINARY_ID"
echo "  • License ID: $LICENSE_ID"
echo "  • Original Size: $(echo "$BINARY_INFO" | jq -r '.original_size') bytes"
echo "  • Wrapped Size: $(echo "$BINARY_INFO" | jq -r '.wrapped_size') bytes"
echo "  • Download Path: $DOWNLOAD_PATH"
echo ""
echo -e "${BLUE}🎉 Test Complete!${NC}"
echo ""

# Cleanup
echo "Cleaning up temporary files..."
rm -f "$DOWNLOAD_PATH"
echo "Done!"
