#!/bin/bash

# Fast test runner for development
# Usage: ./scripts/test-fast.sh [test-name]

set -e

echo "🚀 Running fast tests..."

# Set CI profile for faster compilation
export FOUNDRY_PROFILE=ci

# If specific test provided, run only that test
if [ $# -eq 1 ]; then
    echo "Running specific test: $1"
    forge test --match-test "$1" -v
    exit 0
fi

echo "📦 Building contracts..."
timeout 300 forge build || {
    echo "❌ Build timed out after 5 minutes"
    exit 1
}

echo "🧪 Running unit tests (excluding slow integration tests)..."
timeout 300 forge test --no-match-path "test/**/TokenManagementIntegration.t.sol" -v || {
    echo "❌ Tests timed out after 5 minutes"
    exit 1
}

echo "✅ Fast tests completed!"
echo ""
echo "💡 To run integration tests:"
echo "   forge test --match-path 'test/**/TokenManagementIntegration.t.sol' -v"
echo ""
echo "💡 To run a specific test:"
echo "   ./scripts/test-fast.sh test_TokenExpirationAndReverification"
