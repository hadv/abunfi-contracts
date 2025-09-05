# RISC Zero Social Verification System

## Overview

This document describes the implementation of a ZK-based social verification system using RISC Zero zkVM to prevent DOS and Sybil attacks on gasless transactions. The system ensures that each social account can only be linked to one unique wallet address, providing strong Sybil resistance while preserving user privacy.

## Architecture

### Core Components

1. **SocialAccountRegistry Contract**: Manages social account to wallet mappings
2. **RiscZeroSocialVerifier Contract**: Handles ZK proof verification
3. **RISC Zero Guest Program**: Verifies OAuth tokens and generates proofs
4. **Enhanced EIP7702Paymaster**: Integrates social verification into gas sponsorship

### System Flow

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Frontend      │    │   RISC Zero      │    │  Smart Contract │
│   (Web3Auth)    │───▶│   Guest Program  │───▶│   Verification  │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
        │                        │                        │
        │                        │                        │
        ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ OAuth Provider  │    │   HTTP Client    │    │ Social Registry │
│ (Twitter/etc)   │    │   JSON Parser    │    │   Contract      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Key Features

### 1. Sybil Attack Prevention
- **One Social Account = One Wallet**: Each social account can only be linked to one wallet address
- **ZK Proof Verification**: Uses RISC Zero to verify OAuth tokens without revealing sensitive data
- **Platform Requirements**: Configurable minimum account age, followers, etc.

### 2. DOS Attack Prevention
- **Tiered Rate Limiting**: Different limits based on verification level
- **Social Verification Requirements**: Higher limits for verified accounts
- **Behavioral Analysis**: Future enhancement for pattern detection

### 3. Privacy Preservation
- **Zero Knowledge Proofs**: Only proof of verification is public, not actual social data
- **OAuth Token Privacy**: Tokens are processed in zkVM, never stored on-chain
- **Selective Disclosure**: Users control what information is revealed

## Supported Social Platforms

| Platform | Status | Minimum Age | Minimum Followers | Additional Requirements |
|----------|--------|-------------|-------------------|------------------------|
| Twitter  | ✅ Active | 30 days | 10 | None |
| Discord  | ✅ Active | 14 days | 0 | None |
| GitHub   | ✅ Active | 90 days | 5 | Repository activity |
| Telegram | 🚧 Planned | 30 days | 0 | Bot verification |
| LinkedIn | 🚧 Planned | 60 days | 10 | Professional verification |

## Implementation Guide

### 1. Deploy Contracts

```bash
# Deploy Social Account Registry
forge create src/eip7702/SocialAccountRegistry.sol:SocialAccountRegistry \
  --constructor-args <RISC_ZERO_VERIFIER_ADDRESS>

# Deploy RISC Zero Verifier
forge create src/eip7702/RiscZeroSocialVerifier.sol:RiscZeroSocialVerifier \
  --constructor-args <RISC_ZERO_KEY> <SOCIAL_REGISTRY_ADDRESS>

# Deploy Enhanced Paymaster
forge create src/eip7702/EIP7702Paymaster.sol:EIP7702Paymaster \
  --constructor-args <SOCIAL_REGISTRY_ADDRESS>
```

### 2. Setup RISC Zero Environment

```bash
# Install RISC Zero toolchain
curl -L https://risczero.com/install | bash
rzup install

# Build guest program
cd risc0-social-verifier
cargo build --release

# Run verification service
cargo run --bin host -- twitter <OAUTH_TOKEN> <WALLET_ADDRESS>
```

### 3. Frontend Integration

```javascript
// Example: Twitter verification
const verifyTwitterAccount = async (oauthToken, walletAddress) => {
  // Request verification from RISC Zero service
  const response = await fetch('/api/verify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      platform: 'twitter',
      oauth_token: oauthToken,
      wallet_address: walletAddress
    })
  });
  
  const result = await response.json();
  
  if (result.success) {
    // Submit proof to Social Registry
    const proof = {
      socialAccountHash: result.social_account_hash,
      walletAddress: walletAddress,
      platform: 0, // Twitter
      accountAge: result.account_age,
      followerCount: result.follower_count,
      timestamp: Math.floor(Date.now() / 1000),
      proofHash: result.proof_hash,
      signature: result.signature
    };
    
    await socialRegistry.linkSocialAccount(proof);
  }
};
```

## Security Considerations

### 1. OAuth Token Security
- **Temporary Tokens**: Use short-lived OAuth tokens
- **Secure Transmission**: HTTPS only for token transmission
- **No Storage**: Tokens are never stored, only processed in zkVM

### 2. Proof Verification
- **Signature Validation**: All proofs must be signed by authorized verifiers
- **Timestamp Checks**: Proofs have limited validity periods
- **Replay Protection**: Each proof can only be used once

### 3. Rate Limiting
- **Verification Cooldowns**: Prevent frequent re-verification attempts
- **Platform Limits**: Different limits for different platforms
- **Emergency Controls**: Admin can pause verification if needed

## Configuration

### Platform Configuration Example

```solidity
// Twitter configuration
platformConfigs[SocialPlatform.TWITTER] = PlatformConfig({
    isEnabled: true,
    minimumAccountAge: 30 days,
    minimumFollowers: 10,
    verificationCooldown: 7 days,
    requiresAdditionalVerification: false
});
```

### Sponsorship Policy Example

```solidity
// Enhanced policy with social verification
SponsorshipPolicy memory policy = SponsorshipPolicy({
    dailyGasLimit: 0.1 ether,
    perTxGasLimit: 0.01 ether,
    dailyTxLimit: 50,
    requiresWhitelist: false,
    requiresSocialVerification: true,
    minimumVerificationLevel: 1,
    isActive: true
});
```

## Benefits Over Alternatives

### vs. WorldID
- **Custom Logic**: Full control over verification criteria
- **Multiple Platforms**: Support for various social platforms
- **No Hardware**: No need for Orb verification
- **Flexible Requirements**: Configurable per platform

### vs. Reclaim Protocol
- **General Purpose**: Can handle any OAuth flow
- **Custom Verification**: Implement specific business logic
- **Better Privacy**: Full ZK execution environment
- **Cost Effective**: No per-verification fees

### vs. Simple Rate Limiting
- **Sybil Resistance**: Prevents multiple wallet creation
- **Identity Verification**: Ensures real human users
- **Tiered Access**: Better UX for verified users
- **Attack Prevention**: Comprehensive protection

## Future Enhancements

### 1. Advanced Verification
- **Cross-Platform Verification**: Require multiple social accounts
- **Reputation Scoring**: Dynamic limits based on account reputation
- **Machine Learning**: Behavioral pattern analysis

### 2. Additional Platforms
- **Web2 Integration**: Email, phone number verification
- **Professional Networks**: LinkedIn, professional certifications
- **Gaming Platforms**: Steam, Epic Games, etc.

### 3. Privacy Enhancements
- **Anonymous Credentials**: Zero-knowledge credentials
- **Selective Disclosure**: Fine-grained privacy controls
- **Decentralized Identity**: Integration with DID standards

## Deployment Checklist

- [ ] Deploy SocialAccountRegistry contract
- [ ] Deploy RiscZeroSocialVerifier contract  
- [ ] Deploy enhanced EIP7702Paymaster
- [ ] Setup RISC Zero verification service
- [ ] Configure platform requirements
- [ ] Test verification flow end-to-end
- [ ] Setup monitoring and alerts
- [ ] Document API endpoints
- [ ] Create frontend integration examples
- [ ] Conduct security audit

## API Reference

### SocialAccountRegistry

```solidity
function linkSocialAccount(VerificationProof calldata proof) external;
function getVerificationStatus(address walletAddress) external view returns (bool, uint256);
function isSocialAccountLinked(bytes32 socialAccountHash) external view returns (bool, address);
```

### RiscZeroSocialVerifier

```solidity
function requestVerification(SocialPlatform platform, string calldata oauthToken, address walletAddress) external returns (bytes32);
function submitProof(bytes32 requestId, ProofData calldata proofData, bytes calldata riscZeroProof, bytes calldata signature) external;
function getVerificationResult(bytes32 requestId) external view returns (bool, bool, ProofData memory);
```

### Enhanced EIP7702Paymaster

```solidity
function validateUserOperation(UserOperation calldata userOp, UserOperationContext calldata context) external view returns (bool, uint256);
function setSocialRegistry(address _socialRegistry) external;
```

## Support and Resources

- **Documentation**: [Full API Documentation](./API_REFERENCE.md)
- **Examples**: [Integration Examples](../examples/)
- **Support**: [GitHub Issues](https://github.com/your-repo/issues)
- **Community**: [Discord Server](https://discord.gg/your-server)

## License

This project is licensed under the MIT License. See [LICENSE](../LICENSE) for details.
