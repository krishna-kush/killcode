#!/bin/bash
set -e

echo "🔄 Testing SSE (Server-Sent Events) for Real-time Progress"
echo "==========================================================="
echo ""
echo "📡 Architecture: Weaver (Pub) → Redis → Server (Sub) → Client (SSE)"
echo ""

# Get ports from .env or use defaults
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
echo "$RESPONSE" | jq '.'
echo ""

TASK_ID=$(echo "$RESPONSE" | jq -r '.task_id')
STREAM_URL=$(echo "$RESPONSE" | jq -r '.progress_stream')

if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
    echo "❌ Failed to get task_id from response"
    exit 1
fi

echo "✅ Task ID: ${TASK_ID}"
echo "📡 SSE Stream: ${SERVER_URL}${STREAM_URL}"
echo ""

# Step 3: Connect to SSE stream
echo "3️⃣  Connecting to SSE stream for real-time updates..."
echo "   (Weaver publishes → Redis → Server subscribes → SSE streams to us)"
echo ""

timeout 15 curl -s -N ${SERVER_URL}${STREAM_URL} | while read line; do
    if [[ $line == data:* ]]; then
        # Extract JSON from "data: {...}"
        JSON="${line#data: }"
        
        # Parse progress info
        PERCENTAGE=$(echo "$JSON" | jq -r '.percentage // 0')
        MESSAGE=$(echo "$JSON" | jq -r '.message // "Processing..."')
        COMPLETE=$(echo "$JSON" | jq -r '.complete // false')
        
        echo "   📊 Progress: ${PERCENTAGE}% - ${MESSAGE}"
        
        # Check if complete
        if [ "$COMPLETE" = "true" ]; then
            echo ""
            echo "✅ Merge completed! SSE stream closed."
            BINARY_ID=$(echo "$JSON" | jq -r '.binary_id // "N/A"')
            ERROR=$(echo "$JSON" | jq -r '.error // ""')
            
            if [ -n "$ERROR" ] && [ "$ERROR" != "null" ] && [ "$ERROR" != "" ]; then
                echo "❌ Error: ${ERROR}"
                exit 1
            else
                echo "🎉 Merged binary ID: ${BINARY_ID}"
                exit 0
            fi
        fi
    fi
done

echo ""
echo "⚠️  SSE stream timeout or connection closed"

# Cleanup
rm -f /tmp/base.c /tmp/overload.c /tmp/base.bin /tmp/overload.bin
