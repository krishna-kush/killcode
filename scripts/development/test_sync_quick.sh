#!/bin/bash
set -e

echo "🧪 Quick Sync Mode Test with Live Server"
echo ""

# Test directory
TEST_DIR="/tmp/sync_quick"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Copy overload
cp /home/kay/work/WEB/killcode/overload/target/release/overload "$TEST_DIR/app"

# Create license
echo "📝 Creating license..."
LICENSE_DATA=$(curl -s -X POST http://localhost:8080/api/v1/license/create \
  -H "Content-Type: application/json" \
  -d '{"user_email": "test@example.com", "max_executions": 5}')

echo "$LICENSE_DATA" | jq .

LICENSE_ID=$(echo "$LICENSE_DATA" | jq -r '.license_id')
SECRET=$(echo "$LICENSE_DATA" | jq -r '.shared_secret')

if [ "$LICENSE_ID" = "null" ] || [ -z "$LICENSE_ID" ]; then
  echo "❌ Failed to create license"
  echo "$LICENSE_DATA"
  exit 1
fi

echo "✅ License: $LICENSE_ID"

# Create config
cat > "$TEST_DIR/app.config" << CONF
{
  "license_id": "$LICENSE_ID",
  "server_url": "http://localhost:8080/api/v1/verify",
  "shared_secret": "$SECRET",
  "execution_mode": "sync",
  "grace_period": 0,
  "self_destruct": false,
  "log_level": "debug"
}
CONF

echo "📄 Config created"
echo ""

# Run
echo "🚀 Executing..."
cd "$TEST_DIR"
chmod +x app
./app || echo "Exit code: $?"

echo ""
echo "📊 License status:"
curl -s "http://localhost:8080/api/v1/license/$LICENSE_ID" | jq '{license_id, execution_count, max_executions, authorized}'

rm -rf "$TEST_DIR"
