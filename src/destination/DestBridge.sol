// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BridgedToken} from "./BridgedToken.sol";
import {BridgeTypes} from "../libraries/BridgeTypes.sol";
import {SignatureUtils} from "../libraries/SignatureUtils.sol";

/**
 * @notice Destination chain bridge - verifies relayer signatures and mints bridged tokens
 * @dev Uses EIP-712 typed data for signature verification with replay protection.
 *      Supports multiple source chains via registry pattern.
 */
contract DestBridge is Ownable, Pausable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public immutable DOMAIN_SEPARATOR;

    address public relayer;
    mapping(uint256 => bool) public usedNonces;
    mapping(uint256 sourceChainId => BridgeTypes.SourceChainConfig) public sourceChains;

    event RelayerUpdated(address indexed oldRelayer, address indexed newRelayer);
    event TokensMinted(address indexed recipient, uint256 amount, uint256 indexed nonce, uint256 sourceChainId);
    event SourceChainAdded(uint256 indexed chainId, address token, address bridgeContract);
    event SourceChainRemoved(uint256 indexed chainId);

    constructor(address relayer_, address owner_) Ownable(owner_) {
        if (relayer_ == address(0)) revert BridgeTypes.ZeroAddress();

        relayer = relayer_;
        DOMAIN_SEPARATOR = SignatureUtils.computeDomainSeparator(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                          BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mint(BridgeTypes.BridgeMessage calldata message, bytes calldata signature) external whenNotPaused {
        if (message.destinationChainId != block.chainid) {
            revert BridgeTypes.InvalidChainId(block.chainid, message.destinationChainId);
        }

        BridgeTypes.SourceChainConfig storage sourceConfig = sourceChains[message.sourceChainId];
        if (!sourceConfig.enabled) {
            revert BridgeTypes.SourceChainNotSupported(message.sourceChainId);
        }

        SignatureUtils.checkDeadline(message.deadline);

        if (usedNonces[message.nonce]) {
            revert BridgeTypes.NonceAlreadyUsed(message.nonce);
        }

        SignatureUtils.verifyOrRevert(DOMAIN_SEPARATOR, message, signature, relayer);
        usedNonces[message.nonce] = true;
        BridgedToken(sourceConfig.token).mint(message.recipient, message.amount);

        emit TokensMinted(message.recipient, message.amount, message.nonce, message.sourceChainId);
        emit BridgeTypes.Minted(message.recipient, message.amount, message.nonce, message.sourceChainId);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addSourceChain(uint256 chainId, address token, address bridgeContract) external onlyOwner {
        if (token == address(0)) revert BridgeTypes.ZeroAddress();
        if (bridgeContract == address(0)) revert BridgeTypes.ZeroAddress();

        sourceChains[chainId] =
            BridgeTypes.SourceChainConfig({token: token, bridgeContract: bridgeContract, enabled: true});
        emit SourceChainAdded(chainId, token, bridgeContract);
    }

    function removeSourceChain(uint256 chainId) external onlyOwner {
        if (!sourceChains[chainId].enabled) {
            revert BridgeTypes.SourceChainNotSupported(chainId);
        }
        sourceChains[chainId].enabled = false;
        emit SourceChainRemoved(chainId);
    }

    function isSourceChainSupported(uint256 chainId) external view returns (bool) {
        return sourceChains[chainId].enabled;
    }

    function getSourceChainToken(uint256 chainId) external view returns (address) {
        return sourceChains[chainId].token;
    }

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
