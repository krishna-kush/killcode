#!/bin/bash

# Simple direct test of Rust overload binary

set -e

BASE_URL="http://localhost:8080"
OVERLOAD_BIN="overload/target/release/overload"
TEST_BIN="/tmp/test_rust_overload"
TEST_CONFIG="/tmp/test_rust_overload.config"

echo "🧪 Simple Rust Overload Test"
echo "=============================="
echo ""

# Manual license credentials (you should create these in MongoDB or via API)
# For now, let's create a test license using the old test script data

echo "Creating test license via old working endpoint..."

# Try to use a working test license
LICENSE_ID="test_license_123"
SHARED_SECRET="test_secret_456"

echo "Using test credentials:"
echo "  License ID: $LICENSE_ID"
echo "  Secret: $SHARED_SECRET"
echo ""

# Copy overload
cp "$OVERLOAD_BIN" "$TEST_BIN"
chmod +x "$TEST_BIN"

# Create config
cat > "$TEST_CONFIG" << EOF
{
  "license_id": "$LICENSE_ID",
  "server_url": "$BASE_URL",
  "shared_secret": "$SHARED_SECRET"
}
EOF

echo "Config created. Testing..."
echo ""

# Run the binary
OUTPUT=$("$TEST_BIN" 2>&1 || true)
echo "$OUTPUT"
echo ""

# Cleanup
rm -f "$TEST_BIN" "$TEST_CONFIG"

echo "Test complete!"
