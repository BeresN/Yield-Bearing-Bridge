// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @notice Shared data structures and types for cross-chain bridge operations
 * @dev Defines structs, enums, errors, and events used by both source chain
 *      (BridgeBank) and destination chain (DestBridge) contracts.
 */
library BridgeTypes {
    error ZeroAddress();
    error ZeroAmount();
    error InvalidSignature();
    error SignatureExpired(uint256 deadline, uint256 currentTime);
    error NonceAlreadyUsed(uint256 nonce);
    error UnauthorizedCaller();
    error InvalidChainId(uint256 expected, uint256 actual);
    error VaultDepositFailed();
    error VaultWithdrawFailed();
    error TransferFailed();
    error ChainNotSupported(uint256 chainId);
    error SourceChainNotSupported(uint256 chainId);

    enum DepositStatus {
        Pending,
        Completed,
        Refunded
    }

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct DepositParams {
        address recipient;
        uint256 amount;
        uint256 destinationChainId;
    }

    struct DepositRecord {
        address depositor;
        address recipient;
        uint256 amount;
        uint256 shares;
        uint256 nonce;
        uint256 sourceChainId;
        uint256 destinationChainId;
        uint256 timestamp;
        DepositStatus status;
    }

    struct BridgeMessage {
        address depositor;
        address recipient;
        uint256 amount;
        uint256 shares;
        uint256 nonce;
        uint256 sourceChainId;
        uint256 destinationChainId;
        uint256 deadline;
    }

    struct WithdrawalRequest {
        address owner;
        uint256 amount;
        uint256 sourceChainId;
    }

    struct ChainConfig {
        address remoteContract;
        bool enabled;
    }

    struct SourceChainConfig {
        address token;
        address bridgeContract;
        bool enabled;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposited(
        address indexed depositor,
        address indexed recipient,
        uint256 amount,
        uint256 shares,
        uint256 indexed nonce,
        uint256 destinationChainId
    );

    event Minted(address indexed recipient, uint256 amount, uint256 indexed nonce, uint256 sourceChainId);

    event WithdrawalInitiated(address indexed owner, uint256 amount, uint256 indexed nonce, uint256 sourceChainId);

    event Released(address indexed recipient, uint256 amount, uint256 shares, uint256 indexed nonce);

    event Refunded(address indexed depositor, uint256 amount, uint256 indexed nonce);

    bytes32 public constant BRIDGE_MESSAGE_TYPEHASH = keccak256(
        "BridgeMessage(address depositor,address recipient,uint256 amount,uint256 shares,uint256 nonce,uint256 sourceChainId,uint256 destinationChainId,uint256 deadline)"
    );
}
