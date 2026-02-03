// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC4626} from "../src/mocks/MockERC4626.sol";
import {BridgeBank} from "../src/source/BridgeBank.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract DeploySource is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        console.log("Deploying Source Chain contracts...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast();

        MockERC20 usdc = new MockERC20("Mock USDC", "USDC");
        console.log("MockUSDC deployed at:", address(usdc));

        MockERC4626 vault = new MockERC4626(ERC20(address(usdc)), "Vault USDC", "vUSDC");
        console.log("MockERC4626 Vault deployed at:", address(vault));

        BridgeBank bridgeBank = new BridgeBank(address(vault), deployer);
        console.log("BridgeBank deployed at:", address(bridgeBank));

        bridgeBank.addChain(421614, address(0xDEAD));
        console.log("Added Arbitrum Sepolia (421614) as destination chain");

        vm.stopBroadcast();

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
