// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {BridgeBank} from "../src/source/BridgeBank.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/**
 * @title DeploySource
 * @notice Deploys source chain contracts to Sepolia testnet
 * @dev Run with: forge script script/DeploySource.s.sol:DeploySource --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeploySource is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Source Chain contracts...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Mock USDC
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC");
        console.log("MockUSDC deployed at:", address(usdc));

        // 2. Deploy Mock ERC4626 Vault
        MockERC4626 vault = new MockERC4626(ERC20(address(usdc)), "Vault USDC", "vUSDC");
        console.log("MockERC4626 Vault deployed at:", address(vault));

        // 3. Deploy BridgeBank (owner = deployer)
        BridgeBank bridgeBank = new BridgeBank(address(vault), deployer);
        console.log("BridgeBank deployed at:", address(bridgeBank));

        vm.stopBroadcast();

        // Print summary
        console.log("\n=== DEPLOYMENT SUMMARY (SOURCE CHAIN - SEPOLIA) ===");
        console.log("MockUSDC:    ", address(usdc));
        console.log("Vault:       ", address(vault));
        console.log("BridgeBank:  ", address(bridgeBank));
        console.log("Owner:       ", deployer);
        console.log("================================================\n");

        // Save deployment addresses to file for relayer
        string memory json = string(
            abi.encodePacked(
                '{"chainId":',
                vm.toString(block.chainid),
                ',"usdc":"',
                vm.toString(address(usdc)),
                '","vault":"',
                vm.toString(address(vault)),
                '","bridgeBank":"',
                vm.toString(address(bridgeBank)),
                '","owner":"',
                vm.toString(deployer),
                '"}'
            )
        );
        vm.writeFile("deployments/sepolia.json", json);
        console.log("Deployment saved to deployments/sepolia.json");
    }
}
