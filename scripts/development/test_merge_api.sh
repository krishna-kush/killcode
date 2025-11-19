#!/bin/bash
set -e

echo "🔄 Testing Server Binary Merge API"
echo "===================================="
echo ""

# Get server port from .env or use default
SERVER_PORT=${SERVER_PORT_EXTERNAL:-8080}
SERVER_URL="http://localhost:${SERVER_PORT}"

echo "📍 Server URL: ${SERVER_URL}"
echo ""

# Step 1: Create test binaries
echo "1️⃣  Creating test binaries..."
cat > /tmp/base.c << 'EOF'
#include <stdio.h>
int main() {
    printf("BASE_BINARY\n");
    return 0;
}
EOF

cat > /tmp/overload.c << 'EOF'
#include <stdio.h>
int main() {
    printf("OVERLOAD_BINARY\n");
    return 0;
}
EOF

gcc /tmp/base.c -o /tmp/base.bin -static
gcc /tmp/overload.c -o /tmp/overload.bin -static
echo "✅ Test binaries created"
echo ""

# Step 2: Submit merge request
echo "2️⃣  Submitting merge request to ${SERVER_URL}/merge..."
RESPONSE=$(curl -s -X POST ${SERVER_URL}/merge \
  -F "base_binary=@/tmp/base.bin" \
  -F "overload_binary=@/tmp/overload.bin" \
  -F "mode=before")

echo "Response:"
echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
echo ""

# Step 4: Extract task ID
TASK_ID=$(echo "$RESPONSE" | jq -r '.task_id' 2>/dev/null)

if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
    echo "❌ Failed to get task_id from response"
    exit 1
fi

echo "✅ Task ID: ${TASK_ID}"
echo ""

# Step 3: Poll progress
echo "3️⃣  Polling progress..."
for i in {1..10}; do
    echo "   Poll #${i}..."
    PROGRESS=$(curl -s ${SERVER_URL}/progress/${TASK_ID})
    
    STATUS=$(echo "$PROGRESS" | jq -r '.status' 2>/dev/null)
    PERCENTAGE=$(echo "$PROGRESS" | jq -r '.percentage' 2>/dev/null)
    MESSAGE=$(echo "$PROGRESS" | jq -r '.message' 2>/dev/null)
    
    echo "   Status: ${STATUS} | Progress: ${PERCENTAGE}% | ${MESSAGE}"
    
    if [ "$STATUS" = "complete" ]; then
        echo ""
        echo "✅ Merge completed successfully!"
        echo ""
        echo "Final response:"
        echo "$PROGRESS" | jq '.'
        
        BINARY_ID=$(echo "$PROGRESS" | jq -r '.binary_id')
        if [ -n "$BINARY_ID" ] && [ "$BINARY_ID" != "null" ]; then
            echo ""
            echo "🎉 Merged binary ID: ${BINARY_ID}"
        fi
        exit 0
    fi
    
    if [ "$STATUS" = "failed" ]; then
        echo ""
        echo "❌ Merge failed!"
        ERROR=$(echo "$PROGRESS" | jq -r '.error')
        echo "Error: ${ERROR}"
        exit 1
    fi
    
    sleep 2
done

echo ""
echo "⚠️  Merge still in progress after 20 seconds"
echo "   Check logs: docker compose logs weaver"

# Cleanup
rm -f /tmp/base.c /tmp/overload.c /tmp/base.bin /tmp/overload.bin
