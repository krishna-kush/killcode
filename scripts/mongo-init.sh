#!/bin/bash

# Wait for MongoDB to start
sleep 5

# Initialize replica set
mongosh --eval "
try {
  rs.initiate({
    _id: 'rs0',
    members: [{ _id: 0, host: 'mongodb:27017' }]
  });
  print('Replica set initialized successfully');
} catch (e) {
  print('Replica set already initialized or error:', e);
}
"
