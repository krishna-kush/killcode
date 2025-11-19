#!/bin/bash
set -e

# NOTE: This script is required because the standard /docker-entrypoint-initdb.d/ scripts
# (like mongo-init.sh) ONLY run on a fresh database (empty data directory).
# In a production environment with existing data, those scripts are ignored.
# This script runs on every container start to ensure the replica set is correctly
# initialized and healthy, regardless of whether data already exists.

echo "Waiting for MongoDB to be ready..."
# Try to connect without auth first to check availability, or with auth if needed.
# Since we are running this from a separate container, we need to connect to 'mongodb' host.

# Loop until we can connect
max_retries=30
count=0
while [ $count -lt $max_retries ]; do
    if mongosh --host mongodb --port 27017 --eval "db.runCommand('ping')" --quiet > /dev/null 2>&1; then
        echo "MongoDB is ready (no auth)."
        break
    fi
    # Try with auth if no-auth fails (it might fail if auth is enabled and required even for ping, though usually ping works? No, with --keyFile and auth enabled, you need auth)
    if mongosh --host mongodb --port 27017 -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.runCommand('ping')" --quiet > /dev/null 2>&1; then
        echo "MongoDB is ready (with auth)."
        break
    fi
    
    echo "Waiting for MongoDB... ($count/$max_retries)"
    sleep 2
    count=$((count + 1))
done

if [ $count -eq $max_retries ]; then
    echo "Timed out waiting for MongoDB."
    exit 1
fi

echo "Checking Replica Set status..."

# We use the credentials provided in environment variables
mongosh --host mongodb --port 27017 -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "
try {
    var status = rs.status();
    if (status.ok === 1) {
        print('Replica set already initialized.');
        
        // Optional: Check if the host is correct
        var config = rs.config();
        var member = config.members[0];
        if (member.host !== 'mongodb:27017') {
            print('Warning: Replica set member host is ' + member.host + ', expected mongodb:27017.');
            // We could reconfigure here if needed, but let's be careful.
        }
    } else {
        print('Replica set status not ok. Code: ' + status.code);
        // Try to initiate
        throw new Error('Not initialized');
    }
} catch (e) {
    print('Replica set not initialized or error: ' + e);
    print('Initializing replica set...');
    try {
        rs.initiate({
            _id: 'rs0',
            members: [{ _id: 0, host: 'mongodb:27017' }]
        });
        print('Replica set initialized successfully.');
    } catch (initError) {
        print('Failed to initialize replica set: ' + initError);
        quit(1);
    }
}
"
