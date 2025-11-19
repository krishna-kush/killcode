#!/bin/sh
# Initialize MongoDB keyfile for replica set authentication
# This script runs in a Docker container to ensure the keyfile exists

KEYFILE_PATH="/secrets/mongodb-keyfile"
KEYFILE_DIR="/secrets"

echo "Checking for MongoDB keyfile..."

# Create secrets directory if it doesn't exist
mkdir -p "$KEYFILE_DIR"

if [ -f "$KEYFILE_PATH" ] && [ -s "$KEYFILE_PATH" ]; then
    echo "✓ MongoDB keyfile already exists and is not empty"
else
    echo "Generating MongoDB keyfile..."
    
    # Generate keyfile with random data
    openssl rand -base64 756 > "$KEYFILE_PATH"
    
    # Verify the file has content
    if [ -s "$KEYFILE_PATH" ]; then
        echo "✓ MongoDB keyfile generated ($(wc -c < "$KEYFILE_PATH") bytes)"
    else
        echo "✗ ERROR: Keyfile generation failed - file is empty"
        exit 1
    fi
fi

# Set correct permissions
chmod 600 "$KEYFILE_PATH"
chown 999:999 "$KEYFILE_PATH"

echo "✓ Keyfile ready at $KEYFILE_PATH"
