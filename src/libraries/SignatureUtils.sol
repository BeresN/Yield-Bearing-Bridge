// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {BridgeTypes} from "./BridgeTypes.sol";

/**
 * @title SignatureUtils
 * @notice EIP-712 signature utilities for cross-chain bridge message verification
 * @dev Uses OpenZeppelin's ECDSA library for signature recovery with built-in malleability protection
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

    function getTypedDataHash(bytes32 domainSeparator, BridgeTypes.BridgeMessage memory message)
        internal
        pure
        returns (bytes32)
    {
        return MessageHashUtils.toTypedDataHash(domainSeparator, hashBridgeMessage(message));
    }

    /*//////////////////////////////////////////////////////////////
                         SIGNATURE RECOVERY
    //////////////////////////////////////////////////////////////*/

    /// @dev Recovers signer using OpenZeppelin ECDSA (includes malleability protection)
    function recoverSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
        (address signer, ECDSA.RecoverError error,) = ECDSA.tryRecover(digest, signature);

        if (error != ECDSA.RecoverError.NoError) {
            revert BridgeTypes.InvalidSignature();
        }

        return signer;
    }

    /*//////////////////////////////////////////////////////////////
                            VERIFICATION
    //////////////////////////////////////////////////////////////*/

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

    function checkDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) {
            revert BridgeTypes.SignatureExpired(deadline, block.timestamp);
        }
    }
}
