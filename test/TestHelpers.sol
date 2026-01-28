// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {BridgeTypes} from "../src/libraries/BridgeTypes.sol";
import {SignatureUtils} from "../src/libraries/SignatureUtils.sol";

/**
 * @title SigHelper
 * @notice Helper contract for generating EIP-712 signatures in tests
 */
contract SigHelper is Test {
    bytes32 public domainSeparator;

    function setDomainSeparator(address verifyingContract) external {
        domainSeparator = SignatureUtils.computeDomainSeparator(
            verifyingContract
        );
    }

    /// @notice Creates a signed bridge message using a private key
    function signBridgeMessage(
        uint256 privateKey,
        BridgeTypes.BridgeMessage memory message
    ) external view returns (bytes memory signature) {
        bytes32 digest = SignatureUtils.getTypedDataHash(
            domainSeparator,
            message
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    /// @notice Returns the EIP-712 digest for a message
    function getDigest(
        BridgeTypes.BridgeMessage memory message
    ) external view returns (bytes32) {
        return SignatureUtils.getTypedDataHash(domainSeparator, message);
    }
}

/**
 * @title BaseTest
 * @notice Base test contract with common setup and utilities
 */
abstract contract BaseTest is Test {
    // Common addresses
    address constant OWNER = address(1);
    address constant RELAYER = address(2);
    address constant USER = address(3);
    address constant RECIPIENT = address(4);

    // Common amounts
    uint256 constant INITIAL_BALANCE = 1_000_000e6; // 1M USDC
    uint256 constant DEPOSIT_AMOUNT = 1000e6; // 1000 USDC

    // Private keys for signing (derived from addresses)
    uint256 constant RELAYER_PK = 0x2;

    SigHelper public sigHelper;

    function setUp() public virtual {
        sigHelper = new SigHelper();
    }

    /// @notice Labels common addresses for better trace output
    function _labelAddresses() internal {
        vm.label(OWNER, "Owner");
        vm.label(RELAYER, "Relayer");
        vm.label(USER, "User");
        vm.label(RECIPIENT, "Recipient");
    }

    /// @notice Creates a bridge message with common parameters
    function _createBridgeMessage(
        uint256 amount,
        uint256 shares,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (BridgeTypes.BridgeMessage memory) {
        return
            BridgeTypes.BridgeMessage({
                depositor: USER,
                recipient: RECIPIENT,
                amount: amount,
                shares: shares,
                nonce: nonce,
                sourceChainId: 1,
                destinationChainId: block.chainid,
                deadline: deadline
            });
    }
}
