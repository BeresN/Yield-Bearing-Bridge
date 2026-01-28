// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test, console} from "forge-std/Test.sol";
import {DestBridge} from "../../src/destination/DestBridge.sol";
import {BridgedToken} from "../../src/destination/BridgedToken.sol";
import {BridgeTypes} from "../../src/libraries/BridgeTypes.sol";
import {SignatureUtils} from "../../src/libraries/SignatureUtils.sol";

/**
 * @title DestBridgeTest
 * @notice Unit tests for DestBridge contract
 */
contract DestBridgeTest is Test {
    DestBridge public destBridge;
    BridgedToken public bridgedToken;

    address constant OWNER = address(1);
    address public relayer;
    uint256 constant RELAYER_PK = 0x12345;
    address constant USER = address(3);
    address constant RECIPIENT = address(4);

    uint256 constant MINT_AMOUNT = 1000e6;
    uint256 constant SOURCE_CHAIN_ID = 1;

    bytes32 public domainSeparator;

    function setUp() public {
        relayer = vm.addr(RELAYER_PK);

        vm.startPrank(OWNER);

        // Deploy BridgedToken
        bridgedToken = new BridgedToken("Bridged USDC", "bUSDC");

        // Deploy DestBridge
        destBridge = new DestBridge(address(bridgedToken), relayer, OWNER);

        // Set bridge on token
        bridgedToken.setBridge(address(destBridge));

        vm.stopPrank();

        // Store domain separator for signing
        domainSeparator = destBridge.DOMAIN_SEPARATOR();

        // Label addresses
        vm.label(address(bridgedToken), "BridgedToken");
        vm.label(address(destBridge), "DestBridge");
        vm.label(OWNER, "Owner");
        vm.label(relayer, "Relayer");
        vm.label(USER, "User");
        vm.label(RECIPIENT, "Recipient");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _createMessage(
        uint256 nonce,
        uint256 deadline
    ) internal view returns (BridgeTypes.BridgeMessage memory) {
        return
            BridgeTypes.BridgeMessage({
                depositor: USER,
                recipient: RECIPIENT,
                amount: MINT_AMOUNT,
                shares: MINT_AMOUNT,
                nonce: nonce,
                sourceChainId: SOURCE_CHAIN_ID,
                destinationChainId: block.chainid,
                deadline: deadline
            });
    }

    function _signMessage(
        BridgeTypes.BridgeMessage memory message,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 digest = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Mint() public {
        BridgeTypes.BridgeMessage memory message = _createMessage(
            1,
            block.timestamp + 1 hours
        );
        bytes memory signature = _signMessage(message, RELAYER_PK);

        vm.expectEmit(true, true, true, true);
        emit BridgeTypes.Minted(RECIPIENT, MINT_AMOUNT, 1, SOURCE_CHAIN_ID);

        destBridge.mint(message, signature);

        assertEq(bridgedToken.balanceOf(RECIPIENT), MINT_AMOUNT);
        assertTrue(destBridge.usedNonces(1));
    }

    function test_MultipleMints() public {
        for (uint256 i = 1; i <= 3; i++) {
            BridgeTypes.BridgeMessage memory message = _createMessage(
                i,
                block.timestamp + 1 hours
            );
            bytes memory signature = _signMessage(message, RELAYER_PK);

            destBridge.mint(message, signature);
        }

        assertEq(bridgedToken.balanceOf(RECIPIENT), MINT_AMOUNT * 3);
    }

    function test_RevertWhen_InvalidSignature() public {
        BridgeTypes.BridgeMessage memory message = _createMessage(
            1,
            block.timestamp + 1 hours
        );

        // Sign with wrong key
        uint256 wrongKey = 0x99999;
        bytes memory signature = _signMessage(message, wrongKey);

        vm.expectRevert(BridgeTypes.InvalidSignature.selector);
        destBridge.mint(message, signature);
    }

    function test_RevertWhen_ExpiredDeadline() public {
        // Create message with past deadline
        BridgeTypes.BridgeMessage memory message = _createMessage(
            1,
            block.timestamp - 1
        );
        bytes memory signature = _signMessage(message, RELAYER_PK);

        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeTypes.SignatureExpired.selector,
                block.timestamp - 1,
                block.timestamp
            )
        );
        destBridge.mint(message, signature);
    }

    function test_RevertWhen_NonceReused() public {
        BridgeTypes.BridgeMessage memory message = _createMessage(
            1,
            block.timestamp + 1 hours
        );
        bytes memory signature = _signMessage(message, RELAYER_PK);

        // First mint succeeds
        destBridge.mint(message, signature);

        // Second mint with same nonce fails
        vm.expectRevert(
            abi.encodeWithSelector(BridgeTypes.NonceAlreadyUsed.selector, 1)
        );
        destBridge.mint(message, signature);
    }

    function test_RevertWhen_WrongChainId() public {
        BridgeTypes.BridgeMessage memory message = BridgeTypes.BridgeMessage({
            depositor: USER,
            recipient: RECIPIENT,
            amount: MINT_AMOUNT,
            shares: MINT_AMOUNT,
            nonce: 1,
            sourceChainId: SOURCE_CHAIN_ID,
            destinationChainId: 999, // Wrong chain
            deadline: block.timestamp + 1 hours
        });
        bytes memory signature = _signMessage(message, RELAYER_PK);

        vm.expectRevert(
            abi.encodeWithSelector(
                BridgeTypes.InvalidChainId.selector,
                block.chainid,
                999
            )
        );
        destBridge.mint(message, signature);
    }

    function test_RevertWhen_Paused() public {
        vm.prank(OWNER);
        destBridge.pause();

        BridgeTypes.BridgeMessage memory message = _createMessage(
            1,
            block.timestamp + 1 hours
        );
        bytes memory signature = _signMessage(message, RELAYER_PK);

        vm.expectRevert();
        destBridge.mint(message, signature);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetRelayer() public {
        address newRelayer = address(0x999);

        vm.prank(OWNER);
        destBridge.setRelayer(newRelayer);

        assertEq(destBridge.relayer(), newRelayer);
    }

    function test_RevertWhen_SetRelayerZeroAddress() public {
        vm.prank(OWNER);
        vm.expectRevert(BridgeTypes.ZeroAddress.selector);
        destBridge.setRelayer(address(0));
    }

    function test_RevertWhen_SetRelayerNonOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        destBridge.setRelayer(address(0x999));
    }

    function test_Pause() public {
        vm.prank(OWNER);
        destBridge.pause();

        // Verify paused
        BridgeTypes.BridgeMessage memory message = _createMessage(
            1,
            block.timestamp + 1 hours
        );
        bytes memory signature = _signMessage(message, RELAYER_PK);

        vm.expectRevert();
        destBridge.mint(message, signature);
    }

    function test_Unpause() public {
        vm.prank(OWNER);
        destBridge.pause();

        vm.prank(OWNER);
        destBridge.unpause();

        // Verify unpaused
        BridgeTypes.BridgeMessage memory message = _createMessage(
            1,
            block.timestamp + 1 hours
        );
        bytes memory signature = _signMessage(message, RELAYER_PK);

        destBridge.mint(message, signature);
        assertEq(bridgedToken.balanceOf(RECIPIENT), MINT_AMOUNT);
    }

    function test_RevertWhen_PauseNonOwner() public {
        vm.prank(USER);
        vm.expectRevert();
        destBridge.pause();
    }
}
