// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {BridgedToken} from "../src/destination/BridgedToken.sol";
import {DestBridge} from "../src/destination/DestBridge.sol";

contract DeployDest is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address relayer = deployer;

        console.log("Deploying Destination Chain contracts...");
        console.log("Deployer:", deployer);
        console.log("Relayer:", relayer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast();

        BridgedToken bridgedToken = new BridgedToken("Wrapped USDC", "wUSDC");
        console.log("BridgedToken deployed at:", address(bridgedToken));

        DestBridge destBridge = new DestBridge(relayer, deployer);
        console.log("DestBridge deployed at:", address(destBridge));

        bridgedToken.setBridge(address(destBridge));
        console.log("BridgedToken bridge set to:", address(destBridge));

        destBridge.addSourceChain(11155111, address(bridgedToken), address(0xBEEF));
        console.log("Added Sepolia (11155111) as source chain (update bridgeContract after source deploy)");

        vm.stopBroadcast();

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
