// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BridgedToken} from "./BridgedToken.sol";
import {BridgeTypes} from "../libraries/BridgeTypes.sol";
import {SignatureUtils} from "../libraries/SignatureUtils.sol";

/**
 * @title DestBridge
 * @notice Destination chain bridge - verifies relayer signatures and mints bridged tokens
 * @dev Uses EIP-712 typed data for signature verification with replay protection
 */
contract DestBridge is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    BridgedToken public immutable token;
    bytes32 public immutable DOMAIN_SEPARATOR;

    address public relayer;
    mapping(uint256 => bool) public usedNonces;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event RelayerUpdated(address indexed oldRelayer, address indexed newRelayer);
    event TokensMinted(address indexed recipient, uint256 amount, uint256 indexed nonce, uint256 sourceChainId);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address token_, address relayer_, address owner_) Ownable(owner_) {
        if (token_ == address(0)) revert BridgeTypes.ZeroAddress();
        if (relayer_ == address(0)) revert BridgeTypes.ZeroAddress();

        token = BridgedToken(token_);
        relayer = relayer_;
        DOMAIN_SEPARATOR = SignatureUtils.computeDomainSeparator(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints bridged tokens after verifying relayer signature
    function mint(BridgeTypes.BridgeMessage calldata message, bytes calldata signature) external whenNotPaused {
        // Validate chain ID
        if (message.destinationChainId != block.chainid) {
            revert BridgeTypes.InvalidChainId(block.chainid, message.destinationChainId);
        }

        // Check deadline
        SignatureUtils.checkDeadline(message.deadline);

        // Check nonce hasn't been used (replay protection)
        if (usedNonces[message.nonce]) {
            revert BridgeTypes.NonceAlreadyUsed(message.nonce);
        }

        // Verify signature
        SignatureUtils.verifyOrRevert(DOMAIN_SEPARATOR, message, signature, relayer);

        // Mark nonce as used
        usedNonces[message.nonce] = true;

        // Mint tokens to recipient
        token.mint(message.recipient, message.amount);

        emit TokensMinted(message.recipient, message.amount, message.nonce, message.sourceChainId);

        emit BridgeTypes.Minted(message.recipient, message.amount, message.nonce, message.sourceChainId);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setRelayer(address newRelayer) external onlyOwner {
        if (newRelayer == address(0)) revert BridgeTypes.ZeroAddress();
        address oldRelayer = relayer;
        relayer = newRelayer;
        emit RelayerUpdated(oldRelayer, newRelayer);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
