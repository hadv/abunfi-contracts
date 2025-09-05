// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/eip7702/SocialAccountRegistry.sol";
import "../src/eip7702/RiscZeroSocialVerifier.sol";
import "../src/eip7702/EIP7702Paymaster.sol";

/**
 * @title TokenManagementIntegrationTest
 * @dev Integration tests for OAuth token management and account consistency
 */
contract TokenManagementIntegrationTest is Test {
    SocialAccountRegistry public socialRegistry;
    RiscZeroSocialVerifier public verifier;
    EIP7702Paymaster public paymaster;

    // Test private key for signing (DO NOT use in production)
    uint256 private constant TEST_PRIVATE_KEY = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address public testSigner;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public attacker = makeAddr("attacker");

    // Mock social account data
    bytes32 public constant ALICE_TWITTER_HASH = keccak256(abi.encodePacked("TWITTER", "123456789"));
    bytes32 public constant ALICE_GITHUB_HASH = keccak256(abi.encodePacked("GITHUB", "987654321"));
    bytes32 public constant BOB_TWITTER_HASH = keccak256(abi.encodePacked("TWITTER", "555666777"));

    event SocialAccountLinked(
        bytes32 indexed socialAccountHash,
        address indexed walletAddress,
        SocialAccountRegistry.SocialPlatform platform,
        uint256 timestamp
    );

    event AccountReverified(bytes32 indexed socialAccountHash, address indexed walletAddress, uint256 timestamp);

    function setUp() public {
        // Derive test signer address from private key
        testSigner = vm.addr(TEST_PRIVATE_KEY);

        // Deploy contracts with test signer
        socialRegistry = new SocialAccountRegistry(testSigner);
        verifier = new RiscZeroSocialVerifier(testSigner, address(socialRegistry));
        paymaster = new EIP7702Paymaster(address(socialRegistry));

        // Fund paymaster
        vm.deal(address(paymaster), 10 ether);
    }

    function test_TokenExpirationAndReverification() public {
        console.log("Testing: Token Expiration and Re-verification");

        // Link Alice's Twitter account using test function (bypasses RISC Zero verification)
        vm.prank(alice);
        socialRegistry.linkSocialAccountForTesting(
            ALICE_TWITTER_HASH, alice, SocialAccountRegistry.SocialPlatform.TWITTER
        );

        // Verify initial linking
        (bool isLinked, address linkedWallet) = socialRegistry.isSocialAccountLinked(ALICE_TWITTER_HASH);
        assertTrue(isLinked);
        assertEq(linkedWallet, alice);

        // Check verification status
        (bool hasVerification, uint256 verificationLevel) = socialRegistry.getVerificationStatus(alice);
        assertTrue(hasVerification);
        assertEq(verificationLevel, 1);

        console.log("Initial verification successful");
        console.log("   Account Hash: %s", vm.toString(ALICE_TWITTER_HASH));
        console.log("   Linked Wallet: %s", alice);

        // Simulate token expiration (30 days later)
        vm.warp(block.timestamp + 30 days);

        // Alice re-verifies with new token (same account ID, different token)
        // Use test function to simulate re-verification
        vm.prank(alice);
        socialRegistry.reverifyAccountForTesting(
            ALICE_TWITTER_HASH, // Same hash (same account ID)
            alice,
            SocialAccountRegistry.SocialPlatform.TWITTER
        );

        // Verification status should remain the same
        (bool stillLinked, address stillLinkedWallet) = socialRegistry.isSocialAccountLinked(ALICE_TWITTER_HASH);
        assertTrue(stillLinked);
        assertEq(stillLinkedWallet, alice);

        (bool stillHasVerification, uint256 stillVerificationLevel) = socialRegistry.getVerificationStatus(alice);
        assertTrue(stillHasVerification);
        assertEq(stillVerificationLevel, 1);

        console.log("Re-verification with new token successful");
        console.log("   Same account hash maintained");
        console.log("   Verification level unchanged: %d", stillVerificationLevel);
    }

    function test_UsernameChangeWithSameAccount() public {
        console.log("Testing: Username Change with Same Account ID");

        // Bob's initial verification with username "bob_defi" using test function
        vm.prank(bob);
        socialRegistry.linkSocialAccountForTesting(BOB_TWITTER_HASH, bob, SocialAccountRegistry.SocialPlatform.TWITTER);

        // Verify initial state
        (bool isLinked, address linkedWallet) = socialRegistry.isSocialAccountLinked(BOB_TWITTER_HASH);
        assertTrue(isLinked);
        assertEq(linkedWallet, bob);

        console.log("Initial verification with username 'bob_defi'");

        // Bob changes username to "bob_web3" but keeps same account ID
        vm.warp(block.timestamp + 15 days);

        // Use test function to simulate re-verification after username change
        vm.prank(bob);
        socialRegistry.reverifyAccountForTesting(
            BOB_TWITTER_HASH, // Same hash (same account ID)
            bob,
            SocialAccountRegistry.SocialPlatform.TWITTER
        );

        // Account should still be linked with same hash
        (bool stillLinked, address stillLinkedWallet) = socialRegistry.isSocialAccountLinked(BOB_TWITTER_HASH);
        assertTrue(stillLinked);
        assertEq(stillLinkedWallet, bob);

        console.log("Username change handled correctly");
        console.log("   Same account hash: %s", vm.toString(BOB_TWITTER_HASH));
        console.log("   Username change: bob_defi -> bob_web3");
    }

    function test_AccountTakeoverAttempt() public {
        console.log("Testing: Account Takeover Attempt");

        // Alice links her legitimate account using test function
        vm.prank(alice);
        socialRegistry.linkSocialAccountForTesting(
            ALICE_TWITTER_HASH, alice, SocialAccountRegistry.SocialPlatform.TWITTER
        );

        console.log("Alice's legitimate account linked");

        // Attacker tries to link a different account to Alice's wallet
        bytes32 attackerAccountHash = keccak256(abi.encodePacked("TWITTER", "999888777")); // Different account ID

        // This should succeed as a new account link (different hash) using test function
        vm.prank(alice);
        socialRegistry.linkSocialAccountForTesting(
            attackerAccountHash, // Different hash (different account)
            alice, // Trying to link to Alice's wallet
            SocialAccountRegistry.SocialPlatform.TWITTER
        );

        // But Alice now has 2 linked accounts
        (bool hasVerification, uint256 verificationLevel) = socialRegistry.getVerificationStatus(alice);
        assertTrue(hasVerification);
        assertEq(verificationLevel, 2); // Two accounts linked

        // Original account should still be linked
        (bool originalLinked,) = socialRegistry.isSocialAccountLinked(ALICE_TWITTER_HASH);
        assertTrue(originalLinked);

        // New account should also be linked
        (bool attackerLinked,) = socialRegistry.isSocialAccountLinked(attackerAccountHash);
        assertTrue(attackerLinked);

        console.log("Multiple accounts can be linked to same wallet");
        console.log("   Original account still linked: %s", originalLinked ? "true" : "false");
        console.log("   New account also linked: %s", attackerLinked ? "true" : "false");
        console.log("   Total verification level: %d", verificationLevel);
    }

    function test_MultiPlatformVerification() public {
        console.log("Testing: Multi-Platform Verification");

        // Alice verifies Twitter account using test function
        vm.prank(alice);
        socialRegistry.linkSocialAccountForTesting(
            ALICE_TWITTER_HASH, alice, SocialAccountRegistry.SocialPlatform.TWITTER
        );

        // Alice verifies GitHub account using test function
        vm.prank(alice);
        socialRegistry.linkSocialAccountForTesting(
            ALICE_GITHUB_HASH, alice, SocialAccountRegistry.SocialPlatform.GITHUB
        );

        // Check verification status
        (bool hasVerification, uint256 verificationLevel) = socialRegistry.getVerificationStatus(alice);
        assertTrue(hasVerification);
        assertEq(verificationLevel, 2); // Two platforms verified

        // Both accounts should be linked
        (bool twitterLinked,) = socialRegistry.isSocialAccountLinked(ALICE_TWITTER_HASH);
        (bool githubLinked,) = socialRegistry.isSocialAccountLinked(ALICE_GITHUB_HASH);
        assertTrue(twitterLinked);
        assertTrue(githubLinked);

        console.log("Multi-platform verification successful");
        console.log("   Twitter linked: %s", twitterLinked ? "true" : "false");
        console.log("   GitHub linked: %s", githubLinked ? "true" : "false");
        console.log("   Total verification level: %d", verificationLevel);
    }

    function test_PaymasterIntegrationWithSocialVerification() public {
        console.log("Testing: Paymaster Integration with Social Verification");

        // Set up paymaster policy requiring social verification
        EIP7702Paymaster.SponsorshipPolicy memory policy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.1 ether,
            perTxGasLimit: 0.01 ether,
            dailyTxLimit: 50,
            requiresWhitelist: false,
            requiresSocialVerification: true,
            minimumVerificationLevel: 1,
            isActive: true
        });

        paymaster.setGlobalPolicy(policy);

        // Alice without verification should be rejected
        (bool canSponsorBefore,) = _validateUserOperation(alice);
        assertFalse(canSponsorBefore);

        console.log("Unverified user rejected by paymaster");

        // Alice verifies her Twitter account using test function
        vm.prank(alice);
        socialRegistry.linkSocialAccountForTesting(
            ALICE_TWITTER_HASH, alice, SocialAccountRegistry.SocialPlatform.TWITTER
        );

        // Alice with verification should be accepted
        (bool canSponsorAfter,) = _validateUserOperation(alice);
        assertTrue(canSponsorAfter);

        console.log("Verified user accepted by paymaster");
        console.log("   Social verification enables gas sponsorship");
    }

    // Helper functions

    function _generateSignatureForProof(SocialAccountRegistry.VerificationProof memory proof)
        internal
        view
        returns (bytes memory)
    {
        // Create the same message hash that the contract will verify
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                proof.socialAccountHash,
                proof.walletAddress,
                uint256(proof.platform),
                proof.accountAge,
                proof.followerCount,
                proof.timestamp,
                proof.proofHash
            )
        );

        // Use the same method as the contract: toEthSignedMessageHash
        // This matches MessageHashUtils.toEthSignedMessageHash() in the contract
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_PRIVATE_KEY, ethSignedMessageHash);

        return abi.encodePacked(r, s, v);
    }

    function _createSignedProof(
        bytes32 socialAccountHash,
        address walletAddress,
        SocialAccountRegistry.SocialPlatform platform,
        uint256 accountAge,
        uint256 followerCount,
        bytes32 proofHash
    ) internal view returns (SocialAccountRegistry.VerificationProof memory) {
        SocialAccountRegistry.VerificationProof memory proof = SocialAccountRegistry.VerificationProof({
            socialAccountHash: socialAccountHash,
            walletAddress: walletAddress,
            platform: platform,
            accountAge: accountAge,
            followerCount: followerCount,
            timestamp: block.timestamp,
            proofHash: proofHash,
            signature: ""
        });

        proof.signature = _generateSignatureForProof(proof);
        return proof;
    }

    function _generateMockSignature(bytes32 socialAccountHash, address walletAddress)
        internal
        view
        returns (bytes memory)
    {
        SocialAccountRegistry.VerificationProof memory tempProof = _createSignedProof(
            socialAccountHash,
            walletAddress,
            SocialAccountRegistry.SocialPlatform.TWITTER,
            365 days,
            150,
            keccak256("test_proof")
        );

        return tempProof.signature;
    }

    function _validateUserOperation(address account) internal view returns (bool success, uint256 gasPrice) {
        // Mock user operation
        AbunfiSmartAccount.UserOperation memory userOp = AbunfiSmartAccount.UserOperation({
            target: account,
            value: 0,
            data: "",
            nonce: 1,
            maxFeePerGas: 20 gwei,
            maxPriorityFeePerGas: 2 gwei,
            gasLimit: 100000,
            paymaster: address(paymaster),
            paymasterData: "",
            signature: ""
        });

        EIP7702Paymaster.UserOperationContext memory context = EIP7702Paymaster.UserOperationContext({
            account: account,
            maxFeePerGas: 20 gwei,
            gasLimit: 100000,
            signature: ""
        });

        return paymaster.validateUserOperation(userOp, context);
    }
}
