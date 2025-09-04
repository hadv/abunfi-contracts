// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title SocialAccountRegistry
 * @dev Registry for linking social accounts to wallet addresses using RISC Zero ZK proofs
 * Prevents Sybil attacks by ensuring one social account maps to one wallet address
 */
contract SocialAccountRegistry is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // Events
    event SocialAccountLinked(
        bytes32 indexed socialAccountHash, address indexed walletAddress, SocialPlatform platform, uint256 timestamp
    );
    event SocialAccountUnlinked(
        bytes32 indexed socialAccountHash, address indexed walletAddress, SocialPlatform platform
    );
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event PlatformConfigUpdated(SocialPlatform platform, PlatformConfig config);

    // Enums
    enum SocialPlatform {
        TWITTER,
        DISCORD,
        GITHUB,
        TELEGRAM,
        LINKEDIN
    }

    // Structs
    struct SocialAccount {
        address walletAddress;
        SocialPlatform platform;
        uint256 linkedAt;
        uint256 lastVerified;
        bool isActive;
    }

    struct PlatformConfig {
        bool isEnabled;
        uint256 minimumAccountAge; // in seconds
        uint256 minimumFollowers;
        uint256 verificationCooldown; // time between re-verifications
        bool requiresAdditionalVerification;
    }

    struct VerificationProof {
        bytes32 socialAccountHash;
        address walletAddress;
        SocialPlatform platform;
        uint256 accountAge;
        uint256 followerCount;
        uint256 timestamp;
        bytes32 proofHash; // RISC Zero proof hash
        bytes signature; // Signature from RISC Zero verifier
    }

    // State variables
    mapping(bytes32 => SocialAccount) public socialAccounts;
    mapping(address => bytes32[]) public walletToSocialAccounts;
    mapping(SocialPlatform => PlatformConfig) public platformConfigs;

    // RISC Zero verifier contract address
    address public riscZeroVerifier;

    // Maximum social accounts per wallet
    uint256 public maxAccountsPerWallet = 5;

    // Verification validity period
    uint256 public verificationValidityPeriod = 30 days;

    // Modifiers
    modifier onlyValidPlatform(SocialPlatform platform) {
        require(platformConfigs[platform].isEnabled, "Platform not enabled");
        _;
    }

    modifier onlyRiscZeroVerifier() {
        require(msg.sender == riscZeroVerifier, "Only RISC Zero verifier");
        _;
    }

    constructor(address _riscZeroVerifier) Ownable(msg.sender) {
        riscZeroVerifier = _riscZeroVerifier;
        _initializePlatformConfigs();
    }

    /**
     * @dev Link a social account to a wallet address using RISC Zero proof
     * @param proof The verification proof from RISC Zero guest program
     */
    function linkSocialAccount(VerificationProof calldata proof)
        external
        nonReentrant
        onlyValidPlatform(proof.platform)
    {
        // Verify the proof signature from RISC Zero verifier
        require(_verifyRiscZeroProof(proof), "Invalid RISC Zero proof");

        // Check if social account is already linked
        require(socialAccounts[proof.socialAccountHash].walletAddress == address(0), "Social account already linked");

        // Check platform-specific requirements
        PlatformConfig memory config = platformConfigs[proof.platform];
        require(proof.accountAge >= config.minimumAccountAge, "Account too young");
        require(proof.followerCount >= config.minimumFollowers, "Insufficient followers");

        // Check wallet doesn't exceed maximum accounts
        require(
            walletToSocialAccounts[proof.walletAddress].length < maxAccountsPerWallet,
            "Maximum accounts per wallet exceeded"
        );

        // Link the account
        socialAccounts[proof.socialAccountHash] = SocialAccount({
            walletAddress: proof.walletAddress,
            platform: proof.platform,
            linkedAt: block.timestamp,
            lastVerified: block.timestamp,
            isActive: true
        });

        walletToSocialAccounts[proof.walletAddress].push(proof.socialAccountHash);

        emit SocialAccountLinked(proof.socialAccountHash, proof.walletAddress, proof.platform, block.timestamp);
    }

    /**
     * @dev Unlink a social account from wallet address
     * @param socialAccountHash Hash of the social account to unlink
     */
    function unlinkSocialAccount(bytes32 socialAccountHash) external nonReentrant {
        SocialAccount storage account = socialAccounts[socialAccountHash];
        require(account.walletAddress == msg.sender, "Not account owner");
        require(account.isActive, "Account not active");

        // Remove from wallet's social accounts array
        _removeSocialAccountFromWallet(account.walletAddress, socialAccountHash);

        // Deactivate the account
        account.isActive = false;

        emit SocialAccountUnlinked(socialAccountHash, account.walletAddress, account.platform);
    }

    /**
     * @dev Re-verify a social account with updated proof
     * @param proof Updated verification proof
     */
    function reverifyAccount(VerificationProof calldata proof)
        external
        nonReentrant
        onlyValidPlatform(proof.platform)
    {
        require(_verifyRiscZeroProof(proof), "Invalid RISC Zero proof");

        SocialAccount storage account = socialAccounts[proof.socialAccountHash];
        require(account.walletAddress == proof.walletAddress, "Wallet mismatch");
        require(account.isActive, "Account not active");

        // Check cooldown period
        PlatformConfig memory config = platformConfigs[proof.platform];
        require(block.timestamp >= account.lastVerified + config.verificationCooldown, "Verification cooldown active");

        // Update verification timestamp
        account.lastVerified = block.timestamp;
    }

    /**
     * @dev Check if a wallet address has valid social verification
     * @param walletAddress The wallet address to check
     * @return hasValidVerification Whether the wallet has valid social verification
     * @return verificationLevel The level of verification (number of verified accounts)
     */
    function getVerificationStatus(address walletAddress)
        external
        view
        returns (bool hasValidVerification, uint256 verificationLevel)
    {
        bytes32[] memory socialAccountHashes = walletToSocialAccounts[walletAddress];
        uint256 validAccounts = 0;

        for (uint256 i = 0; i < socialAccountHashes.length; i++) {
            SocialAccount memory account = socialAccounts[socialAccountHashes[i]];
            if (account.isActive && _isVerificationValid(account)) {
                validAccounts++;
            }
        }

        hasValidVerification = validAccounts > 0;
        verificationLevel = validAccounts;
    }

    /**
     * @dev Get social accounts linked to a wallet
     * @param walletAddress The wallet address
     * @return socialAccountHashes Array of linked social account hashes
     */
    function getLinkedAccounts(address walletAddress) external view returns (bytes32[] memory socialAccountHashes) {
        return walletToSocialAccounts[walletAddress];
    }

    /**
     * @dev Check if a social account hash is already linked
     * @param socialAccountHash The social account hash to check
     * @return isLinked Whether the account is linked
     * @return linkedWallet The wallet address it's linked to
     */
    function isSocialAccountLinked(bytes32 socialAccountHash)
        external
        view
        returns (bool isLinked, address linkedWallet)
    {
        SocialAccount memory account = socialAccounts[socialAccountHash];
        isLinked = account.isActive && account.walletAddress != address(0);
        linkedWallet = account.walletAddress;
    }

    // Internal functions

    /**
     * @dev Verify RISC Zero proof signature
     */
    function _verifyRiscZeroProof(VerificationProof calldata proof) internal view returns (bool) {
        // Create the message hash from proof data
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

        // Verify signature from RISC Zero verifier
        address signer = messageHash.toEthSignedMessageHash().recover(proof.signature);
        return signer == riscZeroVerifier;
    }

    /**
     * @dev Check if verification is still valid
     */
    function _isVerificationValid(SocialAccount memory account) internal view returns (bool) {
        return block.timestamp <= account.lastVerified + verificationValidityPeriod;
    }

    /**
     * @dev Remove social account from wallet's array
     */
    function _removeSocialAccountFromWallet(address wallet, bytes32 socialAccountHash) internal {
        bytes32[] storage accounts = walletToSocialAccounts[wallet];
        for (uint256 i = 0; i < accounts.length; i++) {
            if (accounts[i] == socialAccountHash) {
                accounts[i] = accounts[accounts.length - 1];
                accounts.pop();
                break;
            }
        }
    }

    /**
     * @dev Initialize default platform configurations
     */
    function _initializePlatformConfigs() internal {
        // Twitter configuration
        platformConfigs[SocialPlatform.TWITTER] = PlatformConfig({
            isEnabled: true,
            minimumAccountAge: 30 days,
            minimumFollowers: 10,
            verificationCooldown: 7 days,
            requiresAdditionalVerification: false
        });

        // Discord configuration
        platformConfigs[SocialPlatform.DISCORD] = PlatformConfig({
            isEnabled: true,
            minimumAccountAge: 14 days,
            minimumFollowers: 0,
            verificationCooldown: 7 days,
            requiresAdditionalVerification: false
        });

        // GitHub configuration
        platformConfigs[SocialPlatform.GITHUB] = PlatformConfig({
            isEnabled: true,
            minimumAccountAge: 90 days,
            minimumFollowers: 5,
            verificationCooldown: 14 days,
            requiresAdditionalVerification: true
        });
    }

    // Admin functions

    /**
     * @dev Update RISC Zero verifier address
     */
    function setRiscZeroVerifier(address _newVerifier) external onlyOwner {
        address oldVerifier = riscZeroVerifier;
        riscZeroVerifier = _newVerifier;
        emit VerifierUpdated(oldVerifier, _newVerifier);
    }

    /**
     * @dev Update platform configuration
     */
    function setPlatformConfig(SocialPlatform platform, PlatformConfig calldata config) external onlyOwner {
        platformConfigs[platform] = config;
        emit PlatformConfigUpdated(platform, config);
    }

    /**
     * @dev Set maximum accounts per wallet
     */
    function setMaxAccountsPerWallet(uint256 _maxAccounts) external onlyOwner {
        maxAccountsPerWallet = _maxAccounts;
    }

    /**
     * @dev Set verification validity period
     */
    function setVerificationValidityPeriod(uint256 _period) external onlyOwner {
        verificationValidityPeriod = _period;
    }
}
