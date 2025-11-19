#!/bin/bash
set -e

echo "🔄 Testing Health Endpoints and SSE"
echo "====================================="
echo ""

# Get ports from .env or use defaults
SERVER_PORT=${SERVER_PORT_EXTERNAL:-8080}
WEAVER_PORT=${WEAVER_PORT_EXTERNAL:-8081}

SERVER_URL="http://localhost:${SERVER_PORT}"
WEAVER_URL="http://localhost:${WEAVER_PORT}"

echo "📍 Server URL: ${SERVER_URL}"
echo "📍 Weaver URL: ${WEAVER_URL}"
echo ""

echo "⌛ Waiting for server to be ready..."
for i in {1..20}; do
    if curl -s ${SERVER_URL}/health | jq -e '.status == "healthy"' > /dev/null 2>&1; then
        echo "✅ Server is ready!"
        break
    fi
    sleep 1
done

if ! curl -s ${SERVER_URL}/health | jq -e '.status == "healthy"' > /dev/null 2>&1; then
    echo "❌ Server did not become healthy in time."
    exit 1
fi
echo ""

# Test 1: Server Health
echo "1️⃣  Testing Server Health Endpoint..."
SERVER_HEALTH=$(curl -s ${SERVER_URL}/health)
echo "Response: ${SERVER_HEALTH}"
if echo "$SERVER_HEALTH" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
    echo "✅ Server is healthy"
else
    echo "❌ Server health check failed"
    exit 1
fi
echo ""

# Test 2: Weaver Health
echo "2️⃣  Testing Weaver Health Endpoint..."
WEAVER_HEALTH=$(curl -s ${WEAVER_URL}/health)
echo "Response: ${WEAVER_HEALTH}"
if echo "$WEAVER_HEALTH" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
    echo "✅ Weaver is healthy"
else
    echo "❌ Weaver health check failed"
    exit 1
fi
echo ""

# Test 3: Create test binaries
echo "3️⃣  Creating test binaries..."
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

# Test 4: Submit merge request
echo "4️⃣  Submitting merge request..."
RESPONSE=$(curl -s -X POST ${SERVER_URL}/merge \
  -F "base_binary=@/tmp/base.bin" \
  -F "overload_binary=@/tmp/overload.bin" \
  -F "mode=before")

TASK_ID=$(echo "$RESPONSE" | jq -r '.task_id')
echo "✅ Task ID: ${TASK_ID}"

if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
    echo "❌ Failed to get task_id from merge response. The endpoint might be wrong or the server returned an error."
    echo "Response was:"
    echo "$RESPONSE"
    exit 1
fi
echo ""

# Test 5: Test SSE Stream
echo "5️⃣  Testing SSE Progress Stream..."
echo "   Listening to: ${SERVER_URL}/progress/${TASK_ID}/stream"
echo "   (Will timeout after 10 seconds or when complete)"
echo ""

MERGE_COMPLETE=false
while read -r line; do
    if [[ $line == data:* ]]; then
        JSON="${line#data: }"
        echo "   📡 SSE Event: $JSON"

        if echo "$JSON" | jq -e '.complete == true' > /dev/null 2>&1; then
            echo ""
            echo "✅ Merge completed via SSE!"
            MERGE_COMPLETE=true
            break
        fi
    fi
done < <(timeout 30 curl -s -N ${SERVER_URL}/progress/${TASK_ID}/stream)

if [ "$MERGE_COMPLETE" = "false" ]; then
    echo ""
    echo "❌ Timed out waiting for SSE 'complete' event."
    exit 1
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "📊 Summary:"
echo "   ✅ Server health endpoint working"
echo "   ✅ Weaver health endpoint working"
echo "   ✅ Binary merge API working"
echo "   ✅ SSE progress stream working"

# Cleanup
rm -f /tmp/base.c /tmp/overload.c /tmp/base.bin /tmp/overload.bin
