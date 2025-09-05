# Token Management Test Cases

This directory contains comprehensive test cases demonstrating how the RISC Zero social verification system handles OAuth token changes while maintaining secure account-to-wallet mappings.

## Overview

OAuth tokens are temporary and change frequently due to:
- **Expiration**: Access tokens typically expire in 15 minutes to 1 hour
- **Refresh**: New tokens generated from refresh tokens
- **Re-authorization**: Users re-authorizing the app
- **Revocation**: Users revoking and re-granting permissions

Our system handles these changes by relying on **stable account identifiers** rather than the tokens themselves.

## Test Categories

### 1. **Unit Tests** (`risc0-social-verifier/tests/token_management_tests.rs`)

Rust-based tests for the RISC Zero guest program logic:

```bash
cd risc0-social-verifier
cargo test token_management_tests
```

**Test Cases:**
- ✅ `test_token_expiration_and_refresh` - Token changes over time
- ✅ `test_username_change_with_same_account` - Username updates
- ✅ `test_invalid_token_scenarios` - Malformed/expired tokens
- ✅ `test_account_takeover_attempt` - Security attack simulation
- ✅ `test_multiple_platform_verification` - Cross-platform verification

### 2. **Integration Tests** (`test/TokenManagementIntegration.t.sol`)

Solidity-based tests for smart contract integration:

```bash
forge test --match-contract TokenManagementIntegrationTest -vvv
```

**Test Cases:**
- ✅ `test_TokenExpirationAndReverification` - End-to-end token refresh
- ✅ `test_UsernameChangeWithSameAccount` - Account consistency
- ✅ `test_AccountTakeoverAttempt` - Attack prevention
- ✅ `test_MultiPlatformVerification` - Multiple social platforms
- ✅ `test_PaymasterIntegrationWithSocialVerification` - Gas sponsorship

### 3. **Demo Script** (`examples/token-management-demo/demo.js`)

Interactive demonstration of token management scenarios:

```bash
cd examples/token-management-demo
npm install
node demo.js
```

## Key Test Scenarios

### 🔄 **Scenario 1: Token Expiration and Refresh**

```
Day 1:  User verifies with token "abc123" → Account ID "123456789" → Hash "0x1a2b3c..."
Day 30: Token expires, user gets new token "xyz789" → Same Account ID → Same Hash
Day 60: App re-authorized, new token "def456" → Same Account ID → Same Hash
```

**Expected Result**: ✅ All verifications produce the same hash

### 👤 **Scenario 2: Username Change**

```
Week 1: Username "alice_defi" + Account ID "123456789" → Hash "0x1a2b3c..."
Week 3: Username "alice_web3" + Same Account ID → Same Hash
Week 5: Username "alice_crypto" + Same Account ID → Same Hash
```

**Expected Result**: ✅ Hash remains consistent despite username changes

### 🚨 **Scenario 3: Account Takeover Attempt**

```
Legitimate: Account ID "123456789" + Token "legitimate" → Hash "0x1a2b3c..."
Attacker:   Account ID "987654321" + Token "stolen" → Hash "0x9z8y7x..." (different!)
```

**Expected Result**: ✅ Different account IDs produce different hashes, attack detected

### 🌐 **Scenario 4: Multi-Platform Verification**

```
Twitter:  Account ID "123456789" → Hash "0x1a2b3c..."
GitHub:   Account ID "987654321" → Hash "0x9z8y7x..." (different platform)
Discord:  Account ID "555666777" → Hash "0x5f4e3d..." (different platform)
```

**Expected Result**: ✅ Same wallet can link multiple platforms with different hashes

## Running All Tests

### Prerequisites

```bash
# Install Rust and Cargo
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Node.js dependencies
npm install
```

### Run Complete Test Suite

```bash
# 1. Run Rust unit tests
cd risc0-social-verifier
cargo test token_management_tests --verbose

# 2. Run Solidity integration tests  
cd ..
forge test --match-contract TokenManagementIntegrationTest -vvv

# 3. Run interactive demo
cd examples/token-management-demo
node demo.js
```

## Expected Output

### ✅ **Successful Test Run**

```
🧪 Testing: Token Expiration and Refresh
✅ Initial verification successful
   Account ID: 123456789
   Hash: 0x1a2b3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890

✅ Re-verification with new token successful
   Same Account ID: 123456789
   Same Hash: 0x1a2b3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890

✅ Third verification with re-authorized token successful
   Consistent Hash across all verifications

📊 RESULTS ANALYSIS:
   All verifications successful: true
   Same account ID: true
   Same hash generated: true
```

### 🚨 **Security Test Results**

```
🧪 Testing: Account Takeover Attempt
✅ Legitimate account linked
🚨 Attacker's Takeover Attempt
✅ Attack detected

📊 SECURITY ANALYSIS:
   Legitimate user hash: 0x1a2b3c4d...
   Attacker's hash: 0x9z8y7x6w...
   Hashes are different: true
   Attacker verification type: ACCOUNT_UPDATE
   Attacker consistency score: 25/100
   🛡️ Attack detected: YES
```

## Key Insights

### 🔑 **Why This Works**

1. **Stable Identifiers**: We use permanent account IDs, not temporary tokens
2. **Consistent Hashing**: Same account ID always produces same hash
3. **Token Independence**: Hash generation doesn't depend on token content
4. **Attack Detection**: Different account IDs are flagged as suspicious

### 🛡️ **Security Benefits**

- ✅ **Token Theft Protection**: Stolen tokens can't change existing mappings
- ✅ **Account Takeover Prevention**: Different accounts produce different hashes
- ✅ **Replay Attack Resistance**: Nonce system prevents token reuse
- ✅ **Consistency Monitoring**: Suspicious changes are flagged and scored

### 🚀 **User Experience**

- ✅ **Seamless Re-verification**: Users can update tokens without losing verification
- ✅ **Username Changes**: Account updates don't break verification
- ✅ **Multiple Platforms**: Users can verify across different social platforms
- ✅ **Privacy Preservation**: Only necessary data is revealed through ZK proofs

## Troubleshooting

### Common Issues

1. **Test Failures**: Ensure all dependencies are installed
2. **Compilation Errors**: Check Rust and Solidity compiler versions
3. **Network Issues**: Some tests may require internet connectivity for mocking

### Debug Mode

Run tests with verbose output:

```bash
# Rust tests with debug output
RUST_LOG=debug cargo test token_management_tests

# Solidity tests with detailed traces
forge test --match-contract TokenManagementIntegrationTest -vvvv

# Demo with detailed logging
DEBUG=true node demo.js
```

## Contributing

To add new test cases:

1. **Rust Tests**: Add to `risc0-social-verifier/tests/token_management_tests.rs`
2. **Solidity Tests**: Add to `test/TokenManagementIntegration.t.sol`
3. **Demo Scenarios**: Add to `examples/token-management-demo/demo.js`

Follow the existing patterns and ensure all tests pass before submitting.

---

**Note**: These tests demonstrate that our RISC Zero social verification system provides robust protection against token-related attacks while maintaining excellent user experience even as OAuth tokens change over time.
