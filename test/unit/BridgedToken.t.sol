// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {BridgedToken} from "../../src/destination/BridgedToken.sol";

/**
 * @title BridgedTokenTest
 * @notice Unit tests for BridgedToken contract
 */
contract BridgedTokenTest is Test {
    BridgedToken public token;

    address constant OWNER = address(1);
    address constant BRIDGE = address(2);
    address constant USER = address(3);

    uint256 constant MINT_AMOUNT = 1000e18;

    function setUp() public {
        vm.prank(OWNER);
        token = new BridgedToken("Bridged USDC", "bUSDC");

        vm.prank(OWNER);
        token.setBridge(BRIDGE);

        vm.label(address(token), "BridgedToken");
        vm.label(OWNER, "Owner");
        vm.label(BRIDGE, "Bridge");
        vm.label(USER, "User");
    }

    /*//////////////////////////////////////////////////////////////
                            MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint() public {
        vm.prank(BRIDGE);
        token.mint(USER, MINT_AMOUNT);

        assertEq(token.balanceOf(USER), MINT_AMOUNT);
        assertEq(token.totalSupply(), MINT_AMOUNT);
    }

    function test_MintMultiple() public {
        vm.startPrank(BRIDGE);
        token.mint(USER, MINT_AMOUNT);
        token.mint(USER, MINT_AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(USER), MINT_AMOUNT * 2);
    }

    function test_RevertWhen_NonBridgeMints() public {
        vm.prank(USER);
        vm.expectRevert(BridgedToken.OnlyBridge.selector);
        token.mint(USER, MINT_AMOUNT);
    }

    function test_RevertWhen_OwnerMints() public {
        vm.prank(OWNER);
        vm.expectRevert(BridgedToken.OnlyBridge.selector);
        token.mint(USER, MINT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            BURN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Burn() public {
        vm.prank(BRIDGE);
        token.mint(USER, MINT_AMOUNT);

        vm.prank(BRIDGE);
        token.burn(USER, MINT_AMOUNT / 2);

        assertEq(token.balanceOf(USER), MINT_AMOUNT / 2);
    }

    function test_RevertWhen_NonBridgeBurns() public {
        vm.prank(BRIDGE);
        token.mint(USER, MINT_AMOUNT);

        vm.prank(USER);
        vm.expectRevert(BridgedToken.OnlyBridge.selector);
        token.burn(USER, MINT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                          SET BRIDGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetBridge() public {
        address newBridge = address(0x999);

        vm.prank(OWNER);
        token.setBridge(newBridge);

        assertEq(token.bridge(), newBridge);
    }

    function test_SetBridgeEmitsEvent() public {
        address newBridge = address(0x999);

        vm.expectEmit(true, true, false, false);
        emit BridgedToken.BridgeUpdated(BRIDGE, newBridge);

        vm.prank(OWNER);
        token.setBridge(newBridge);
    }

    function test_RevertWhen_SetBridgeZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(BridgedToken.ZeroAddress.selector);
        token.setBridge(address(0));
    }

    function test_RevertWhen_SetBridgeNonOwner() public {
        vm.prank(USER);
        vm.expectRevert(BridgedToken.OnlyBridge.selector);
        token.setBridge(address(0x999));
    }

    /*//////////////////////////////////////////////////////////////
                      TRANSFER OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferOwnership() public {
        address newOwner = address(0x888);

        vm.prank(OWNER);
        token.transferOwnership(newOwner);

        assertEq(token.owner(), newOwner);
    }

    function test_RevertWhen_TransferOwnershipZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(BridgedToken.ZeroAddress.selector);
        token.transferOwnership(address(0));
    }

    function test_RevertWhen_TransferOwnershipNonOwner() public {
        vm.prank(USER);
        vm.expectRevert(BridgedToken.OnlyBridge.selector);
        token.transferOwnership(address(0x888));
    }

    function test_NewOwnerCanSetBridge() public {
        address newOwner = address(0x888);

        vm.prank(OWNER);
        token.transferOwnership(newOwner);

        address newBridge = address(0x777);
        vm.prank(newOwner);
        token.setBridge(newBridge);

        assertEq(token.bridge(), newBridge);
    }

    /*//////////////////////////////////////////////////////////////
                          ERC20 STANDARD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer() public {
        vm.prank(BRIDGE);
        token.mint(USER, MINT_AMOUNT);

        address recipient = address(0x555);
        vm.prank(USER);
        token.transfer(recipient, MINT_AMOUNT / 2);

        assertEq(token.balanceOf(USER), MINT_AMOUNT / 2);
        assertEq(token.balanceOf(recipient), MINT_AMOUNT / 2);
    }

    function test_Approve() public {
        vm.prank(BRIDGE);
        token.mint(USER, MINT_AMOUNT);

        address spender = address(0x666);
        vm.prank(USER);
        token.approve(spender, MINT_AMOUNT);

        assertEq(token.allowance(USER, spender), MINT_AMOUNT);
    }

    function test_TransferFrom() public {
        vm.prank(BRIDGE);
        token.mint(USER, MINT_AMOUNT);

        address spender = address(0x666);
        address recipient = address(0x555);

        vm.prank(USER);
        token.approve(spender, MINT_AMOUNT);

        vm.prank(spender);
        token.transferFrom(USER, recipient, MINT_AMOUNT);

        assertEq(token.balanceOf(recipient), MINT_AMOUNT);
        assertEq(token.balanceOf(USER), 0);
    }
}
