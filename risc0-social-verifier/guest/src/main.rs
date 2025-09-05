// RISC Zero Guest Program for Social Account Verification
// This program runs inside the zkVM and verifies OAuth tokens

use risc0_zkvm::guest::env;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;

#[derive(Debug, Serialize, Deserialize)]
pub enum SocialPlatform {
    Twitter,
    Discord,
    Github,
    Telegram,
    LinkedIn,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct VerificationInput {
    pub platform: SocialPlatform,
    pub oauth_token: String,
    pub wallet_address: String,
    pub timestamp: u64,
    pub nonce: u64, // Prevent replay attacks
    pub expected_account_id: Option<String>, // For re-verification
}

#[derive(Debug, Serialize, Deserialize)]
pub struct VerificationOutput {
    pub social_account_hash: [u8; 32],
    pub wallet_address: String,
    pub platform: SocialPlatform,
    pub account_age: u64,
    pub follower_count: u64,
    pub timestamp: u64,
    pub nonce: u64,
    pub social_account_id: String, // Stable account ID
    pub verification_type: VerificationType,
    pub account_consistency_score: u8, // 0-100 consistency rating
    pub verification_success: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub enum VerificationType {
    NewAccount,
    ReVerification,
    AccountUpdate,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TwitterUserData {
    pub id: String,
    pub username: String,
    pub name: String,
    pub created_at: String,
    pub public_metrics: TwitterMetrics,
    pub verified: Option<bool>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TwitterMetrics {
    pub followers_count: u64,
    pub following_count: u64,
    pub tweet_count: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DiscordUserData {
    pub id: String,
    pub username: String,
    pub discriminator: String,
    pub verified: Option<bool>,
    pub email: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GithubUserData {
    pub id: u64,
    pub login: String,
    pub name: Option<String>,
    pub created_at: String,
    pub followers: u64,
    pub following: u64,
    pub public_repos: u64,
}

fn main() {
    // Read input from the host
    let input: VerificationInput = env::read();

    // Validate OAuth token first
    if !validate_oauth_token(&input.oauth_token, &input.platform) {
        let failed_result = create_failed_verification(&input, "Invalid OAuth token");
        env::commit(&failed_result);
        return;
    }

    // Verify the OAuth token and extract user data
    let verification_result = match input.platform {
        SocialPlatform::Twitter => verify_twitter_account(&input),
        SocialPlatform::Discord => verify_discord_account(&input),
        SocialPlatform::Github => verify_github_account(&input),
        SocialPlatform::Telegram => verify_telegram_account(&input),
        SocialPlatform::LinkedIn => verify_linkedin_account(&input),
    };

    // Commit the verification result to the journal
    env::commit(&verification_result);
}

fn verify_twitter_account(input: &VerificationInput) -> VerificationOutput {
    // In a real implementation, this would make HTTP requests to Twitter API
    // For demonstration, we'll simulate the verification process

    // Simulate API call to Twitter
    let user_data = simulate_twitter_api_call(&input.oauth_token);

    match user_data {
        Ok(data) => {
            // Calculate account age
            let account_age = calculate_account_age(&data.created_at);

            // Determine verification type
            let verification_type = determine_verification_type(input, &data.id);

            // Calculate consistency score
            let consistency_score = calculate_consistency_score(&verification_type, &data.id);

            // Generate social account hash (always same for same account ID)
            let social_account_hash = generate_social_account_hash(
                &SocialPlatform::Twitter,
                &data.id,
            );

            VerificationOutput {
                social_account_hash,
                wallet_address: input.wallet_address.clone(),
                platform: SocialPlatform::Twitter,
                account_age,
                follower_count: data.public_metrics.followers_count,
                timestamp: input.timestamp,
                nonce: input.nonce,
                social_account_id: data.id,
                verification_type,
                account_consistency_score: consistency_score,
                verification_success: true,
            }
        }
        Err(_) => {
            create_failed_verification(input, "Twitter API call failed")
        }
    }
}

fn verify_discord_account(input: &VerificationInput) -> VerificationOutput {
    let user_data = simulate_discord_api_call(&input.oauth_token);
    
    match user_data {
        Ok(data) => {
            let social_account_hash = generate_social_account_hash(
                &SocialPlatform::Discord,
                &data.id,
            );
            
            VerificationOutput {
                social_account_hash,
                wallet_address: input.wallet_address.clone(),
                platform: SocialPlatform::Discord,
                account_age: 0, // Discord doesn't provide creation date in basic API
                follower_count: 0, // Discord doesn't have followers concept
                timestamp: input.timestamp,
                social_account_id: data.id,
                verification_success: true,
            }
        }
        Err(_) => {
            VerificationOutput {
                social_account_hash: [0u8; 32],
                wallet_address: input.wallet_address.clone(),
                platform: SocialPlatform::Discord,
                account_age: 0,
                follower_count: 0,
                timestamp: input.timestamp,
                social_account_id: String::new(),
                verification_success: false,
            }
        }
    }
}

fn verify_github_account(input: &VerificationInput) -> VerificationOutput {
    let user_data = simulate_github_api_call(&input.oauth_token);
    
    match user_data {
        Ok(data) => {
            let account_age = calculate_account_age(&data.created_at);
            let social_account_hash = generate_social_account_hash(
                &SocialPlatform::Github,
                &data.id.to_string(),
            );
            
            VerificationOutput {
                social_account_hash,
                wallet_address: input.wallet_address.clone(),
                platform: SocialPlatform::Github,
                account_age,
                follower_count: data.followers,
                timestamp: input.timestamp,
                social_account_id: data.id.to_string(),
                verification_success: true,
            }
        }
        Err(_) => {
            VerificationOutput {
                social_account_hash: [0u8; 32],
                wallet_address: input.wallet_address.clone(),
                platform: SocialPlatform::Github,
                account_age: 0,
                follower_count: 0,
                timestamp: input.timestamp,
                social_account_id: String::new(),
                verification_success: false,
            }
        }
    }
}

fn verify_telegram_account(_input: &VerificationInput) -> VerificationOutput {
    // Telegram verification would be more complex as it requires bot integration
    // For now, return a placeholder
    VerificationOutput {
        social_account_hash: [0u8; 32],
        wallet_address: _input.wallet_address.clone(),
        platform: SocialPlatform::Telegram,
        account_age: 0,
        follower_count: 0,
        timestamp: _input.timestamp,
        social_account_id: String::new(),
        verification_success: false,
    }
}

fn verify_linkedin_account(_input: &VerificationInput) -> VerificationOutput {
    // LinkedIn verification placeholder
    VerificationOutput {
        social_account_hash: [0u8; 32],
        wallet_address: _input.wallet_address.clone(),
        platform: SocialPlatform::LinkedIn,
        account_age: 0,
        follower_count: 0,
        timestamp: _input.timestamp,
        social_account_id: String::new(),
        verification_success: false,
    }
}

// Simulation functions (in real implementation, these would make actual HTTP requests)

fn simulate_twitter_api_call(oauth_token: &str) -> Result<TwitterUserData, &'static str> {
    // Simulate token validation
    if oauth_token.len() < 10 {
        return Err("Invalid token");
    }
    
    // Return mock data
    Ok(TwitterUserData {
        id: "123456789".to_string(),
        username: "testuser".to_string(),
        name: "Test User".to_string(),
        created_at: "2020-01-01T00:00:00.000Z".to_string(),
        public_metrics: TwitterMetrics {
            followers_count: 150,
            following_count: 100,
            tweet_count: 500,
        },
        verified: Some(false),
    })
}

fn simulate_discord_api_call(oauth_token: &str) -> Result<DiscordUserData, &'static str> {
    if oauth_token.len() < 10 {
        return Err("Invalid token");
    }
    
    Ok(DiscordUserData {
        id: "987654321".to_string(),
        username: "testuser".to_string(),
        discriminator: "1234".to_string(),
        verified: Some(true),
        email: Some("test@example.com".to_string()),
    })
}

fn simulate_github_api_call(oauth_token: &str) -> Result<GithubUserData, &'static str> {
    if oauth_token.len() < 10 {
        return Err("Invalid token");
    }
    
    Ok(GithubUserData {
        id: 12345,
        login: "testuser".to_string(),
        name: Some("Test User".to_string()),
        created_at: "2019-06-01T00:00:00Z".to_string(),
        followers: 25,
        following: 50,
        public_repos: 10,
    })
}

// Utility functions

fn generate_social_account_hash(platform: &SocialPlatform, account_id: &str) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(format!("{:?}", platform).as_bytes());
    hasher.update(account_id.as_bytes());
    hasher.finalize().into()
}

fn calculate_account_age(created_at: &str) -> u64 {
    // Parse the creation date and calculate age in seconds
    // This is a simplified implementation
    match chrono::DateTime::parse_from_rfc3339(created_at) {
        Ok(created) => {
            let now = chrono::Utc::now();
            let duration = now.signed_duration_since(created.with_timezone(&chrono::Utc));
            duration.num_seconds() as u64
        }
        Err(_) => 0,
    }
}

fn validate_oauth_token(token: &str, platform: &SocialPlatform) -> bool {
    // Basic token validation
    if token.len() < 10 {
        return false;
    }

    // Platform-specific token format validation
    match platform {
        SocialPlatform::Twitter => token.starts_with("Bearer ") || token.len() > 20,
        SocialPlatform::Discord => token.len() > 15,
        SocialPlatform::Github => token.starts_with("ghp_") || token.starts_with("gho_"),
        _ => token.len() > 10,
    }
}

fn determine_verification_type(
    input: &VerificationInput,
    account_id: &str,
) -> VerificationType {
    match &input.expected_account_id {
        Some(expected_id) => {
            if expected_id == account_id {
                VerificationType::ReVerification
            } else {
                VerificationType::AccountUpdate
            }
        }
        None => VerificationType::NewAccount,
    }
}

fn calculate_consistency_score(
    verification_type: &VerificationType,
    account_data: &str, // In real implementation, this would be structured data
) -> u8 {
    match verification_type {
        VerificationType::NewAccount => 100, // New accounts get full score
        VerificationType::ReVerification => {
            // Check consistency with previous verification
            // This is simplified - in real implementation would compare with stored data
            if account_data.len() > 0 {
                95 // High score for successful re-verification
            } else {
                50 // Lower score if data seems inconsistent
            }
        }
        VerificationType::AccountUpdate => {
            // Account ID changed - this should be rare and flagged
            25 // Low score for account updates
        }
    }
}

fn create_failed_verification(input: &VerificationInput, reason: &str) -> VerificationOutput {
    VerificationOutput {
        social_account_hash: [0u8; 32],
        wallet_address: input.wallet_address.clone(),
        platform: input.platform.clone(),
        account_age: 0,
        follower_count: 0,
        timestamp: input.timestamp,
        nonce: input.nonce,
        social_account_id: String::new(),
        verification_type: VerificationType::NewAccount,
        account_consistency_score: 0,
        verification_success: false,
    }
}
