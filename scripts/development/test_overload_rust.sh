#!/bin/bash

# Test script for Rust overload binary

set -e

BASE_URL="http://localhost:8080"
OVERLOAD_BIN="overload/target/release/overload"
TEST_BIN="/tmp/test_overload_rust"

echo "🧪 Testing Rust Overload Binary"
echo "================================"
echo ""

# Step 1: Create a test license
echo "📝 Step 1: Creating test license..."
LICENSE_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/license" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "rust_test_client",
    "user_email": "rust@test.com",
    "max_executions": 5,
    "allowed_machines": ["test_machine_123"],
    "expiration_days": 30
  }')

LICENSE_ID=$(echo "$LICENSE_RESPONSE" | jq -r '.license_id')
SHARED_SECRET=$(echo "$LICENSE_RESPONSE" | jq -r '.shared_secret')

echo "✅ License created:"
echo "   License ID: $LICENSE_ID"
echo "   Shared Secret: $SHARED_SECRET"
echo ""

# Step 2: Copy overload binary to temp location
echo "📦 Step 2: Copying overload binary to test location..."
cp "$OVERLOAD_BIN" "$TEST_BIN"
chmod +x "$TEST_BIN"
echo "✅ Binary copied to: $TEST_BIN"
echo ""

# Step 3: Patch config into binary at offset 0x2000
echo "🔧 Step 3: Patching configuration into binary..."

# Create config struct (must match EmbeddedConfig in Rust)
# Total size: 512 bytes
# - magic: 18 bytes
# - license_id: 64 bytes
# - server_url: 256 bytes
# - shared_secret: 64 bytes
# - grace_period: 4 bytes
# - reserved: 72 bytes
# - checksum: 32 bytes

python3 << EOF
import struct
import hashlib

# Read the binary
with open("$TEST_BIN", "rb") as f:
    data = bytearray(f.read())

# Ensure binary is large enough
CONFIG_OFFSET = 0x2000
CONFIG_SIZE = 512
if len(data) < CONFIG_OFFSET + CONFIG_SIZE:
    data.extend(b'\x00' * (CONFIG_OFFSET + CONFIG_SIZE - len(data)))

# Create config
magic = b"KILLCODE_CONFIG_V1"
license_id = "$LICENSE_ID".encode('utf-8').ljust(64, b'\x00')
server_url = b"http://localhost:8080".ljust(256, b'\x00')
shared_secret = "$SHARED_SECRET".encode('utf-8').ljust(64, b'\x00')
grace_period = struct.pack('<I', 300)  # 5 minutes
reserved = b'\x00' * 72

# Calculate checksum (SHA256 of all fields before checksum)
config_data = magic + license_id + server_url + shared_secret + grace_period + reserved
checksum = hashlib.sha256(config_data).digest()

# Write config to binary at offset
config = config_data + checksum
data[CONFIG_OFFSET:CONFIG_OFFSET+len(config)] = config

# Write modified binary
with open("$TEST_BIN", "wb") as f:
    f.write(data)

print("✅ Config patched successfully")
print(f"   Magic: {magic.decode('utf-8', errors='ignore')}")
print(f"   License ID: {license_id.decode('utf-8').rstrip(chr(0))}")
print(f"   Server URL: {server_url.decode('utf-8').rstrip(chr(0))}")
print(f"   Config offset: 0x{CONFIG_OFFSET:x}")
print(f"   Config size: {len(config)} bytes")
EOF

echo ""

# Step 4: Test successful verification
echo "✅ Step 4: Testing successful license verification..."
echo ""
OUTPUT=$("$TEST_BIN" 2>&1 || true)
echo "$OUTPUT"
echo ""

if echo "$OUTPUT" | grep -q "License verified successfully"; then
    echo "✅ SUCCESS: License verification passed!"
else
    echo "❌ FAILED: License verification did not pass"
fi
echo ""

# Step 5: Test with invalid license (should self-destruct)
echo "🔥 Step 5: Testing self-destruct with invalid license..."
cp "$OVERLOAD_BIN" "$TEST_BIN.invalid"
chmod +x "$TEST_BIN.invalid"

# Patch with invalid license ID
python3 << 'EOF'
import struct

TEST_BIN = "/tmp/test_overload_rust.invalid"

# Read the binary
with open(TEST_BIN, "rb") as f:
    data = bytearray(f.read())

CONFIG_OFFSET = 0x2000
CONFIG_SIZE = 512
if len(data) < CONFIG_OFFSET + CONFIG_SIZE:
    data.extend(b'\x00' * (CONFIG_OFFSET + CONFIG_SIZE - len(data)))

# Create config with invalid license
magic = b"KILLCODE_CONFIG_V1"
license_id = b"INVALID_LICENSE_ID_123456".ljust(64, b'\x00')
server_url = b"http://localhost:8080".ljust(256, b'\x00')
shared_secret = b"invalid_secret_12345".ljust(64, b'\x00')
grace_period = struct.pack('<I', 300)
reserved = b'\x00' * 72
checksum = b'\x00' * 32

config = magic + license_id + server_url + shared_secret + grace_period + reserved + checksum
data[CONFIG_OFFSET:CONFIG_OFFSET+len(config)] = config

with open(TEST_BIN, "wb") as f:
    f.write(data)

print("✅ Invalid config patched")
EOF

OUTPUT=$("$TEST_BIN.invalid" 2>&1 || true)
echo "$OUTPUT"
echo ""

if [ ! -f "$TEST_BIN.invalid" ]; then
    echo "✅ SUCCESS: Binary self-destructed as expected!"
else
    echo "⚠️  Binary still exists (self-destruct may not work on all filesystems)"
    rm -f "$TEST_BIN.invalid"
fi
echo ""

# Cleanup
echo "🧹 Cleaning up..."
rm -f "$TEST_BIN" "$TEST_BIN.invalid"
echo "✅ Cleanup complete"
echo ""

echo "================================"
echo "✅ All tests completed!"
