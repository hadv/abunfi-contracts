// Test cases for OAuth token management and account consistency
use risc0_social_verifier::*;
use serde_json;
use std::collections::HashMap;

#[cfg(test)]
mod token_management_tests {
    use super::*;

    // Mock data for testing
    struct MockTwitterUser {
        id: String,
        username: String,
        created_at: String,
        followers_count: u64,
    }

    struct TestScenario {
        name: String,
        user_data: MockTwitterUser,
        tokens: Vec<String>, // Different tokens for same user
        wallet_address: String,
        expected_hash: String,
    }

    #[test]
    fn test_token_expiration_and_refresh() {
        let scenario = TestScenario {
            name: "Token Expiration and Refresh".to_string(),
            user_data: MockTwitterUser {
                id: "123456789".to_string(),
                username: "alice_crypto".to_string(),
                created_at: "2020-01-15T10:30:00.000Z".to_string(),
                followers_count: 150,
            },
            tokens: vec![
                "Bearer aaaa1111bbbb2222cccc3333".to_string(), // Original token
                "Bearer dddd4444eeee5555ffff6666".to_string(), // Refreshed token
                "Bearer gggg7777hhhh8888iiii9999".to_string(), // Re-authorized token
            ],
            wallet_address: "0x742d35Cc6634C0532925a3b8D4C2C4e0C8A8e8e8".to_string(),
            expected_hash: "0x1a2b3c4d5e6f7890abcdef1234567890abcdef1234567890abcdef1234567890".to_string(),
        };

        println!("🧪 Testing: {}", scenario.name);

        // Test 1: Initial verification with first token
        let input1 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: scenario.tokens[0].clone(),
            wallet_address: scenario.wallet_address.clone(),
            timestamp: 1640995200, // 2022-01-01
            nonce: 1,
            expected_account_id: None, // New account
        };

        let result1 = simulate_verification(&input1, &scenario.user_data);
        assert!(result1.verification_success);
        assert_eq!(result1.social_account_id, scenario.user_data.id);
        assert_eq!(result1.verification_type, VerificationType::NewAccount);
        assert_eq!(result1.account_consistency_score, 100);

        println!("✅ Initial verification successful");
        println!("   Account ID: {}", result1.social_account_id);
        println!("   Hash: {:?}", hex::encode(result1.social_account_hash));

        // Test 2: Re-verification with refreshed token (30 days later)
        let input2 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: scenario.tokens[1].clone(),
            wallet_address: scenario.wallet_address.clone(),
            timestamp: 1643587200, // 2022-01-31
            nonce: 2,
            expected_account_id: Some(scenario.user_data.id.clone()), // Re-verification
        };

        let result2 = simulate_verification(&input2, &scenario.user_data);
        assert!(result2.verification_success);
        assert_eq!(result2.social_account_id, scenario.user_data.id);
        assert_eq!(result2.verification_type, VerificationType::ReVerification);
        assert_eq!(result2.account_consistency_score, 95);

        // Most importantly: Same hash generated!
        assert_eq!(result1.social_account_hash, result2.social_account_hash);

        println!("✅ Re-verification with new token successful");
        println!("   Same Account ID: {}", result2.social_account_id);
        println!("   Same Hash: {:?}", hex::encode(result2.social_account_hash));

        // Test 3: Third verification with re-authorized token (60 days later)
        let input3 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: scenario.tokens[2].clone(),
            wallet_address: scenario.wallet_address.clone(),
            timestamp: 1646179200, // 2022-03-02
            nonce: 3,
            expected_account_id: Some(scenario.user_data.id.clone()),
        };

        let result3 = simulate_verification(&input3, &scenario.user_data);
        assert!(result3.verification_success);
        assert_eq!(result3.social_account_id, scenario.user_data.id);
        assert_eq!(result3.verification_type, VerificationType::ReVerification);

        // All three verifications produce the same hash!
        assert_eq!(result1.social_account_hash, result3.social_account_hash);
        assert_eq!(result2.social_account_hash, result3.social_account_hash);

        println!("✅ Third verification with re-authorized token successful");
        println!("   Consistent Hash across all verifications: {:?}", hex::encode(result3.social_account_hash));
    }

    #[test]
    fn test_username_change_with_same_account() {
        println!("🧪 Testing: Username Change with Same Account ID");

        let original_user = MockTwitterUser {
            id: "987654321".to_string(),
            username: "bob_defi".to_string(),
            created_at: "2019-06-01T15:45:00.000Z".to_string(),
            followers_count: 500,
        };

        let updated_user = MockTwitterUser {
            id: "987654321".to_string(), // Same ID
            username: "bob_web3".to_string(), // Changed username
            created_at: "2019-06-01T15:45:00.000Z".to_string(), // Same creation date
            followers_count: 520, // Slightly more followers
        };

        let wallet_address = "0x1234567890123456789012345678901234567890".to_string();

        // Initial verification
        let input1 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: "Bearer token1111".to_string(),
            wallet_address: wallet_address.clone(),
            timestamp: 1640995200,
            nonce: 1,
            expected_account_id: None,
        };

        let result1 = simulate_verification(&input1, &original_user);
        assert!(result1.verification_success);

        // Re-verification after username change
        let input2 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: "Bearer token2222".to_string(),
            wallet_address: wallet_address.clone(),
            timestamp: 1643587200,
            nonce: 2,
            expected_account_id: Some(original_user.id.clone()),
        };

        let result2 = simulate_verification(&input2, &updated_user);
        assert!(result2.verification_success);
        assert_eq!(result2.verification_type, VerificationType::ReVerification);

        // Same account ID = same hash, despite username change
        assert_eq!(result1.social_account_hash, result2.social_account_hash);
        assert_eq!(result1.social_account_id, result2.social_account_id);

        println!("✅ Username change handled correctly");
        println!("   Account ID unchanged: {}", result2.social_account_id);
        println!("   Hash unchanged: {:?}", hex::encode(result2.social_account_hash));
        println!("   Username changed: {} → {}", original_user.username, updated_user.username);
    }

    #[test]
    fn test_invalid_token_scenarios() {
        println!("🧪 Testing: Invalid Token Scenarios");

        let user_data = MockTwitterUser {
            id: "555666777".to_string(),
            username: "charlie_nft".to_string(),
            created_at: "2021-03-10T12:00:00.000Z".to_string(),
            followers_count: 75,
        };

        let wallet_address = "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd".to_string();

        // Test 1: Empty token
        let input1 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: "".to_string(),
            wallet_address: wallet_address.clone(),
            timestamp: 1640995200,
            nonce: 1,
            expected_account_id: None,
        };

        let result1 = simulate_verification(&input1, &user_data);
        assert!(!result1.verification_success);
        assert_eq!(result1.account_consistency_score, 0);

        // Test 2: Malformed token
        let input2 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: "invalid".to_string(),
            wallet_address: wallet_address.clone(),
            timestamp: 1640995200,
            nonce: 2,
            expected_account_id: None,
        };

        let result2 = simulate_verification(&input2, &user_data);
        assert!(!result2.verification_success);

        // Test 3: Token for wrong platform
        let input3 = VerificationInput {
            platform: SocialPlatform::Github,
            oauth_token: "Bearer twitter_token".to_string(), // Twitter token for GitHub
            wallet_address: wallet_address.clone(),
            timestamp: 1640995200,
            nonce: 3,
            expected_account_id: None,
        };

        let result3 = simulate_verification(&input3, &user_data);
        assert!(!result3.verification_success);

        println!("✅ Invalid token scenarios handled correctly");
    }

    #[test]
    fn test_account_takeover_attempt() {
        println!("🧪 Testing: Account Takeover Attempt");

        let legitimate_user = MockTwitterUser {
            id: "111222333".to_string(),
            username: "alice_original".to_string(),
            created_at: "2020-05-15T09:30:00.000Z".to_string(),
            followers_count: 200,
        };

        let attacker_user = MockTwitterUser {
            id: "444555666".to_string(), // Different account ID
            username: "alice_original".to_string(), // Same username (somehow obtained)
            created_at: "2023-01-01T00:00:00.000Z".to_string(), // Different creation date
            followers_count: 5, // Suspicious low followers
        };

        let wallet_address = "0x1111222233334444555566667777888899990000".to_string();

        // Legitimate user's initial verification
        let input1 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: "Bearer legitimate_token".to_string(),
            wallet_address: wallet_address.clone(),
            timestamp: 1640995200,
            nonce: 1,
            expected_account_id: None,
        };

        let result1 = simulate_verification(&input1, &legitimate_user);
        assert!(result1.verification_success);

        // Attacker attempts to re-verify with different account ID
        let input2 = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: "Bearer attacker_token".to_string(),
            wallet_address: wallet_address.clone(),
            timestamp: 1643587200,
            nonce: 2,
            expected_account_id: Some(legitimate_user.id.clone()), // Claims to be re-verification
        };

        let result2 = simulate_verification(&input2, &attacker_user);
        
        // This should be detected as AccountUpdate (suspicious)
        assert_eq!(result2.verification_type, VerificationType::AccountUpdate);
        assert!(result2.account_consistency_score < 50); // Low consistency score
        
        // Different account ID = different hash
        assert_ne!(result1.social_account_hash, result2.social_account_hash);

        println!("✅ Account takeover attempt detected");
        println!("   Original Account ID: {}", result1.social_account_id);
        println!("   Attacker Account ID: {}", result2.social_account_id);
        println!("   Consistency Score: {}", result2.account_consistency_score);
    }

    #[test]
    fn test_multiple_platform_verification() {
        println!("🧪 Testing: Multiple Platform Verification");

        let wallet_address = "0xmultiplat1234567890123456789012345678".to_string();

        // Twitter verification
        let twitter_user = MockTwitterUser {
            id: "twitter123".to_string(),
            username: "user_multi".to_string(),
            created_at: "2020-01-01T00:00:00.000Z".to_string(),
            followers_count: 100,
        };

        let twitter_input = VerificationInput {
            platform: SocialPlatform::Twitter,
            oauth_token: "Bearer twitter_token".to_string(),
            wallet_address: wallet_address.clone(),
            timestamp: 1640995200,
            nonce: 1,
            expected_account_id: None,
        };

        let twitter_result = simulate_verification(&twitter_input, &twitter_user);
        assert!(twitter_result.verification_success);

        // GitHub verification (same user, different platform)
        let github_user = MockGithubUser {
            id: 456789,
            login: "user_multi".to_string(),
            created_at: "2020-01-01T00:00:00Z".to_string(),
            followers: 50,
        };

        let github_input = VerificationInput {
            platform: SocialPlatform::Github,
            oauth_token: "ghp_github_token_1234567890".to_string(),
            wallet_address: wallet_address.clone(),
            timestamp: 1640995200,
            nonce: 2,
            expected_account_id: None,
        };

        let github_result = simulate_verification_github(&github_input, &github_user);
        assert!(github_result.verification_success);

        // Different platforms = different hashes (as expected)
        assert_ne!(twitter_result.social_account_hash, github_result.social_account_hash);

        // But same wallet can be linked to multiple platforms
        assert_eq!(twitter_result.wallet_address, github_result.wallet_address);

        println!("✅ Multiple platform verification successful");
        println!("   Twitter Hash: {:?}", hex::encode(twitter_result.social_account_hash));
        println!("   GitHub Hash: {:?}", hex::encode(github_result.social_account_hash));
    }

    // Helper functions for testing

    fn simulate_verification(input: &VerificationInput, user_data: &MockTwitterUser) -> VerificationOutput {
        // Simulate the verification process
        if !validate_oauth_token(&input.oauth_token, &input.platform) {
            return create_failed_verification(input, "Invalid token");
        }

        let verification_type = determine_verification_type(input, &user_data.id);
        let consistency_score = calculate_consistency_score(&verification_type, &user_data.id);
        let social_account_hash = generate_social_account_hash(&input.platform, &user_data.id);
        let account_age = calculate_account_age(&user_data.created_at);

        VerificationOutput {
            social_account_hash,
            wallet_address: input.wallet_address.clone(),
            platform: input.platform.clone(),
            account_age,
            follower_count: user_data.followers_count,
            timestamp: input.timestamp,
            nonce: input.nonce,
            social_account_id: user_data.id.clone(),
            verification_type,
            account_consistency_score: consistency_score,
            verification_success: true,
        }
    }

    struct MockGithubUser {
        id: u64,
        login: String,
        created_at: String,
        followers: u64,
    }

    fn simulate_verification_github(input: &VerificationInput, user_data: &MockGithubUser) -> VerificationOutput {
        if !validate_oauth_token(&input.oauth_token, &input.platform) {
            return create_failed_verification(input, "Invalid token");
        }

        let account_id = user_data.id.to_string();
        let verification_type = determine_verification_type(input, &account_id);
        let consistency_score = calculate_consistency_score(&verification_type, &account_id);
        let social_account_hash = generate_social_account_hash(&input.platform, &account_id);
        let account_age = calculate_account_age(&user_data.created_at);

        VerificationOutput {
            social_account_hash,
            wallet_address: input.wallet_address.clone(),
            platform: input.platform.clone(),
            account_age,
            follower_count: user_data.followers,
            timestamp: input.timestamp,
            nonce: input.nonce,
            social_account_id: account_id,
            verification_type,
            account_consistency_score: consistency_score,
            verification_success: true,
        }
    }
}
