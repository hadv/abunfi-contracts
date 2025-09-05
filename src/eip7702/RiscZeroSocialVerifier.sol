// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title RiscZeroSocialVerifier
 * @dev Verifies RISC Zero proofs for social account verification
 * This contract acts as the bridge between RISC Zero guest programs and the social registry
 */
contract RiscZeroSocialVerifier is Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // Events
    event ProofVerified(bytes32 indexed proofHash, address indexed requester, SocialPlatform platform, bool success);
    event VerifierKeyUpdated(address indexed oldKey, address indexed newKey);
    event PlatformEndpointUpdated(SocialPlatform platform, string endpoint);

    // Enums
    enum SocialPlatform {
        TWITTER,
        DISCORD,
        GITHUB,
        TELEGRAM,
        LINKEDIN
    }

    // Structs
    struct ProofData {
        bytes32 socialAccountHash;
        address walletAddress;
        SocialPlatform platform;
        uint256 accountAge;
        uint256 followerCount;
        uint256 timestamp;
        string socialAccountId; // For debugging/verification
        bytes32 oauthTokenHash; // Hash of OAuth token used
    }

    struct VerificationRequest {
        address requester;
        ProofData data;
        bytes32 proofHash;
        uint256 requestedAt;
        bool isVerified;
        bool isCompleted;
    }

    // State variables
    mapping(bytes32 => VerificationRequest) public verificationRequests;
    mapping(SocialPlatform => string) public platformEndpoints;
    mapping(address => bool) public authorizedVerifiers;

    // RISC Zero specific
    address public riscZeroVerifierKey;
    uint256 public proofValidityPeriod = 1 hours;
    uint256 public requestTimeout = 30 minutes;

    // Social Registry contract
    address public socialRegistry;

    // Modifiers
    modifier onlyAuthorizedVerifier() {
        require(authorizedVerifiers[msg.sender], "Not authorized verifier");
        _;
    }

    modifier onlyValidRequest(bytes32 requestId) {
        require(verificationRequests[requestId].requester != address(0), "Invalid request");
        require(!verificationRequests[requestId].isCompleted, "Request already completed");
        require(block.timestamp <= verificationRequests[requestId].requestedAt + requestTimeout, "Request timed out");
        _;
    }

    constructor(address _riscZeroVerifierKey, address _socialRegistry) Ownable(msg.sender) {
        riscZeroVerifierKey = _riscZeroVerifierKey;
        socialRegistry = _socialRegistry;
        _initializePlatformEndpoints();

        // Add deployer as authorized verifier initially
        authorizedVerifiers[msg.sender] = true;
    }

    /**
     * @dev Request social account verification
     * @param platform The social platform to verify
     * @param oauthToken The OAuth token for the social account
     * @param walletAddress The wallet address to link to
     * @return requestId The unique request identifier
     */
    function requestVerification(SocialPlatform platform, string calldata oauthToken, address walletAddress)
        external
        nonReentrant
        returns (bytes32 requestId)
    {
        require(bytes(platformEndpoints[platform]).length > 0, "Platform not supported");
        require(walletAddress != address(0), "Invalid wallet address");

        // Generate unique request ID
        requestId = keccak256(abi.encodePacked(msg.sender, platform, walletAddress, block.timestamp, block.number));

        // Store verification request
        verificationRequests[requestId] = VerificationRequest({
            requester: msg.sender,
            data: ProofData({
                socialAccountHash: bytes32(0), // Will be filled by RISC Zero
                walletAddress: walletAddress,
                platform: platform,
                accountAge: 0, // Will be filled by RISC Zero
                followerCount: 0, // Will be filled by RISC Zero
                timestamp: block.timestamp,
                socialAccountId: "", // Will be filled by RISC Zero
                oauthTokenHash: keccak256(abi.encodePacked(oauthToken))
            }),
            proofHash: bytes32(0), // Will be filled when proof is submitted
            requestedAt: block.timestamp,
            isVerified: false,
            isCompleted: false
        });

        // Note: In a real implementation, this would trigger the RISC Zero guest program
        // The guest program would:
        // 1. Use the OAuth token to fetch user data from the social platform
        // 2. Verify the token validity and extract account information
        // 3. Generate a ZK proof of the verification
        // 4. Submit the proof back to this contract via submitProof()

        return requestId;
    }

    /**
     * @dev Submit verification proof from RISC Zero guest program
     * @param requestId The verification request ID
     * @param proofData The verified social account data
     * @param riscZeroProof The RISC Zero proof bytes
     * @param signature Signature from authorized verifier
     */
    function submitProof(
        bytes32 requestId,
        ProofData calldata proofData,
        bytes calldata riscZeroProof,
        bytes calldata signature
    ) external onlyAuthorizedVerifier onlyValidRequest(requestId) {
        VerificationRequest storage request = verificationRequests[requestId];

        // Verify the proof signature
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                requestId,
                proofData.socialAccountHash,
                proofData.walletAddress,
                uint256(proofData.platform),
                proofData.accountAge,
                proofData.followerCount,
                proofData.timestamp
            )
        );

        address signer = messageHash.toEthSignedMessageHash().recover(signature);
        require(signer == riscZeroVerifierKey, "Invalid proof signature");

        // Verify RISC Zero proof (simplified - in real implementation would call RISC Zero verifier)
        require(_verifyRiscZeroProof(riscZeroProof, proofData), "Invalid RISC Zero proof");

        // Update request with verified data
        request.data = proofData;
        request.proofHash = keccak256(riscZeroProof);
        request.isVerified = true;
        request.isCompleted = true;

        emit ProofVerified(request.proofHash, request.requester, proofData.platform, true);
    }

    /**
     * @dev Get verification result
     * @param requestId The verification request ID
     * @return isCompleted Whether verification is completed
     * @return isVerified Whether verification was successful
     * @return proofData The verified social account data
     */
    function getVerificationResult(bytes32 requestId)
        external
        view
        returns (bool isCompleted, bool isVerified, ProofData memory proofData)
    {
        VerificationRequest memory request = verificationRequests[requestId];
        return (request.isCompleted, request.isVerified, request.data);
    }

    /**
     * @dev Create verification proof for social registry
     * @param requestId The completed verification request ID
     * @return proof The formatted proof for social registry
     */
    function createRegistryProof(bytes32 requestId) external view returns (bytes memory proof) {
        VerificationRequest memory request = verificationRequests[requestId];
        require(request.isCompleted && request.isVerified, "Verification not completed");

        // Create signature for the proof
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                request.data.socialAccountHash,
                request.data.walletAddress,
                uint256(request.data.platform),
                request.data.accountAge,
                request.data.followerCount,
                request.data.timestamp,
                request.proofHash
            )
        );

        // In a real implementation, this would be signed by the verifier
        // For now, we'll return the unsigned proof data
        proof = abi.encode(
            request.data.socialAccountHash,
            request.data.walletAddress,
            request.data.platform,
            request.data.accountAge,
            request.data.followerCount,
            request.data.timestamp,
            request.proofHash,
            new bytes(0) // Placeholder for signature
        );
    }

    // Internal functions

    /**
     * @dev Verify RISC Zero proof (simplified implementation)
     * In a real implementation, this would call the actual RISC Zero verifier
     */
    function _verifyRiscZeroProof(bytes calldata proof, ProofData calldata data) internal pure returns (bool) {
        // Simplified verification - in real implementation would:
        // 1. Call RISC Zero verifier contract
        // 2. Verify the proof against the expected program hash
        // 3. Verify the public outputs match the provided data

        // For now, just check that proof is not empty
        return proof.length > 0 && data.socialAccountHash != bytes32(0);
    }

    /**
     * @dev Initialize platform API endpoints
     */
    function _initializePlatformEndpoints() internal {
        platformEndpoints[SocialPlatform.TWITTER] = "https://api.twitter.com/2/users/me";
        platformEndpoints[SocialPlatform.DISCORD] = "https://discord.com/api/users/@me";
        platformEndpoints[SocialPlatform.GITHUB] = "https://api.github.com/user";
        platformEndpoints[SocialPlatform.TELEGRAM] = "https://api.telegram.org/bot";
        platformEndpoints[SocialPlatform.LINKEDIN] = "https://api.linkedin.com/v2/people/~";
    }

    // Admin functions

    /**
     * @dev Add or remove authorized verifier
     */
    function setAuthorizedVerifier(address verifier, bool authorized) external onlyOwner {
        authorizedVerifiers[verifier] = authorized;
    }

    /**
     * @dev Update RISC Zero verifier key
     */
    function setRiscZeroVerifierKey(address newKey) external onlyOwner {
        address oldKey = riscZeroVerifierKey;
        riscZeroVerifierKey = newKey;
        emit VerifierKeyUpdated(oldKey, newKey);
    }

    /**
     * @dev Update platform endpoint
     */
    function setPlatformEndpoint(SocialPlatform platform, string calldata endpoint) external onlyOwner {
        platformEndpoints[platform] = endpoint;
        emit PlatformEndpointUpdated(platform, endpoint);
    }

    /**
     * @dev Set social registry contract
     */
    function setSocialRegistry(address _socialRegistry) external onlyOwner {
        socialRegistry = _socialRegistry;
    }

    /**
     * @dev Set proof validity period
     */
    function setProofValidityPeriod(uint256 _period) external onlyOwner {
        proofValidityPeriod = _period;
    }

    /**
     * @dev Set request timeout
     */
    function setRequestTimeout(uint256 _timeout) external onlyOwner {
        requestTimeout = _timeout;
    }

    /**
     * @dev Emergency function to complete failed verification
     */
    function emergencyCompleteVerification(bytes32 requestId, bool success) external onlyOwner {
        VerificationRequest storage request = verificationRequests[requestId];
        require(request.requester != address(0), "Invalid request");

        request.isCompleted = true;
        request.isVerified = success;

        emit ProofVerified(request.proofHash, request.requester, request.data.platform, success);
    }
}
