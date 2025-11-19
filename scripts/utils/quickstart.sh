#!/bin/bash
################################################################################
# Quick Start - Full System Setup and Test
#
# Description:
#   Complete workflow demonstration for KillCode license system:
#   - Starts services (Docker Compose)
#   - Uploads base binary
#   - Downloads merged binary
#   - Tests execution
#   - Shows verification in action
#
# Usage:
#   ./quickstart.sh
################################################################################

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=================================================="
echo "  🚀 KillCode License System - Quick Start"
echo "=================================================="
echo ""

# Step 1: Check prerequisites
echo -e "${BLUE}Step 1: Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker first.${NC}"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    echo -e "${RED}❌ Docker Compose not found. Please install Docker Compose first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker and Docker Compose found${NC}"
echo ""

# Step 2: Build overload binary
echo -e "${BLUE}Step 2: Building overload binary...${NC}"

cd overload

# Check if dependencies are installed
if ! command -v gcc &> /dev/null; then
    echo -e "${YELLOW}⚠️  GCC not found. Installing dependencies...${NC}"
    sudo apt-get update
    sudo apt-get install -y build-essential libcurl4-openssl-dev libssl-dev
fi

# Build
echo "Building overload binary for x86_64..."
make clean 2>/dev/null || true
make

if [ -f "bin/overload-x86_64" ]; then
    echo -e "${GREEN}✅ Overload binary built successfully${NC}"
    file bin/overload-x86_64
    size bin/overload-x86_64
else
    echo -e "${RED}❌ Failed to build overload binary${NC}"
    exit 1
fi

# Install to server templates
echo "Installing overload template..."
make install

cd ..
echo ""

# Step 3: Start services
echo -e "${BLUE}Step 3: Starting Docker services...${NC}"

# Stop any existing containers
docker compose down 2>/dev/null || true

# Start services
echo "Starting MongoDB, Redis, Server, and Weaver..."
docker compose up -d

# Wait for services to be ready
echo "Waiting for services to initialize..."
sleep 15

# Check if services are running
if ! docker compose ps | grep -q "Up"; then
    echo -e "${RED}❌ Services failed to start${NC}"
    docker compose logs
    exit 1
fi

echo -e "${GREEN}✅ All services are running${NC}"
echo ""

# Step 4: Test health
echo -e "${BLUE}Step 4: Testing service health...${NC}"

# Test server
SERVER_HEALTH=$(curl -s http://localhost:8080/health)
if echo "$SERVER_HEALTH" | grep -q "ok\|healthy"; then
    echo -e "${GREEN}✅ Server is healthy${NC}"
else
    echo -e "${RED}❌ Server health check failed${NC}"
    exit 1
fi

# Test Weaver
WEAVER_HEALTH=$(curl -s http://localhost:8081/health)
if echo "$WEAVER_HEALTH" | grep -q "ok\|healthy"; then
    echo -e "${GREEN}✅ Weaver is healthy${NC}"
else
    echo -e "${YELLOW}⚠️  Weaver health check returned: $WEAVER_HEALTH${NC}"
fi

echo ""

# Step 5: Run license system tests
echo -e "${BLUE}Step 5: Running license system integration tests...${NC}"
echo ""

./test_license_system.sh

echo ""

# Step 6: Summary
echo "=================================================="
echo "  🎉 Quick Start Complete!"
echo "=================================================="
echo ""
echo -e "${GREEN}✅ Services Running:${NC}"
echo "   - Server:  http://localhost:8080"
echo "   - Weaver:  http://localhost:8081"
echo "   - MongoDB: localhost:27017"
echo "   - Redis:   localhost:6379"
echo ""
echo -e "${GREEN}✅ Overload Binary:${NC}"
echo "   - Location: overload/bin/overload-x86_64"
echo "   - Template: server/overload-templates/overload-x86_64"
echo ""
echo -e "${GREEN}✅ Tests Passed:${NC}"
echo "   - Binary upload with license creation"
echo "   - HMAC signature validation"
echo "   - Timestamp replay protection"
echo "   - License management (CRUD)"
echo "   - License revocation"
echo ""
echo -e "${BLUE}📚 Next Steps:${NC}"
echo ""
echo "1. View service logs:"
echo "   ${YELLOW}docker compose logs -f${NC}"
echo ""
echo "2. Upload a binary:"
echo "   ${YELLOW}curl -X POST http://localhost:8080/binary/upload \\
     -F \"binary=@/path/to/binary\" \\
     -F \"user_id=test_user\"${NC}"
echo ""
echo "3. View MongoDB data:"
echo "   ${YELLOW}docker compose exec mongo mongosh${NC}"
echo "   ${YELLOW}use killcode${NC}"
echo "   ${YELLOW}db.licenses.find().pretty()${NC}"
echo ""
echo "4. Stop services:"
echo "   ${YELLOW}docker compose down${NC}"
echo ""
echo "5. Read documentation:"
echo "   - ${YELLOW}LICENSE_API.md${NC} - API reference"
echo "   - ${YELLOW}IMPLEMENTATION_SUMMARY.md${NC} - What was built"
echo "   - ${YELLOW}overload/README.md${NC} - Overload details"
echo ""
echo "=================================================="
echo "  🔐 Your binaries are now protected with licenses!"
echo "=================================================="
