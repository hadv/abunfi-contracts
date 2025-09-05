#!/usr/bin/env node

/**
 * Token Management Demo
 * Demonstrates how OAuth token changes are handled in the social verification system
 *
 * Security Note: This is a demonstration script for testing purposes only.
 * It uses Node.js built-in modules and does not execute dynamic code.
 */

// Import built-in Node.js modules (safe, no dynamic code execution)
const crypto = require('crypto');

// Mock data for demonstration
const DEMO_SCENARIOS = {
    tokenExpiration: {
        name: "Token Expiration and Refresh",
        user: {
            id: "123456789",
            username: "alice_crypto",
            created_at: "2020-01-15T10:30:00.000Z",
            followers_count: 150
        },
        tokens: [
            "Bearer aaaa1111bbbb2222cccc3333", // Original token
            "Bearer dddd4444eeee5555ffff6666", // Refreshed token  
            "Bearer gggg7777hhhh8888iiii9999"  // Re-authorized token
        ],
        wallet: "0x742d35Cc6634C0532925a3b8D4C2C4e0C8A8e8e8"
    },
    
    usernameChange: {
        name: "Username Change with Same Account",
        user: {
            id: "987654321", // Same ID throughout
            usernames: ["bob_defi", "bob_web3", "bob_crypto"], // Different usernames
            created_at: "2019-06-01T15:45:00.000Z",
            followers_count: [500, 520, 550] // Growing followers
        },
        tokens: [
            "Bearer token1111",
            "Bearer token2222", 
            "Bearer token3333"
        ],
        wallet: "0x1234567890123456789012345678901234567890"
    },
    
    accountTakeover: {
        name: "Account Takeover Attempt",
        legitimateUser: {
            id: "111222333",
            username: "alice_original",
            created_at: "2020-05-15T09:30:00.000Z",
            followers_count: 200
        },
        attackerUser: {
            id: "444555666", // Different ID!
            username: "alice_original", // Same username (somehow obtained)
            created_at: "2023-01-01T00:00:00.000Z", // Different creation date
            followers_count: 5 // Suspicious low followers
        },
        wallet: "0x1111222233334444555566667777888899990000"
    }
};

class SocialVerificationDemo {
    constructor() {
        this.verificationHistory = new Map();
    }

    // Simulate the RISC Zero guest program logic
    generateSocialAccountHash(platform, accountId) {
        const data = `${platform}:${accountId}`;
        return crypto.createHash('sha256').update(data).digest('hex');
    }

    calculateAccountAge(createdAt) {
        const created = new Date(createdAt);
        const now = new Date();
        return Math.floor((now - created) / 1000); // Age in seconds
    }

    validateOAuthToken(token, platform) {
        if (token.length < 10) return false;
        
        switch (platform) {
            case 'TWITTER':
                return token.startsWith('Bearer ') || token.length > 20;
            case 'DISCORD':
                return token.length > 15;
            case 'GITHUB':
                return token.startsWith('ghp_') || token.startsWith('gho_');
            default:
                return token.length > 10;
        }
    }

    determineVerificationType(accountId, expectedAccountId) {
        if (!expectedAccountId) {
            return 'NEW_ACCOUNT';
        }
        
        if (expectedAccountId === accountId) {
            return 'RE_VERIFICATION';
        }
        
        return 'ACCOUNT_UPDATE'; // Suspicious!
    }

    calculateConsistencyScore(verificationType, accountData) {
        switch (verificationType) {
            case 'NEW_ACCOUNT':
                return 100;
            case 'RE_VERIFICATION':
                return 95;
            case 'ACCOUNT_UPDATE':
                return 25; // Low score for account changes
            default:
                return 0;
        }
    }

    simulateVerification(input) {
        console.log(`\n🔍 Verifying: ${input.platform} account`);
        console.log(`   Token: ${input.oauth_token.substring(0, 20)}...`);
        console.log(`   Wallet: ${input.wallet_address}`);
        console.log(`   Expected Account ID: ${input.expected_account_id || 'None (new account)'}`);

        // Validate token
        if (!this.validateOAuthToken(input.oauth_token, input.platform)) {
            console.log(`❌ Invalid OAuth token format`);
            return {
                verification_success: false,
                error: "Invalid OAuth token"
            };
        }

        // Extract account data (simulated)
        const accountData = this.extractAccountData(input.oauth_token, input.user_data);
        if (!accountData) {
            console.log(`❌ Failed to extract account data`);
            return {
                verification_success: false,
                error: "Failed to extract account data"
            };
        }

        // Generate hash based on stable account ID
        const socialAccountHash = this.generateSocialAccountHash(input.platform, accountData.id);
        
        // Determine verification type
        const verificationType = this.determineVerificationType(accountData.id, input.expected_account_id);
        
        // Calculate consistency score
        const consistencyScore = this.calculateConsistencyScore(verificationType, accountData);
        
        // Calculate account age
        const accountAge = this.calculateAccountAge(accountData.created_at);

        const result = {
            social_account_hash: socialAccountHash,
            wallet_address: input.wallet_address,
            platform: input.platform,
            account_id: accountData.id,
            account_age: accountAge,
            follower_count: accountData.followers_count,
            timestamp: input.timestamp,
            nonce: input.nonce,
            verification_type: verificationType,
            account_consistency_score: consistencyScore,
            verification_success: true
        };

        console.log(`✅ Verification successful`);
        console.log(`   Account ID: ${result.account_id}`);
        console.log(`   Hash: 0x${result.social_account_hash}`);
        console.log(`   Type: ${result.verification_type}`);
        console.log(`   Consistency Score: ${result.account_consistency_score}/100`);

        return result;
    }

    extractAccountData(token, userData) {
        // Simulate API call to extract account data
        // In real implementation, this would make HTTP requests
        return userData;
    }

    async runTokenExpirationDemo() {
        console.log(`\n🧪 DEMO: ${DEMO_SCENARIOS.tokenExpiration.name}`);
        console.log("=" * 60);

        const scenario = DEMO_SCENARIOS.tokenExpiration;
        const results = [];

        // Initial verification
        console.log(`\n📅 Day 1: Initial Verification`);
        const input1 = {
            platform: 'TWITTER',
            oauth_token: scenario.tokens[0],
            wallet_address: scenario.wallet,
            timestamp: Math.floor(Date.now() / 1000),
            nonce: 1,
            expected_account_id: null,
            user_data: scenario.user
        };

        const result1 = this.simulateVerification(input1);
        results.push(result1);

        // Token refresh (30 days later)
        console.log(`\n📅 Day 31: Token Expired, Using Refreshed Token`);
        const input2 = {
            platform: 'TWITTER',
            oauth_token: scenario.tokens[1], // Different token
            wallet_address: scenario.wallet,
            timestamp: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60),
            nonce: 2,
            expected_account_id: scenario.user.id, // Re-verification
            user_data: scenario.user
        };

        const result2 = this.simulateVerification(input2);
        results.push(result2);

        // Re-authorization (60 days later)
        console.log(`\n📅 Day 61: App Re-authorized, New Token`);
        const input3 = {
            platform: 'TWITTER',
            oauth_token: scenario.tokens[2], // Another different token
            wallet_address: scenario.wallet,
            timestamp: Math.floor(Date.now() / 1000) + (60 * 24 * 60 * 60),
            nonce: 3,
            expected_account_id: scenario.user.id, // Re-verification
            user_data: scenario.user
        };

        const result3 = this.simulateVerification(input3);
        results.push(result3);

        // Verify consistency
        console.log(`\n📊 RESULTS ANALYSIS:`);
        console.log(`   All verifications successful: ${results.every(r => r.verification_success)}`);
        console.log(`   Same account ID: ${results.every(r => r.account_id === scenario.user.id)}`);
        console.log(`   Same hash generated: ${results.every(r => r.social_account_hash === results[0].social_account_hash)}`);
        console.log(`   Hash value: 0x${results[0].social_account_hash}`);

        return results;
    }

    async runUsernameChangeDemo() {
        console.log(`\n🧪 DEMO: ${DEMO_SCENARIOS.usernameChange.name}`);
        console.log("=" * 60);

        const scenario = DEMO_SCENARIOS.usernameChange;
        const results = [];

        for (let i = 0; i < scenario.user.usernames.length; i++) {
            console.log(`\n📅 Verification ${i + 1}: Username "${scenario.user.usernames[i]}"`);
            
            const userData = {
                id: scenario.user.id, // Same ID always
                username: scenario.user.usernames[i], // Different username
                created_at: scenario.user.created_at, // Same creation date
                followers_count: scenario.user.followers_count[i] // Growing followers
            };

            const input = {
                platform: 'TWITTER',
                oauth_token: scenario.tokens[i],
                wallet_address: scenario.wallet,
                timestamp: Math.floor(Date.now() / 1000) + (i * 15 * 24 * 60 * 60), // 15 days apart
                nonce: i + 1,
                expected_account_id: i === 0 ? null : scenario.user.id, // First is new, rest are re-verification
                user_data: userData
            };

            const result = this.simulateVerification(input);
            results.push(result);
        }

        console.log(`\n📊 RESULTS ANALYSIS:`);
        console.log(`   All verifications successful: ${results.every(r => r.verification_success)}`);
        console.log(`   Same account ID maintained: ${results.every(r => r.account_id === scenario.user.id)}`);
        console.log(`   Same hash despite username changes: ${results.every(r => r.social_account_hash === results[0].social_account_hash)}`);
        console.log(`   Username evolution: ${scenario.user.usernames.join(' → ')}`);

        return results;
    }

    async runAccountTakeoverDemo() {
        console.log(`\n🧪 DEMO: ${DEMO_SCENARIOS.accountTakeover.name}`);
        console.log("=" * 60);

        const scenario = DEMO_SCENARIOS.accountTakeover;

        // Legitimate user's verification
        console.log(`\n👤 Legitimate User Verification`);
        const legitimateInput = {
            platform: 'TWITTER',
            oauth_token: "Bearer legitimate_token_12345",
            wallet_address: scenario.wallet,
            timestamp: Math.floor(Date.now() / 1000),
            nonce: 1,
            expected_account_id: null,
            user_data: scenario.legitimateUser
        };

        const legitimateResult = this.simulateVerification(legitimateInput);

        // Attacker's attempt
        console.log(`\n🚨 Attacker's Takeover Attempt`);
        const attackerInput = {
            platform: 'TWITTER',
            oauth_token: "Bearer attacker_token_67890",
            wallet_address: scenario.wallet,
            timestamp: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60),
            nonce: 2,
            expected_account_id: scenario.legitimateUser.id, // Claims to be re-verification
            user_data: scenario.attackerUser
        };

        const attackerResult = this.simulateVerification(attackerInput);

        console.log(`\n📊 SECURITY ANALYSIS:`);
        console.log(`   Legitimate user hash: 0x${legitimateResult.social_account_hash}`);
        console.log(`   Attacker's hash: 0x${attackerResult.social_account_hash}`);
        console.log(`   Hashes are different: ${legitimateResult.social_account_hash !== attackerResult.social_account_hash}`);
        console.log(`   Attacker verification type: ${attackerResult.verification_type}`);
        console.log(`   Attacker consistency score: ${attackerResult.account_consistency_score}/100`);
        console.log(`   🛡️ Attack detected: ${attackerResult.verification_type === 'ACCOUNT_UPDATE' && attackerResult.account_consistency_score < 50 ? 'YES' : 'NO'}`);

        return { legitimateResult, attackerResult };
    }

    async runAllDemos() {
        console.log("🚀 RISC Zero Social Verification - Token Management Demo");
        console.log("=" * 80);
        console.log("This demo shows how OAuth token changes are handled securely");
        console.log("while maintaining consistent account-to-wallet mappings.\n");

        try {
            await this.runTokenExpirationDemo();
            await this.runUsernameChangeDemo();
            await this.runAccountTakeoverDemo();

            console.log(`\n🎉 ALL DEMOS COMPLETED SUCCESSFULLY!`);
            console.log(`\n💡 KEY TAKEAWAYS:`);
            console.log(`   ✅ OAuth tokens can change without affecting account mappings`);
            console.log(`   ✅ Account hashes remain consistent based on stable account IDs`);
            console.log(`   ✅ Username changes don't break verification`);
            console.log(`   ✅ Account takeover attempts are detected and flagged`);
            console.log(`   ✅ System provides strong Sybil resistance`);

        } catch (error) {
            console.error(`❌ Demo failed:`, error);
        }
    }
}

// Run the demo (safe module check, no dynamic code execution)
if (typeof module !== 'undefined' && module.exports && require.main === module) {
    const demo = new SocialVerificationDemo();
    demo.runAllDemos();
}

// Safe module export
if (typeof module !== 'undefined' && module.exports) {
    module.exports = SocialVerificationDemo;
}
