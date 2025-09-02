// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/eip7702/AbunfiSmartAccount.sol";
import "../src/eip7702/EIP7702Paymaster.sol";
import "../src/eip7702/EIP7702Bundler.sol";
import "../src/AbunfiVault.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title DeployEIP7702
 * @dev Deployment script for Abunfi EIP-7702 gasless transaction infrastructure
 */
contract DeployEIP7702 is Script {
    // Configuration
    uint256 public constant INITIAL_PAYMASTER_FUNDING = 5 ether; // 5 ETH for gas sponsorship
    uint256 public constant GLOBAL_DAILY_LIMIT = 10 ether; // 10 ETH daily limit
    uint256 public constant DEFAULT_USER_LIMIT = 0.05 ether; // ~$125 per user daily
    uint256 public constant DEFAULT_TX_LIMIT = 100; // 100 transactions per day

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying EIP-7702 gasless infrastructure...");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Smart Account Implementation
        console.log("\n1. Deploying AbunfiSmartAccount implementation...");
        AbunfiSmartAccount smartAccountImpl = new AbunfiSmartAccount();
        console.log("AbunfiSmartAccount implementation deployed at:", address(smartAccountImpl));

        // 2. Deploy Paymaster
        console.log("\n2. Deploying EIP7702Paymaster...");
        EIP7702Paymaster paymaster = new EIP7702Paymaster();
        console.log("EIP7702Paymaster deployed at:", address(paymaster));

        // 3. Deploy Bundler
        console.log("\n3. Deploying EIP7702Bundler...");
        EIP7702Bundler bundler = new EIP7702Bundler();
        console.log("EIP7702Bundler deployed at:", address(bundler));

        // 4. Deploy or get USDC
        address usdcAddress;
        if (block.chainid == 31337 || block.chainid == 11155111) {
            // Local or Sepolia
            console.log("\n4. Deploying Mock USDC...");
            MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
            usdcAddress = address(mockUSDC);
            console.log("Mock USDC deployed at:", usdcAddress);

            // Mint some USDC for testing
            mockUSDC.mint(deployer, 1000000 * 10 ** 6); // 1M USDC
            console.log("Minted 1M USDC to deployer");
        } else {
            // For testing, we'll deploy mock USDC on all networks
            console.log("\n4. Deploying Mock USDC for testing...");
            MockERC20 mockUSDC = new MockERC20("USD Coin", "USDC", 6);
            usdcAddress = address(mockUSDC);
            console.log("Mock USDC deployed at:", usdcAddress);

            // Mint some USDC for testing
            mockUSDC.mint(deployer, 1000000 * 10 ** 6); // 1M USDC
            console.log("Minted 1M USDC to deployer");
        }

        // 5. Deploy AbunfiVault (no trusted forwarder needed for EIP-7702)
        console.log("\n5. Deploying AbunfiVault...");
        // Deploy risk management contracts first
        address riskProfileManager = address(new MockERC20("Mock Risk Manager", "MRM", 18));
        address withdrawalManager = address(new MockERC20("Mock Withdrawal Manager", "MWM", 18));

        AbunfiVault vault = new AbunfiVault(usdcAddress, address(0), riskProfileManager, withdrawalManager);
        console.log("AbunfiVault deployed at:", address(vault));

        // 6. Configure the system
        console.log("\n6. Configuring EIP-7702 system...");

        // Add bundler as trusted in paymaster
        paymaster.setTrustedBundler(address(bundler), true);
        console.log("Added bundler as trusted in paymaster");

        // Add paymaster to bundler
        bundler.addPaymaster(address(paymaster));
        console.log("Added paymaster to bundler");

        // Set paymaster policies
        EIP7702Paymaster.SponsorshipPolicy memory globalPolicy = EIP7702Paymaster.SponsorshipPolicy({
            dailyGasLimit: GLOBAL_DAILY_LIMIT,
            perTxGasLimit: DEFAULT_USER_LIMIT,
            dailyTxLimit: DEFAULT_TX_LIMIT,
            requiresWhitelist: false,
            isActive: true
        });
        paymaster.setGlobalPolicy(globalPolicy);
        console.log("Set global sponsorship policy");
        console.log("- Daily gas limit:", GLOBAL_DAILY_LIMIT);
        console.log("- Per-tx gas limit:", DEFAULT_USER_LIMIT);
        console.log("- Daily tx limit:", DEFAULT_TX_LIMIT);

        // Fund the paymaster
        if (deployer.balance >= INITIAL_PAYMASTER_FUNDING) {
            payable(address(paymaster)).transfer(INITIAL_PAYMASTER_FUNDING);
            console.log("Funded paymaster with:", INITIAL_PAYMASTER_FUNDING);
        } else {
            console.log("WARNING: Insufficient balance to fund paymaster");
        }

        vm.stopBroadcast();

        // 7. Output deployment summary
        console.log("\n=== EIP-7702 DEPLOYMENT SUMMARY ===");
        console.log("Network:", getNetworkName());
        console.log("Smart Account Implementation:", address(smartAccountImpl));
        console.log("EIP7702Paymaster:", address(paymaster));
        console.log("EIP7702Bundler:", address(bundler));
        console.log("AbunfiVault:", address(vault));
        console.log("USDC Token:", usdcAddress);
        console.log("Paymaster Balance:", address(paymaster).balance);

        // 8. Save deployment addresses (split to avoid stack too deep)
        _saveDeploymentInfo(smartAccountImpl, paymaster, bundler, vault, usdcAddress, deployer);

        // 9. Usage instructions
        console.log("\n=== USAGE INSTRUCTIONS ===");
        console.log("1. Users need to create EIP-7702 delegation transactions:");
        console.log("   - Transaction type: 0x04");
        console.log("   - Authorization list pointing to:", address(smartAccountImpl));
        console.log("");
        console.log("2. After delegation, initialize the account:");
        console.log("   - Call initialize(userAddress, paymasterAddress)");
        console.log("");
        console.log("3. Create and sign user operations for gasless transactions");
        console.log("4. Submit to bundler service for execution");

        // 10. Frontend SDK configuration
        console.log("\n=== FRONTEND SDK CONFIG ===");
        console.log("const config = {");
        console.log("  smartAccountAddress: '", address(smartAccountImpl), "',");
        console.log("  paymasterAddress: '", address(paymaster), "',");
        console.log("  bundlerAddress: '", address(bundler), "',");
        console.log("  vaultAddress: '", address(vault), "',");
        console.log("  usdcAddress: '", usdcAddress, "'");
        console.log("};");

        // 11. Verification commands
        console.log("\n=== VERIFICATION COMMANDS ===");
        if (block.chainid != 31337) {
            // Skip for local network
            console.log("forge verify-contract");
            console.log("Contract addresses:");
            console.log("SmartAccount:", address(smartAccountImpl));
            console.log("Paymaster:", address(paymaster));
            console.log("Bundler:", address(bundler));
            console.log("Vault:", address(vault));
        }

        // 12. Security recommendations
        console.log("\n=== SECURITY RECOMMENDATIONS ===");
        console.log("1. Set up monitoring for paymaster balance");
        console.log("2. Implement rate limiting in bundler service");
        console.log("3. Consider whitelisting for initial launch");
        console.log("4. Monitor for unusual transaction patterns");
        console.log("5. Set up alerts for high gas usage");

        console.log("\n=== DEPLOYMENT COMPLETE ===");
    }

    function getNetworkName() internal view returns (string memory) {
        if (block.chainid == 1) return "mainnet";
        if (block.chainid == 11155111) return "sepolia";
        if (block.chainid == 137) return "polygon";
        if (block.chainid == 80001) return "mumbai";
        if (block.chainid == 42161) return "arbitrum";
        if (block.chainid == 421613) return "arbitrum-goerli";
        if (block.chainid == 10) return "optimism";
        if (block.chainid == 420) return "optimism-goerli";
        if (block.chainid == 31337) return "localhost";
        return "unknown";
    }

    function _saveDeploymentInfo(
        AbunfiSmartAccount smartAccountImpl,
        EIP7702Paymaster paymaster,
        EIP7702Bundler bundler,
        AbunfiVault vault,
        address usdcAddress,
        address deployer
    ) internal {
        string memory deploymentInfo = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                getNetworkName(),
                '",\n',
                '  "chainId": ',
                vm.toString(block.chainid),
                ",\n",
                '  "smartAccountImpl": "',
                vm.toString(address(smartAccountImpl)),
                '",\n',
                '  "paymaster": "',
                vm.toString(address(paymaster)),
                '",\n'
            )
        );

        deploymentInfo = string(
            abi.encodePacked(
                deploymentInfo,
                '  "bundler": "',
                vm.toString(address(bundler)),
                '",\n',
                '  "vault": "',
                vm.toString(address(vault)),
                '",\n',
                '  "usdc": "',
                vm.toString(usdcAddress),
                '",\n',
                '  "deployer": "',
                vm.toString(deployer),
                '",\n',
                '  "timestamp": ',
                vm.toString(block.timestamp),
                "\n",
                "}"
            )
        );

        string memory filename = string(abi.encodePacked("deployments/eip7702-", vm.toString(block.chainid), ".json"));

        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);
    }
}
