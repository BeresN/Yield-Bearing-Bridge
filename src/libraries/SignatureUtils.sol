// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeTypes} from "./BridgeTypes.sol";

/**
 * @title SignatureUtils
 * @notice EIP-712 signature utilities for cross-chain bridge message verification
 * @dev Provides domain separator construction, struct hashing, and signature recovery
 */
library SignatureUtils {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    string private constant NAME = "YieldBearingBridge";
    string private constant VERSION = "1";

    /*//////////////////////////////////////////////////////////////
                           DOMAIN SEPARATOR
    //////////////////////////////////////////////////////////////*/

    /// @dev Computes the EIP-712 domain separator for a given contract address
    function computeDomainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes(NAME)),
                keccak256(bytes(VERSION)),
                block.chainid,
                verifyingContract
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                            STRUCT HASHING
    //////////////////////////////////////////////////////////////*/

    /// @dev Computes the EIP-712 struct hash for a BridgeMessage
    function hashBridgeMessage(BridgeTypes.BridgeMessage memory message) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                BridgeTypes.BRIDGE_MESSAGE_TYPEHASH,
                message.depositor,
                message.recipient,
                message.amount,
                message.shares,
                message.nonce,
                message.sourceChainId,
                message.destinationChainId,
                message.deadline
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                          DIGEST COMPUTATION
    //////////////////////////////////////////////////////////////*/

    /// @dev Computes the final EIP-712 digest to be signed
    function getTypedDataHash(bytes32 domainSeparator, BridgeTypes.BridgeMessage memory message)
        internal
        pure
        returns (bytes32)
    {
        bytes1 prefix = bytes1(0x19);
        bytes1 eip712Version = bytes1(0x01); // EIP-712 is version 1 of EIP-191
        return keccak256(abi.encodePacked(prefix, eip712Version, domainSeparator, hashBridgeMessage(message)));
    }

    /*//////////////////////////////////////////////////////////////
                         SIGNATURE RECOVERY
    //////////////////////////////////////////////////////////////*/

    /// @dev Recovers signer address from signature components (v, r, s)
    function recoverSigner(bytes32 digest, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) {
            revert BridgeTypes.InvalidSignature();
        }
        return signer;
    }

    /// @dev Recovers signer from packed signature bytes (65 bytes: r + s + v)
    function recoverSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) {
            revert BridgeTypes.InvalidSignature();
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // EIP-2 compatibility
        if (v < 27) {
            v += 27;
        }

        return recoverSigner(digest, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                            VERIFICATION
    //////////////////////////////////////////////////////////////*/

    /// @dev Verifies that a message was signed by the expected signer
    function verify(
        bytes32 domainSeparator,
        BridgeTypes.BridgeMessage memory message,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool) {
        bytes32 digest = getTypedDataHash(domainSeparator, message);
        address recoveredSigner = recoverSigner(digest, signature);
        return recoveredSigner == expectedSigner;
    }

    /// @dev Verifies signature and reverts if invalid or signer mismatch
    function verifyOrRevert(
        bytes32 domainSeparator,
        BridgeTypes.BridgeMessage memory message,
        bytes memory signature,
        address expectedSigner
    ) internal pure {
        if (!verify(domainSeparator, message, signature, expectedSigner)) {
            revert BridgeTypes.InvalidSignature();
        }
    }

    /// @dev Checks if signature deadline has passed
    function checkDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) {
            revert BridgeTypes.SignatureExpired(deadline, block.timestamp);
        }
    }
}
