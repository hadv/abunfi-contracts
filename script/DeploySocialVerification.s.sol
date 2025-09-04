// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/eip7702/SocialAccountRegistry.sol";
import "../src/eip7702/RiscZeroSocialVerifier.sol";
import "../src/eip7702/EIP7702Paymaster.sol";

/**
 * @title DeploySocialVerification
 * @dev Deployment script for RISC Zero social verification system
 */
contract DeploySocialVerification is Script {
    // Configuration
    address public constant RISC_ZERO_VERIFIER_KEY = 0x1234567890123456789012345678901234567890; // Replace with actual key
    uint256 public constant INITIAL_PAYMASTER_FUNDING = 2 ether;
    
    // Deployed contract addresses
    SocialAccountRegistry public socialRegistry;
    RiscZeroSocialVerifier public riscZeroVerifier;
    EIP7702Paymaster public paymaster;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== RISC Zero Social Verification Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Balance:", deployer.balance / 1e18, "ETH");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy Social Account Registry
        console.log("\n1. Deploying SocialAccountRegistry...");
        socialRegistry = new SocialAccountRegistry(RISC_ZERO_VERIFIER_KEY);
        console.log("SocialAccountRegistry deployed at:", address(socialRegistry));
        
        // Step 2: Deploy RISC Zero Verifier
        console.log("\n2. Deploying RiscZeroSocialVerifier...");
        riscZeroVerifier = new RiscZeroSocialVerifier(
            RISC_ZERO_VERIFIER_KEY,
            address(socialRegistry)
        );
        console.log("RiscZeroSocialVerifier deployed at:", address(riscZeroVerifier));
        
        // Step 3: Deploy Enhanced Paymaster
        console.log("\n3. Deploying Enhanced EIP7702Paymaster...");
        paymaster = new EIP7702Paymaster(address(socialRegistry));
        console.log("EIP7702Paymaster deployed at:", address(paymaster));
        
        // Step 4: Configure the system
        console.log("\n4. Configuring system...");
        _configureSystem();
        
        // Step 5: Fund the paymaster
        console.log("\n5. Funding paymaster...");
        payable(address(paymaster)).transfer(INITIAL_PAYMASTER_FUNDING);
        console.log("Paymaster funded with:", INITIAL_PAYMASTER_FUNDING / 1e18, "ETH");
        
        vm.stopBroadcast();
        
        // Step 6: Display deployment summary
        _displayDeploymentSummary();
        
        // Step 7: Verify contracts (if on testnet/mainnet)
        if (block.chainid != 31337) { // Not local
            _verifyContracts();
        }
    }
    
    function _configureSystem() internal {
        // Configure Social Registry platform settings
        console.log("Configuring platform settings...");
        
        // Twitter configuration
        SocialAccountRegistry.PlatformConfig memory twitterConfig = SocialAccountRegistry.PlatformConfig({
            isEnabled: true,
            minimumAccountAge: 30 days,
            minimumFollowers: 10,
            verificationCooldown: 7 days,
            requiresAdditionalVerification: false
        });
        socialRegistry.setPlatformConfig(SocialAccountRegistry.SocialPlatform.TWITTER, twitterConfig);
        
        // Discord configuration
        SocialAccountRegistry.PlatformConfig memory discordConfig = SocialAccountRegistry.PlatformConfig({
            isEnabled: true,
            minimumAccountAge: 14 days,
            minimumFollowers: 0,
            verificationCooldown: 7 days,
            requiresAdditionalVerification: false
        });
        socialRegistry.setPlatformConfig(SocialAccountRegistry.SocialPlatform.DISCORD, discordConfig);
        
        // GitHub configuration (stricter requirements)
        SocialAccountRegistry.PlatformConfig memory githubConfig = SocialAccountRegistry.PlatformConfig({
            isEnabled: true,
            minimumAccountAge: 90 days,
            minimumFollowers: 5,
            verificationCooldown: 14 days,
            requiresAdditionalVerification: true
        });
        socialRegistry.setPlatformConfig(SocialAccountRegistry.SocialPlatform.GITHUB, githubConfig);
        
        // Configure Paymaster with social verification
        console.log("Configuring paymaster policies...");
        
        // Basic policy (no social verification required)
        EIP7702Paymaster.SponsorshipPolicy memory basicPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.01 ether, // $25 at 2500 ETH
            perTxGasLimit: 0.002 ether, // $5 per tx
            dailyTxLimit: 10,
            requiresWhitelist: false,
            requiresSocialVerification: false,
            minimumVerificationLevel: 0,
            isActive: true
        });
        paymaster.setGlobalPolicy(basicPolicy);
        
        // Set RISC Zero verifier as authorized
        riscZeroVerifier.setAuthorizedVerifier(address(this), true);
        
        console.log("System configuration completed");
    }
    
    function _displayDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network: %s (Chain ID: %d)", _getNetworkName(), block.chainid);
        console.log("");
        console.log("Core Contracts:");
        console.log("  - SocialAccountRegistry: %s", address(socialRegistry));
        console.log("  - RiscZeroSocialVerifier: %s", address(riscZeroVerifier));
        console.log("  - EIP7702Paymaster: %s", address(paymaster));
        console.log("");
        console.log("Configuration:");
        console.log("  - RISC Zero Verifier Key: %s", RISC_ZERO_VERIFIER_KEY);
        console.log("  - Paymaster Funding: %d ETH", INITIAL_PAYMASTER_FUNDING / 1e18);
        console.log("  - Supported Platforms: Twitter, Discord, GitHub");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Setup RISC Zero verification service");
        console.log("2. Configure frontend integration");
        console.log("3. Test social verification flow");
        console.log("4. Monitor system performance");
        console.log("");
        console.log("Documentation:");
        console.log("  - See docs/RISC_ZERO_SOCIAL_VERIFICATION.md");
    }
    
    function _verifyContracts() internal {
        console.log("\n=== CONTRACT VERIFICATION ===");
        console.log("Verifying contracts on block explorer...");
        
        // Note: In a real deployment, you would use forge verify-contract
        // or similar tools to verify the contracts on Etherscan
        
        string[] memory verifyCommands = new string[](3);
        
        // Social Registry verification
        verifyCommands[0] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(address(socialRegistry)),
            " src/eip7702/SocialAccountRegistry.sol:SocialAccountRegistry",
            " --constructor-args $(cast abi-encode 'constructor(address)' ",
            vm.toString(RISC_ZERO_VERIFIER_KEY),
            ")"
        ));
        
        // RISC Zero Verifier verification
        verifyCommands[1] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(address(riscZeroVerifier)),
            " src/eip7702/RiscZeroSocialVerifier.sol:RiscZeroSocialVerifier",
            " --constructor-args $(cast abi-encode 'constructor(address,address)' ",
            vm.toString(RISC_ZERO_VERIFIER_KEY),
            " ",
            vm.toString(address(socialRegistry)),
            ")"
        ));
        
        // Paymaster verification
        verifyCommands[2] = string(abi.encodePacked(
            "forge verify-contract ",
            vm.toString(address(paymaster)),
            " src/eip7702/EIP7702Paymaster.sol:EIP7702Paymaster",
            " --constructor-args $(cast abi-encode 'constructor(address)' ",
            vm.toString(address(socialRegistry)),
            ")"
        ));
        
        console.log("Run these commands to verify contracts:");
        for (uint i = 0; i < verifyCommands.length; i++) {
            console.log(verifyCommands[i]);
        }
    }
    
    function _getNetworkName() internal view returns (string memory) {
        if (block.chainid == 1) return "Ethereum Mainnet";
        if (block.chainid == 11155111) return "Sepolia Testnet";
        if (block.chainid == 137) return "Polygon Mainnet";
        if (block.chainid == 80001) return "Polygon Mumbai";
        if (block.chainid == 42161) return "Arbitrum One";
        if (block.chainid == 421613) return "Arbitrum Goerli";
        if (block.chainid == 31337) return "Local Network";
        return "Unknown Network";
    }
    
    // Helper function to create example verification policies
    function createExamplePolicies() external view returns (
        EIP7702Paymaster.SponsorshipPolicy memory unverified,
        EIP7702Paymaster.SponsorshipPolicy memory singleVerified,
        EIP7702Paymaster.SponsorshipPolicy memory multiVerified
    ) {
        // Policy for unverified users (very limited)
        unverified = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.005 ether, // $12.50 at 2500 ETH
            perTxGasLimit: 0.001 ether, // $2.50 per tx
            dailyTxLimit: 5,
            requiresWhitelist: false,
            requiresSocialVerification: false,
            minimumVerificationLevel: 0,
            isActive: true
        });
        
        // Policy for single platform verified users
        singleVerified = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.02 ether, // $50 at 2500 ETH
            perTxGasLimit: 0.004 ether, // $10 per tx
            dailyTxLimit: 20,
            requiresWhitelist: false,
            requiresSocialVerification: true,
            minimumVerificationLevel: 1,
            isActive: true
        });
        
        // Policy for multi-platform verified users (premium)
        multiVerified = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.1 ether, // $250 at 2500 ETH
            perTxGasLimit: 0.01 ether, // $25 per tx
            dailyTxLimit: 100,
            requiresWhitelist: false,
            requiresSocialVerification: true,
            minimumVerificationLevel: 2,
            isActive: true
        });
    }
}
