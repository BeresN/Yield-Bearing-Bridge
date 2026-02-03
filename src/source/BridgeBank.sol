// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {VaultAdapter} from "./VaultAdapter.sol";
import {BridgeTypes} from "../libraries/BridgeTypes.sol";

/**
 * @title BridgeBank
 * @notice Source chain bridge - accepts deposits and routes to ERC-4626 vault
 * @dev Emits Deposited events for off-chain relayer to process
 */
contract BridgeBank is VaultAdapter, Ownable, Pausable {
    using SafeTransferLib for ERC20;

    error SlipageTooHigh();

    uint256 public depositNonce;
    mapping(uint256 => BridgeTypes.DepositRecord) public deposits;
    mapping(uint256 chainId => BridgeTypes.ChainConfig) public supportedChains;

    event ChainAdded(uint256 indexed chainId, address remoteContract);
    event ChainRemoved(uint256 indexed chainId);

    constructor(address vault_, address owner_) VaultAdapter(vault_) Ownable(owner_) {}

    /*//////////////////////////////////////////////////////////////
                          BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(BridgeTypes.DepositParams calldata params) external whenNotPaused returns (uint256 nonce) {
        if (params.recipient == address(0)) revert BridgeTypes.ZeroAddress();
        if (params.amount == 0) revert BridgeTypes.ZeroAmount();
        if (!supportedChains[params.destinationChainId].enabled) {
            revert BridgeTypes.ChainNotSupported(params.destinationChainId);
        }

        depositToken.safeTransferFrom(msg.sender, address(this), params.amount);

        uint256 shares = _depositToVault(params.amount);

        nonce = ++depositNonce;
        deposits[nonce] = BridgeTypes.DepositRecord({
            depositor: msg.sender,
            recipient: params.recipient,
            amount: params.amount,
            shares: shares,
            nonce: nonce,
            sourceChainId: block.chainid,
            destinationChainId: params.destinationChainId,
            timestamp: block.timestamp,
            status: BridgeTypes.DepositStatus.Pending
        });

        emit BridgeTypes.Deposited(
            msg.sender, params.recipient, params.amount, shares, nonce, params.destinationChainId
        );
    }

    function refund(uint256 nonce, uint256 minAmount) external onlyOwner {
        BridgeTypes.DepositRecord storage record = deposits[nonce];

        if (record.status != BridgeTypes.DepositStatus.Pending) {
            revert BridgeTypes.NonceAlreadyUsed(nonce);
        }

        record.status = BridgeTypes.DepositStatus.Refunded;

        uint256 assets = _redeemFromVault(record.shares, record.depositor);
        if (assets < minAmount) {
            revert SlipageTooHigh();
        }
        emit BridgeTypes.Refunded(record.depositor, assets, nonce);
    }

    function markCompleted(uint256 nonce) external onlyOwner {
        BridgeTypes.DepositRecord storage record = deposits[nonce];

        if (record.status != BridgeTypes.DepositStatus.Pending) {
            revert BridgeTypes.NonceAlreadyUsed(nonce);
        }

        record.status = BridgeTypes.DepositStatus.Completed;
    }

    function getDeposit(uint256 nonce) external view returns (BridgeTypes.DepositRecord memory) {
        return deposits[nonce];
    }

    function getDepositValue(uint256 nonce) external view returns (uint256) {
        return _getShareValue(deposits[nonce].shares);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addChain(uint256 chainId, address remoteContract) external onlyOwner {
        if (remoteContract == address(0)) revert BridgeTypes.ZeroAddress();
        supportedChains[chainId] = BridgeTypes.ChainConfig({remoteContract: remoteContract, enabled: true});
        emit ChainAdded(chainId, remoteContract);
    }

    function removeChain(uint256 chainId) external onlyOwner {
        if (!supportedChains[chainId].enabled) {
            revert BridgeTypes.ChainNotSupported(chainId);
        }
        supportedChains[chainId].enabled = false;
        emit ChainRemoved(chainId);
    }

    function isChainSupported(uint256 chainId) external view returns (bool) {
        return supportedChains[chainId].enabled;
    }

    function getRemoteContract(uint256 chainId) external view returns (address) {
        return supportedChains[chainId].remoteContract;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
