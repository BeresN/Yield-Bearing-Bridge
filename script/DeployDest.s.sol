// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {BridgedToken} from "../src/destination/BridgedToken.sol";
import {DestBridge} from "../src/destination/DestBridge.sol";

/**
 * @title DeployDest
 * @notice Deploys destination chain contracts to Arbitrum Sepolia testnet
 * @dev Run with: forge script script/DeployDest.s.sol:DeployDest --rpc-url $ARB_SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployDest is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // The relayer address - this is the account that will sign bridge messages
        // For testing, using the same deployer key. In production, use a separate key.
        address relayer = vm.envOr("RELAYER_ADDRESS", deployer);

        console.log("Deploying Destination Chain contracts...");
        console.log("Deployer:", deployer);
        console.log("Relayer:", relayer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy BridgedToken (wUSDC)
        BridgedToken bridgedToken = new BridgedToken("Wrapped USDC", "wUSDC");
        console.log("BridgedToken deployed at:", address(bridgedToken));

        // 2. Deploy DestBridge
        DestBridge destBridge = new DestBridge(address(bridgedToken), relayer, deployer);
        console.log("DestBridge deployed at:", address(destBridge));

        // 3. Set bridge address on BridgedToken
        bridgedToken.setBridge(address(destBridge));
        console.log("BridgedToken bridge set to:", address(destBridge));

        vm.stopBroadcast();

        // Print summary
        console.log("\n=== DEPLOYMENT SUMMARY (DESTINATION CHAIN - ARB SEPOLIA) ===");
        console.log("BridgedToken:", address(bridgedToken));
        console.log("DestBridge:  ", address(destBridge));
        console.log("Relayer:     ", relayer);
        console.log("Owner:       ", deployer);
        console.log("============================================================\n");

        // Save deployment addresses to file for relayer
        string memory json = string(
            abi.encodePacked(
                '{"chainId":',
                vm.toString(block.chainid),
                ',"bridgedToken":"',
                vm.toString(address(bridgedToken)),
                '","destBridge":"',
                vm.toString(address(destBridge)),
                '","relayer":"',
                vm.toString(relayer),
                '","owner":"',
                vm.toString(deployer),
                '"}'
            )
        );
        vm.writeFile("deployments/arbitrum-sepolia.json", json);
        console.log("Deployment saved to deployments/arbitrum-sepolia.json");
    }
}
