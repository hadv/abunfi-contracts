// RISC Zero Host Program for Social Account Verification
// This program runs on the host and coordinates with the guest program

use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};
use serde::{Deserialize, Serialize};
use std::env;
use anyhow::Result;

// Include the guest binary
const GUEST_BINARY: &[u8] = include_bytes!("../../guest/target/riscv32im-risc0-zkvm-elf/release/social-verifier-guest");

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
}

#[derive(Debug, Serialize, Deserialize)]
pub struct VerificationOutput {
    pub social_account_hash: [u8; 32],
    pub wallet_address: String,
    pub platform: SocialPlatform,
    pub account_age: u64,
    pub follower_count: u64,
    pub timestamp: u64,
    pub social_account_id: String,
    pub verification_success: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ProofResult {
    pub verification_output: VerificationOutput,
    pub receipt: Vec<u8>, // Serialized receipt
    pub proof_hash: [u8; 32],
}

pub struct SocialVerificationService {
    prover: risc0_zkvm::Prover,
}

impl SocialVerificationService {
    pub fn new() -> Self {
        Self {
            prover: default_prover(),
        }
    }

    /// Verify a social account and generate a ZK proof
    pub async fn verify_social_account(
        &self,
        platform: SocialPlatform,
        oauth_token: String,
        wallet_address: String,
    ) -> Result<ProofResult> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs();

        let input = VerificationInput {
            platform,
            oauth_token,
            wallet_address,
            timestamp,
        };

        // Create the executor environment
        let env = ExecutorEnv::builder()
            .write(&input)?
            .build()?;

        // Execute the guest program and generate proof
        let receipt = self.prover.prove(env, GUEST_BINARY)?;

        // Extract the verification output from the receipt
        let verification_output: VerificationOutput = receipt.journal.decode()?;

        // Generate proof hash
        let proof_hash = self.calculate_proof_hash(&receipt);

        Ok(ProofResult {
            verification_output,
            receipt: bincode::serialize(&receipt)?,
            proof_hash,
        })
    }

    /// Verify an existing proof
    pub fn verify_proof(&self, receipt_bytes: &[u8]) -> Result<bool> {
        let receipt: Receipt = bincode::deserialize(receipt_bytes)?;
        
        // Verify the receipt
        receipt.verify(GUEST_BINARY)?;
        
        Ok(true)
    }

    /// Calculate a hash of the proof for on-chain storage
    fn calculate_proof_hash(&self, receipt: &Receipt) -> [u8; 32] {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(&receipt.journal.bytes);
        hasher.finalize().into()
    }
}

/// Web service endpoints for social verification
pub mod web_service {
    use super::*;
    use serde_json;
    use std::sync::Arc;

    #[derive(Debug, Serialize, Deserialize)]
    pub struct VerificationRequest {
        pub platform: String,
        pub oauth_token: String,
        pub wallet_address: String,
    }

    #[derive(Debug, Serialize, Deserialize)]
    pub struct VerificationResponse {
        pub success: bool,
        pub social_account_hash: Option<String>,
        pub account_age: Option<u64>,
        pub follower_count: Option<u64>,
        pub proof_hash: Option<String>,
        pub receipt: Option<String>, // Base64 encoded
        pub error: Option<String>,
    }

    pub struct VerificationServer {
        service: Arc<SocialVerificationService>,
    }

    impl VerificationServer {
        pub fn new() -> Self {
            Self {
                service: Arc::new(SocialVerificationService::new()),
            }
        }

        pub async fn handle_verification_request(
            &self,
            request: VerificationRequest,
        ) -> VerificationResponse {
            let platform = match request.platform.to_lowercase().as_str() {
                "twitter" => SocialPlatform::Twitter,
                "discord" => SocialPlatform::Discord,
                "github" => SocialPlatform::Github,
                "telegram" => SocialPlatform::Telegram,
                "linkedin" => SocialPlatform::LinkedIn,
                _ => {
                    return VerificationResponse {
                        success: false,
                        social_account_hash: None,
                        account_age: None,
                        follower_count: None,
                        proof_hash: None,
                        receipt: None,
                        error: Some("Unsupported platform".to_string()),
                    };
                }
            };

            match self.service.verify_social_account(
                platform,
                request.oauth_token,
                request.wallet_address,
            ).await {
                Ok(result) => {
                    if result.verification_output.verification_success {
                        VerificationResponse {
                            success: true,
                            social_account_hash: Some(hex::encode(result.verification_output.social_account_hash)),
                            account_age: Some(result.verification_output.account_age),
                            follower_count: Some(result.verification_output.follower_count),
                            proof_hash: Some(hex::encode(result.proof_hash)),
                            receipt: Some(base64::encode(result.receipt)),
                            error: None,
                        }
                    } else {
                        VerificationResponse {
                            success: false,
                            social_account_hash: None,
                            account_age: None,
                            follower_count: None,
                            proof_hash: None,
                            receipt: None,
                            error: Some("Social account verification failed".to_string()),
                        }
                    }
                }
                Err(e) => VerificationResponse {
                    success: false,
                    social_account_hash: None,
                    account_age: None,
                    follower_count: None,
                    proof_hash: None,
                    receipt: None,
                    error: Some(format!("Verification error: {}", e)),
                },
            }
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Parse command line arguments
    let args: Vec<String> = env::args().collect();
    
    if args.len() < 4 {
        println!("Usage: {} <platform> <oauth_token> <wallet_address>", args[0]);
        println!("Platforms: twitter, discord, github, telegram, linkedin");
        return Ok(());
    }

    let platform_str = &args[1];
    let oauth_token = &args[2];
    let wallet_address = &args[3];

    let platform = match platform_str.to_lowercase().as_str() {
        "twitter" => SocialPlatform::Twitter,
        "discord" => SocialPlatform::Discord,
        "github" => SocialPlatform::Github,
        "telegram" => SocialPlatform::Telegram,
        "linkedin" => SocialPlatform::LinkedIn,
        _ => {
            println!("Unsupported platform: {}", platform_str);
            return Ok(());
        }
    };

    println!("Starting social account verification...");
    println!("Platform: {:?}", platform);
    println!("Wallet Address: {}", wallet_address);

    let service = SocialVerificationService::new();
    
    match service.verify_social_account(
        platform,
        oauth_token.to_string(),
        wallet_address.to_string(),
    ).await {
        Ok(result) => {
            println!("\n=== Verification Result ===");
            println!("Success: {}", result.verification_output.verification_success);
            println!("Social Account Hash: {}", hex::encode(result.verification_output.social_account_hash));
            println!("Account Age: {} seconds", result.verification_output.account_age);
            println!("Follower Count: {}", result.verification_output.follower_count);
            println!("Proof Hash: {}", hex::encode(result.proof_hash));
            println!("Receipt Size: {} bytes", result.receipt.len());
            
            // Verify the proof
            match service.verify_proof(&result.receipt) {
                Ok(valid) => println!("Proof Verification: {}", if valid { "VALID" } else { "INVALID" }),
                Err(e) => println!("Proof Verification Error: {}", e),
            }
        }
        Err(e) => {
            println!("Verification failed: {}", e);
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_twitter_verification() {
        let service = SocialVerificationService::new();
        
        let result = service.verify_social_account(
            SocialPlatform::Twitter,
            "mock_twitter_token_12345".to_string(),
            "0x1234567890123456789012345678901234567890".to_string(),
        ).await;

        assert!(result.is_ok());
        let proof_result = result.unwrap();
        assert!(proof_result.verification_output.verification_success);
        assert!(proof_result.verification_output.follower_count > 0);
    }

    #[tokio::test]
    async fn test_invalid_token() {
        let service = SocialVerificationService::new();
        
        let result = service.verify_social_account(
            SocialPlatform::Twitter,
            "short".to_string(), // Invalid token
            "0x1234567890123456789012345678901234567890".to_string(),
        ).await;

        assert!(result.is_ok());
        let proof_result = result.unwrap();
        assert!(!proof_result.verification_output.verification_success);
    }

    #[test]
    fn test_proof_verification() {
        // This would test the proof verification functionality
        // For now, it's a placeholder
        assert!(true);
    }
}
