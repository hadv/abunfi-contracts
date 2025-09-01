#!/bin/bash

# Abunfi Contracts - Deployment Testing Script
# This script tests the deployment setup without actually deploying

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Abunfi Deployment Setup Test ===${NC}"

# Check if required files exist
echo -e "${BLUE}Checking required files...${NC}"

REQUIRED_FILES=(
    ".env.example"
    "script/Deploy.s.sol"
    "script/DeploySepolia.s.sol"
    "script/DeployEIP7702.s.sol"
    "scripts/deploy-sepolia.sh"
    "foundry.toml"
    "DEPLOYMENT.md"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅ $file${NC}"
    else
        echo -e "${RED}❌ $file (missing)${NC}"
        exit 1
    fi
done

# Check if .env exists
if [ -f ".env" ]; then
    echo -e "${GREEN}✅ .env file exists${NC}"
    
    # Check if required variables are set
    source .env
    
    if [ -z "$PRIVATE_KEY" ]; then
        echo -e "${YELLOW}⚠️  PRIVATE_KEY not set in .env${NC}"
    else
        echo -e "${GREEN}✅ PRIVATE_KEY is set${NC}"
    fi
    
    if [ -z "$SEPOLIA_RPC_URL" ]; then
        echo -e "${YELLOW}⚠️  SEPOLIA_RPC_URL not set in .env${NC}"
    else
        echo -e "${GREEN}✅ SEPOLIA_RPC_URL is set${NC}"
    fi
    
    if [ -z "$ETHERSCAN_API_KEY" ]; then
        echo -e "${YELLOW}⚠️  ETHERSCAN_API_KEY not set in .env${NC}"
    else
        echo -e "${GREEN}✅ ETHERSCAN_API_KEY is set${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  .env file not found. Copy .env.example to .env and configure it.${NC}"
fi

# Check if deployments directory exists
if [ -d "deployments" ]; then
    echo -e "${GREEN}✅ deployments directory exists${NC}"
else
    echo -e "${YELLOW}⚠️  deployments directory not found. Creating it...${NC}"
    mkdir -p deployments
    echo -e "${GREEN}✅ deployments directory created${NC}"
fi

# Check if scripts are executable
if [ -x "scripts/deploy-sepolia.sh" ]; then
    echo -e "${GREEN}✅ deploy-sepolia.sh is executable${NC}"
else
    echo -e "${YELLOW}⚠️  deploy-sepolia.sh is not executable. Making it executable...${NC}"
    chmod +x scripts/deploy-sepolia.sh
    echo -e "${GREEN}✅ deploy-sepolia.sh is now executable${NC}"
fi

# Test contract compilation
echo -e "${BLUE}Testing contract compilation...${NC}"
if forge build > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Contracts compile successfully${NC}"
else
    echo -e "${RED}❌ Contract compilation failed${NC}"
    echo -e "${YELLOW}Run 'forge build' to see detailed errors${NC}"
    exit 1
fi

# Test contract tests
echo -e "${BLUE}Testing contract tests...${NC}"
if forge test > /dev/null 2>&1; then
    echo -e "${GREEN}✅ All tests pass${NC}"
else
    echo -e "${RED}❌ Some tests are failing${NC}"
    echo -e "${YELLOW}Run 'forge test -vvv' to see detailed test results${NC}"
    exit 1
fi

# Check Foundry tools
echo -e "${BLUE}Checking Foundry tools...${NC}"

if command -v forge &> /dev/null; then
    echo -e "${GREEN}✅ forge is installed${NC}"
    forge --version
else
    echo -e "${RED}❌ forge is not installed${NC}"
    exit 1
fi

if command -v cast &> /dev/null; then
    echo -e "${GREEN}✅ cast is installed${NC}"
else
    echo -e "${RED}❌ cast is not installed${NC}"
    exit 1
fi

# Check additional tools
echo -e "${BLUE}Checking additional tools...${NC}"

if command -v jq &> /dev/null; then
    echo -e "${GREEN}✅ jq is installed${NC}"
else
    echo -e "${YELLOW}⚠️  jq is not installed (recommended for deployment scripts)${NC}"
    echo -e "${YELLOW}Install with: brew install jq (macOS) or sudo apt-get install jq (Ubuntu)${NC}"
fi

if command -v node &> /dev/null; then
    echo -e "${GREEN}✅ Node.js is installed${NC}"
    node --version
else
    echo -e "${YELLOW}⚠️  Node.js is not installed (optional)${NC}"
fi

# Test package.json scripts
echo -e "${BLUE}Testing package.json scripts...${NC}"

if [ -f "package.json" ]; then
    echo -e "${GREEN}✅ package.json exists${NC}"
    
    # Check if npm scripts are properly defined
    if grep -q "deploy:sepolia" package.json; then
        echo -e "${GREEN}✅ deploy:sepolia script is defined${NC}"
    else
        echo -e "${RED}❌ deploy:sepolia script is missing${NC}"
    fi
    
    if grep -q "deploy:eip7702" package.json; then
        echo -e "${GREEN}✅ deploy:eip7702 script is defined${NC}"
    else
        echo -e "${RED}❌ deploy:eip7702 script is missing${NC}"
    fi
else
    echo -e "${RED}❌ package.json not found${NC}"
fi

# Summary
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "${GREEN}✅ Deployment setup is ready!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "${GREEN}1. Configure your .env file with real values${NC}"
echo -e "${GREEN}2. Get Sepolia ETH from https://sepoliafaucet.com/${NC}"
echo -e "${GREEN}3. Run deployment: ./scripts/deploy-sepolia.sh${NC}"
echo -e "${GREEN}4. Verify contracts on Sepolia Etherscan${NC}"
echo ""
echo -e "${BLUE}Available deployment commands:${NC}"
echo -e "${GREEN}• ./scripts/deploy-sepolia.sh          # Full Sepolia deployment${NC}"
echo -e "${GREEN}• npm run deploy:sepolia               # Core contracts only${NC}"
echo -e "${GREEN}• npm run deploy:eip7702               # EIP-7702 gasless infrastructure${NC}"
echo -e "${GREEN}• npm run test:sepolia                 # Test against Sepolia${NC}"
echo ""
echo -e "${GREEN}🎉 Ready for deployment! 🎉${NC}"
