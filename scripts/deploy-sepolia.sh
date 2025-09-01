#!/bin/bash

# Abunfi Contracts - Sepolia Testnet Deployment Script
# This script deploys the Abunfi smart contracts to Sepolia testnet

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NETWORK="sepolia"
CHAIN_ID="11155111"
SCRIPT_NAME="DeploySepolia"

echo -e "${BLUE}=== Abunfi Sepolia Testnet Deployment ===${NC}"
echo -e "${BLUE}Network: ${NETWORK}${NC}"
echo -e "${BLUE}Chain ID: ${CHAIN_ID}${NC}"
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo -e "${YELLOW}Please copy .env.example to .env and configure your settings${NC}"
    exit 1
fi

# Load environment variables
source .env

# Validate required environment variables
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set in .env${NC}"
    exit 1
fi

if [ -z "$SEPOLIA_RPC_URL" ]; then
    echo -e "${RED}Error: SEPOLIA_RPC_URL not set in .env${NC}"
    exit 1
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo -e "${YELLOW}Warning: ETHERSCAN_API_KEY not set - contract verification will be skipped${NC}"
fi

# Check deployer balance
echo -e "${BLUE}Checking deployer balance...${NC}"
DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
BALANCE=$(cast balance $DEPLOYER_ADDRESS --rpc-url $SEPOLIA_RPC_URL)
BALANCE_ETH=$(cast to-unit $BALANCE ether)

echo -e "${GREEN}Deployer Address: ${DEPLOYER_ADDRESS}${NC}"
echo -e "${GREEN}Balance: ${BALANCE_ETH} ETH${NC}"

# Check if balance is sufficient (minimum 0.1 ETH recommended)
MIN_BALANCE="100000000000000000"  # 0.1 ETH in wei
if [ $(echo "$BALANCE < $MIN_BALANCE" | bc -l) -eq 1 ]; then
    echo -e "${RED}Error: Insufficient balance for deployment${NC}"
    echo -e "${YELLOW}Minimum recommended balance: 0.1 ETH${NC}"
    echo -e "${YELLOW}Get Sepolia ETH from: https://sepoliafaucet.com/${NC}"
    exit 1
fi

# Create deployments directory if it doesn't exist
mkdir -p deployments

# Build contracts
echo -e "${BLUE}Building contracts...${NC}"
forge build

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Contract compilation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Contracts compiled successfully${NC}"

# Run tests before deployment
echo -e "${BLUE}Running tests...${NC}"
forge test

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Tests failed${NC}"
    echo -e "${YELLOW}Please fix failing tests before deployment${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All tests passed${NC}"

# Deploy contracts
echo -e "${BLUE}Deploying contracts to Sepolia...${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"

forge script script/${SCRIPT_NAME}.s.sol:${SCRIPT_NAME} \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Deployment failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Deployment completed successfully!${NC}"

# Check if deployment file was created
DEPLOYMENT_FILE="deployments/sepolia-core.json"
if [ -f "$DEPLOYMENT_FILE" ]; then
    echo -e "${GREEN}✅ Deployment info saved to: ${DEPLOYMENT_FILE}${NC}"
    
    # Extract key addresses for quick reference
    echo -e "${BLUE}=== Quick Reference ===${NC}"
    echo -e "${GREEN}Vault Address:$(cat $DEPLOYMENT_FILE | jq -r '.contracts.core.vault')${NC}"
    echo -e "${GREEN}USDC Address: $(cat $DEPLOYMENT_FILE | jq -r '.contracts.core.usdc')${NC}"
    echo -e "${GREEN}Strategy Manager: $(cat $DEPLOYMENT_FILE | jq -r '.contracts.core.strategyManager')${NC}"
else
    echo -e "${YELLOW}Warning: Deployment file not found${NC}"
fi

# Post-deployment verification
echo -e "${BLUE}Running post-deployment verification...${NC}"

# Check if contracts are deployed and have code
VAULT_ADDRESS=$(cat $DEPLOYMENT_FILE | jq -r '.contracts.core.vault' 2>/dev/null || echo "")
if [ ! -z "$VAULT_ADDRESS" ] && [ "$VAULT_ADDRESS" != "null" ]; then
    CODE_SIZE=$(cast code $VAULT_ADDRESS --rpc-url $SEPOLIA_RPC_URL | wc -c)
    if [ $CODE_SIZE -gt 2 ]; then
        echo -e "${GREEN}✅ Vault contract deployed successfully${NC}"
    else
        echo -e "${RED}❌ Vault contract deployment verification failed${NC}"
    fi
fi

# Display next steps
echo -e "${BLUE}=== Next Steps ===${NC}"
echo -e "${GREEN}1. Verify contracts on Sepolia Etherscan:${NC}"
echo -e "   https://sepolia.etherscan.io/address/${VAULT_ADDRESS}"
echo ""
echo -e "${GREEN}2. Test the deployment:${NC}"
echo -e "   npm run test:sepolia"
echo ""
echo -e "${GREEN}3. Fund test accounts:${NC}"
echo -e "   Use the test user addresses from the deployment output"
echo ""
echo -e "${GREEN}4. Update frontend configuration:${NC}"
echo -e "   Copy the contract addresses to your frontend config"
echo ""
echo -e "${GREEN}5. Monitor the deployment:${NC}"
echo -e "   Check contract interactions and gas usage"

echo -e "${GREEN}🎉 Sepolia deployment complete! 🎉${NC}"
