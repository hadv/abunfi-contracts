// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/eip7702/AbunfiSmartAccount.sol";
import "../src/eip7702/EIP7702Paymaster.sol";
import "../src/eip7702/EIP7702Bundler.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title DeploySepoliaTest
 * @dev Deployment script specifically for Sepolia testnet with security testing configurations
 */
contract DeploySepoliaTest is Script {
    // Sepolia-specific configuration for testing
    uint256 public constant INITIAL_PAYMASTER_FUNDING = 2 ether; // 2 ETH for testing
    uint256 public constant GLOBAL_DAILY_LIMIT = 5 ether; // 5 ETH daily limit for testing

    // Rate limiting configuration for testing DOS/Sybil prevention
    uint256 public constant DEFAULT_DAILY_GAS_LIMIT = 0.1 ether; // 0.1 ETH per day (standard)
    uint256 public constant WHITELISTED_DAILY_GAS_LIMIT = 0.2 ether; // 0.2 ETH per day (whitelisted)
    uint256 public constant DEFAULT_PER_TX_GAS_LIMIT = 0.01 ether; // 0.01 ETH per transaction (standard)
    uint256 public constant WHITELISTED_PER_TX_GAS_LIMIT = 0.02 ether; // 0.02 ETH per transaction (whitelisted)
    uint256 public constant DEFAULT_DAILY_TX_LIMIT = 50; // 50 transactions per day (standard)
    uint256 public constant WHITELISTED_DAILY_TX_LIMIT = 100; // 100 transactions per day (whitelisted)

    // Test accounts for security testing
    address[] public securityTestAccounts;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Verify we're on Sepolia
        require(block.chainid == 11155111, "This script is only for Sepolia testnet (chainId: 11155111)");

        console.log("Deploying Abunfi Security Testing Infrastructure on Sepolia...");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);

        // Ensure deployer has enough ETH
        require(deployer.balance >= 3 ether, "Deployer needs at least 3 ETH for deployment and testing");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Smart Account Implementation
        console.log("\n1. Deploying AbunfiSmartAccount implementation...");
        AbunfiSmartAccount smartAccountImpl = new AbunfiSmartAccount();
        console.log("AbunfiSmartAccount implementation deployed at:", address(smartAccountImpl));

        // 2. Deploy EIP7702Paymaster with security configurations
        console.log("\n2. Deploying EIP7702Paymaster with security configurations...");
        EIP7702Paymaster paymaster = new EIP7702Paymaster(
            address(0) // socialRegistry - using address(0) for testing
        );
        console.log("EIP7702Paymaster deployed at:", address(paymaster));

        // 3. Deploy EIP7702Bundler
        console.log("\n3. Deploying EIP7702Bundler...");
        EIP7702Bundler bundler = new EIP7702Bundler();
        console.log("EIP7702Bundler deployed at:", address(bundler));

        // 4. Deploy Mock USDC for testing (Sepolia doesn't have real USDC)
        console.log("\n4. Deploying Mock USDC for testing...");
        MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
        address usdcAddress = address(mockUSDC);
        console.log("Mock USDC deployed at:", usdcAddress);

        // Mint USDC for testing
        mockUSDC.mint(deployer, 10000000 * 10 ** 6); // 10M USDC for testing
        console.log("Minted 10M USDC to deployer for testing");

        // 5. Deploy AbunfiVault
        console.log("\n5. Deploying AbunfiVault...");
        // Deploy mock risk management contracts for testing
        address riskProfileManager = address(new MockERC20("Mock Risk Manager", "MRM", 18));
        address withdrawalManager = address(new MockERC20("Mock Withdrawal Manager", "MWM", 18));

        AbunfiVault vault = new AbunfiVault(
            usdcAddress,
            address(0), // trustedForwarder - using address(0) for EIP-7702
            riskProfileManager,
            withdrawalManager
        );
        console.log("AbunfiVault deployed at:", address(vault));

        // 6. Configure the security system
        console.log("\n6. Configuring security system...");

        // Add bundler as trusted in paymaster
        paymaster.setTrustedBundler(address(bundler), true);
        console.log("Added bundler as trusted in paymaster");

        // Add paymaster to bundler
        bundler.addPaymaster(address(paymaster));
        console.log("Added paymaster to bundler");

        // Fund the paymaster for gas sponsorship
        payable(address(paymaster)).transfer(INITIAL_PAYMASTER_FUNDING);
        console.log("Funded paymaster with", INITIAL_PAYMASTER_FUNDING / 1e18, "ETH");

        // 7. Set up default rate limiting policies
        console.log("\n7. Setting up rate limiting policies...");

        // Set global default policy
        EIP7702Paymaster.SponsorshipPolicy memory defaultPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: DEFAULT_DAILY_GAS_LIMIT,
            perTxGasLimit: DEFAULT_PER_TX_GAS_LIMIT,
            dailyTxLimit: DEFAULT_DAILY_TX_LIMIT,
            requiresWhitelist: false,
            requiresSocialVerification: false,
            minimumVerificationLevel: 1,
            isActive: true
        });

        paymaster.setGlobalPolicy(defaultPolicy);
        console.log("Set global default policy:");
        console.log("  Daily gas limit: 0.1 ETH");
        console.log("  Per-tx gas limit: 0.01 ETH");
        console.log("  Daily tx limit: 50");

        // 8. Create test accounts for security testing
        console.log("\n8. Creating test accounts for security testing...");

        // Create 5 test accounts
        for (uint256 i = 0; i < 5; i++) {
            uint256 testPrivateKey = uint256(keccak256(abi.encodePacked("test_account", i, block.timestamp)));
            address testAccount = vm.addr(testPrivateKey);
            securityTestAccounts.push(testAccount);

            // Fund test accounts with some ETH for transactions
            payable(testAccount).transfer(0.1 ether);

            // Mint some USDC to test accounts
            mockUSDC.mint(testAccount, 1000 * 10 ** 6); // 1000 USDC each

            console.log("Test account", i + 1, ":", testAccount);
        }

        // 9. Set up whitelisted accounts for testing
        console.log("\n9. Setting up whitelisted accounts...");

        // Whitelist the first test account with higher limits
        address whitelistedAccount = securityTestAccounts[0];

        EIP7702Paymaster.SponsorshipPolicy memory whitelistedPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: WHITELISTED_DAILY_GAS_LIMIT,
            perTxGasLimit: WHITELISTED_PER_TX_GAS_LIMIT,
            dailyTxLimit: WHITELISTED_DAILY_TX_LIMIT,
            requiresWhitelist: false, // Don't require whitelist for this account
            requiresSocialVerification: false,
            minimumVerificationLevel: 1,
            isActive: true
        });

        paymaster.setAccountPolicy(whitelistedAccount, whitelistedPolicy);
        paymaster.setAccountWhitelist(whitelistedAccount, true);

        console.log("Whitelisted account:", whitelistedAccount);
        console.log("  Daily gas limit: 0.2 ETH");
        console.log("  Per-tx gas limit: 0.02 ETH");
        console.log("  Daily tx limit: 100");

        // 10. Set up restricted account for testing
        console.log("\n10. Setting up restricted account for testing...");

        address restrictedAccount = securityTestAccounts[1];

        EIP7702Paymaster.SponsorshipPolicy memory restrictedPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: 0.01 ether, // Very low limit
            perTxGasLimit: 0.001 ether, // Very low per-tx limit
            dailyTxLimit: 5, // Very low tx limit
            requiresWhitelist: true, // Requires whitelist but not whitelisted
            requiresSocialVerification: false,
            minimumVerificationLevel: 1,
            isActive: true
        });

        paymaster.setAccountPolicy(restrictedAccount, restrictedPolicy);
        // Note: Not whitelisting this account to test whitelist requirement

        console.log("Restricted account:", restrictedAccount);
        console.log("  Daily gas limit: 0.01 ETH");
        console.log("  Per-tx gas limit: 0.001 ETH");
        console.log("  Daily tx limit: 5");
        console.log("  Requires whitelist: true (but not whitelisted)");

        vm.stopBroadcast();

        // 11. Save deployment information
        console.log("\n11. Saving deployment information...");

        string memory deploymentInfo = string(
            abi.encodePacked(
                "{\n",
                '  "network": "sepolia",\n',
                '  "chainId": ',
                vm.toString(block.chainid),
                ",\n",
                '  "smartAccount": "',
                vm.toString(address(smartAccountImpl)),
                '",\n',
                '  "paymaster": "',
                vm.toString(address(paymaster)),
                '",\n',
                '  "bundler": "',
                vm.toString(address(bundler)),
                '",\n',
                '  "vault": "',
                vm.toString(address(vault)),
                '",\n',
                '  "usdc": "',
                vm.toString(usdcAddress),
                '",\n'
            )
        );

        // Add test accounts to deployment info
        deploymentInfo = string(
            abi.encodePacked(
                deploymentInfo,
                '  "testAccounts": {\n',
                '    "whitelisted": "',
                vm.toString(securityTestAccounts[0]),
                '",\n',
                '    "restricted": "',
                vm.toString(securityTestAccounts[1]),
                '",\n',
                '    "standard": ["',
                vm.toString(securityTestAccounts[2]),
                '", "',
                vm.toString(securityTestAccounts[3]),
                '", "',
                vm.toString(securityTestAccounts[4]),
                '"]\n',
                "  },\n"
            )
        );

        // Add rate limiting configuration
        deploymentInfo = string(
            abi.encodePacked(
                deploymentInfo,
                '  "rateLimits": {\n',
                '    "standard": {\n',
                '      "dailyGasLimit": "',
                vm.toString(DEFAULT_DAILY_GAS_LIMIT),
                '",\n',
                '      "perTxGasLimit": "',
                vm.toString(DEFAULT_PER_TX_GAS_LIMIT),
                '",\n',
                '      "dailyTxLimit": ',
                vm.toString(DEFAULT_DAILY_TX_LIMIT),
                "\n",
                "    },\n",
                '    "whitelisted": {\n',
                '      "dailyGasLimit": "',
                vm.toString(WHITELISTED_DAILY_GAS_LIMIT),
                '",\n',
                '      "perTxGasLimit": "',
                vm.toString(WHITELISTED_PER_TX_GAS_LIMIT),
                '",\n',
                '      "dailyTxLimit": ',
                vm.toString(WHITELISTED_DAILY_TX_LIMIT),
                "\n",
                "    }\n",
                "  },\n"
            )
        );

        deploymentInfo = string(
            abi.encodePacked(
                deploymentInfo,
                '  "deployer": "',
                vm.toString(deployer),
                '",\n',
                '  "timestamp": ',
                vm.toString(block.timestamp),
                ",\n",
                '  "blockNumber": ',
                vm.toString(block.number),
                "\n",
                "}"
            )
        );

        // Create deployments directory if it doesn't exist
        string[] memory mkdirCmd = new string[](3);
        mkdirCmd[0] = "mkdir";
        mkdirCmd[1] = "-p";
        mkdirCmd[2] = "deployments";
        vm.ffi(mkdirCmd);

        string memory filename = "deployments/sepolia-security-test.json";
        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);

        // 12. Display testing instructions
        console.log("\n=== SEPOLIA SECURITY TESTING SETUP COMPLETE ===");
        console.log("\nContract Addresses:");
        console.log("SmartAccount Implementation:", address(smartAccountImpl));
        console.log("EIP7702Paymaster:", address(paymaster));
        console.log("EIP7702Bundler:", address(bundler));
        console.log("AbunfiVault:", address(vault));
        console.log("Mock USDC:", usdcAddress);

        console.log("\nTest Accounts:");
        console.log("Whitelisted Account:", securityTestAccounts[0]);
        console.log("Restricted Account:", securityTestAccounts[1]);
        console.log("Standard Accounts:", securityTestAccounts[2], securityTestAccounts[3], securityTestAccounts[4]);

        console.log("\nNext Steps:");
        console.log("1. Update frontend .env with these contract addresses");
        console.log("2. Update backend .env with these contract addresses");
        console.log("3. Run security tests using the test accounts");
        console.log("4. Test rate limiting with different account types");
        console.log("5. Verify DOS/Sybil attack prevention mechanisms");
    }
}
