#!/bin/bash
set -e

echo "🧪 Testing Sync Mode with Live Server"
echo "======================================"
echo ""

# Create test directory
TEST_DIR="/tmp/sync_test_live"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Copy overload
cp /home/kay/work/WEB/killcode/overload/target/release/overload "$TEST_DIR/test_app"
chmod +x "$TEST_DIR/test_app"

# Create license via API
echo "📝 Creating license..."
LICENSE_RESP=$(curl -s -X POST http://localhost:8080/api/v1/licenses \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "test@example.com",
    "max_executions": 5,
    "expires_at": "2025-12-31T23:59:59Z"
  }')

LICENSE_ID=$(echo "$LICENSE_RESP" | jq -r '.license_id')
SHARED_SECRET=$(echo "$LICENSE_RESP" | jq -r '.shared_secret')

echo "✅ License created: $LICENSE_ID"
echo ""

# Create config with correct server URL
cat > "$TEST_DIR/test_app.config" << EOFCONFIG
{
  "license_id": "$LICENSE_ID",
  "server_url": "http://localhost:8080/api/v1/verify",
  "shared_secret": "$SHARED_SECRET",
  "execution_mode": "sync",
  "grace_period": 0,
  "self_destruct": false,
  "log_level": "debug"
}
EOFCONFIG

echo "📄 Config created"
echo ""

# Run the test
echo "🚀 Running overload in sync mode..."
cd "$TEST_DIR"
./test_app

echo ""
echo "✅ Test completed successfully!"

# Check execution count
echo ""
echo "📊 Checking execution count..."
curl -s "http://localhost:8080/api/v1/licenses/$LICENSE_ID" | jq '{license_id, execution_count, max_executions}'

# Cleanup
rm -rf "$TEST_DIR"
