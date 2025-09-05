# Token Management & Security in Social Verification

## Overview

This document explains how our RISC Zero social verification system handles OAuth token changes while maintaining secure and consistent user account linking.

## Key Security Principles

### 1. **Stable Account Identifiers**

We rely on **permanent account identifiers**, not temporary tokens:

| Platform | Stable Identifier | Example | Changes Over Time? |
|----------|------------------|---------|-------------------|
| Twitter | User ID | `123456789` | ❌ Never |
| Discord | User ID (Snowflake) | `987654321012345678` | ❌ Never |
| GitHub | User ID | `12345` | ❌ Never |
| Username | Handle/Login | `@username` | ✅ Can change |
| OAuth Token | Access Token | `abc123...` | ✅ Expires/refreshes |

### 2. **Hash Generation Strategy**

```rust
fn generate_social_account_hash(platform: &SocialPlatform, account_id: &str) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(format!("{:?}", platform).as_bytes());
    hasher.update(account_id.as_bytes()); // Using stable ID, not token
    hasher.finalize().into()
}
```

**Key Point**: The hash is generated from the **permanent account ID**, ensuring consistency even when tokens change.

## Token Lifecycle Management

### 1. **Initial Verification Flow**

```
User → OAuth Provider → Get Token → RISC Zero Guest → Extract Account ID → Generate Hash → Store Mapping
```

### 2. **Re-verification with New Token**

```
User → OAuth Provider → Get New Token → RISC Zero Guest → Extract Same Account ID → Generate Same Hash → Verify Existing Mapping
```

### 3. **Token Expiration Handling**

When tokens expire:
- ✅ **Account mapping remains valid** (based on stable ID)
- ✅ **User can re-verify** with new token
- ✅ **Same hash is generated** (same account ID)
- ✅ **No duplicate mappings** created

## Enhanced Security Measures

### 1. **Account Consistency Verification**

```rust
struct AccountConsistencyCheck {
    account_id: String,
    username: String,
    creation_date: String,
    verification_timestamp: u64,
    previous_verification_hash: Option<[u8; 32]>,
}

fn verify_account_consistency(
    current_data: &AccountData,
    previous_verification: Option<&AccountConsistencyCheck>
) -> bool {
    if let Some(prev) = previous_verification {
        // Account ID must match (never changes)
        if current_data.id != prev.account_id {
            return false;
        }
        
        // Creation date must match (immutable)
        if current_data.created_at != prev.creation_date {
            return false;
        }
        
        // Username can change, but we log it for monitoring
        if current_data.username != prev.username {
            log_username_change(&prev.username, &current_data.username);
        }
    }
    
    true
}
```

### 2. **Token Validation Enhancements**

```rust
fn validate_oauth_token(token: &str, platform: &SocialPlatform) -> Result<TokenInfo, TokenError> {
    // 1. Check token format
    if !is_valid_token_format(token, platform) {
        return Err(TokenError::InvalidFormat);
    }
    
    // 2. Verify token is not expired
    let token_info = decode_token_info(token)?;
    if token_info.expires_at < current_timestamp() {
        return Err(TokenError::Expired);
    }
    
    // 3. Check token scope/permissions
    if !has_required_permissions(&token_info, platform) {
        return Err(TokenError::InsufficientPermissions);
    }
    
    Ok(token_info)
}
```

### 3. **Re-verification Logic**

```rust
fn handle_reverification(
    input: &VerificationInput,
    existing_mapping: Option<&SocialAccountMapping>
) -> VerificationResult {
    // Extract account data with new token
    let account_data = fetch_account_data(&input.oauth_token, &input.platform)?;
    
    if let Some(existing) = existing_mapping {
        // Verify this is the same account
        if account_data.id != existing.social_account_id {
            return Err(VerificationError::AccountMismatch);
        }
        
        // Check if account is trying to link to different wallet
        if input.wallet_address != existing.wallet_address {
            return Err(VerificationError::WalletMismatch);
        }
        
        // Update verification timestamp
        return Ok(VerificationResult::Updated {
            account_hash: existing.account_hash,
            last_verified: current_timestamp(),
        });
    }
    
    // New account verification
    create_new_verification(input, account_data)
}
```

## Attack Prevention

### 1. **Token Theft Protection**

Even if an OAuth token is stolen:
- ✅ **Attacker cannot change existing mappings** (account ID verification)
- ✅ **Attacker cannot link to different wallet** (consistency checks)
- ✅ **Original user can re-verify** with new token
- ✅ **Suspicious activity is logged** for monitoring

### 2. **Account Takeover Protection**

If a social account is compromised:
- ✅ **Existing wallet mapping remains** (until explicitly changed)
- ✅ **Re-verification requires same account ID** (prevents takeover)
- ✅ **Account changes are monitored** (username, email changes)
- ✅ **Emergency unlinking available** (for legitimate users)

### 3. **Token Replay Protection**

- ✅ **Tokens are used once** in ZK proof generation
- ✅ **Proof includes timestamp** (prevents old proof reuse)
- ✅ **Nonce system** prevents replay attacks
- ✅ **Token validation** checks expiration

## Implementation Improvements

### 1. **Enhanced Guest Program**

```rust
#[derive(Debug, Serialize, Deserialize)]
pub struct EnhancedVerificationInput {
    pub platform: SocialPlatform,
    pub oauth_token: String,
    pub wallet_address: String,
    pub timestamp: u64,
    pub nonce: u64, // Prevent replay attacks
    pub expected_account_id: Option<String>, // For re-verification
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EnhancedVerificationOutput {
    pub social_account_hash: [u8; 32],
    pub wallet_address: String,
    pub platform: SocialPlatform,
    pub account_id: String, // Stable identifier
    pub account_age: u64,
    pub follower_count: u64,
    pub timestamp: u64,
    pub nonce: u64,
    pub verification_type: VerificationType, // New vs Re-verification
    pub account_consistency_score: u8, // 0-100 consistency rating
    pub verification_success: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum VerificationType {
    NewAccount,
    ReVerification,
    AccountUpdate,
}
```

### 2. **Smart Contract Enhancements**

```solidity
struct SocialAccountMapping {
    address walletAddress;
    SocialPlatform platform;
    string accountId; // Store stable account ID
    uint256 linkedAt;
    uint256 lastVerified;
    uint256 verificationCount; // Track re-verifications
    bool isActive;
}

function reverifyAccount(
    bytes32 socialAccountHash,
    VerificationProof calldata proof
) external {
    SocialAccountMapping storage mapping = socialAccounts[socialAccountHash];
    require(mapping.isActive, "Account not active");
    require(mapping.walletAddress == msg.sender, "Not account owner");
    
    // Verify proof is for the same account ID
    require(
        keccak256(abi.encodePacked(mapping.accountId)) == 
        keccak256(abi.encodePacked(proof.accountId)),
        "Account ID mismatch"
    );
    
    // Update verification timestamp
    mapping.lastVerified = block.timestamp;
    mapping.verificationCount++;
    
    emit AccountReverified(socialAccountHash, msg.sender, block.timestamp);
}
```

## Best Practices

### 1. **For Users**
- ✅ **Re-verify periodically** (every 30 days recommended)
- ✅ **Use fresh tokens** for verification
- ✅ **Monitor account activity** for unauthorized changes
- ✅ **Keep backup verification methods** (multiple platforms)

### 2. **For Developers**
- ✅ **Validate token freshness** (< 1 hour old recommended)
- ✅ **Implement rate limiting** on verification attempts
- ✅ **Log all verification events** for monitoring
- ✅ **Provide clear error messages** for token issues

### 3. **For System Operators**
- ✅ **Monitor verification patterns** for anomalies
- ✅ **Set up alerts** for suspicious activity
- ✅ **Regular security audits** of verification logic
- ✅ **Emergency response procedures** for compromised accounts

## Conclusion

Our RISC Zero social verification system is designed to handle OAuth token changes gracefully while maintaining security:

1. **Stable Identifiers**: We use permanent account IDs, not temporary tokens
2. **Consistent Hashing**: Same account always generates same hash
3. **Re-verification Support**: Users can update with new tokens
4. **Attack Prevention**: Multiple layers of security checks
5. **Monitoring**: Comprehensive logging and alerting

This approach ensures that even as OAuth tokens change over time, the user account to wallet address mapping remains secure and consistent.
