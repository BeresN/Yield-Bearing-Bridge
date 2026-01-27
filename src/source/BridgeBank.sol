// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public depositNonce;
    mapping(uint256 => BridgeTypes.DepositRecord) public deposits;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address vault_, address owner_) VaultAdapter(vault_) Ownable(owner_) {}

    /*//////////////////////////////////////////////////////////////
                          DEPOSIT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits tokens to bridge and routes to vault
    function deposit(BridgeTypes.DepositParams calldata params) external whenNotPaused returns (uint256 nonce) {
        if (params.recipient == address(0)) revert BridgeTypes.ZeroAddress();
        if (params.amount == 0) revert BridgeTypes.ZeroAmount();

        // Transfer tokens from depositor
        depositToken.safeTransferFrom(msg.sender, address(this), params.amount);

        // Deposit to vault and get shares
        uint256 shares = _depositToVault(params.amount);

        // Create deposit record
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

    /*//////////////////////////////////////////////////////////////
                          REFUND FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Refunds a pending deposit back to the depositor
    function refund(uint256 nonce) external onlyOwner {
        BridgeTypes.DepositRecord storage record = deposits[nonce];

        if (record.status != BridgeTypes.DepositStatus.Pending) {
            revert BridgeTypes.NonceAlreadyUsed(nonce);
        }

        // Update status
        record.status = BridgeTypes.DepositStatus.Refunded;

        // Redeem shares and send assets to depositor
        uint256 assets = _redeemFromVault(record.shares, record.depositor);

        emit BridgeTypes.Refunded(record.depositor, assets, nonce);
    }

    /// @notice Called by relayer to mark deposit as completed (prevents refund)
    function markCompleted(uint256 nonce) external onlyOwner {
        BridgeTypes.DepositRecord storage record = deposits[nonce];

        if (record.status != BridgeTypes.DepositStatus.Pending) {
            revert BridgeTypes.NonceAlreadyUsed(nonce);
        }

        record.status = BridgeTypes.DepositStatus.Completed;
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets deposit details by nonce
    function getDeposit(uint256 nonce) external view returns (BridgeTypes.DepositRecord memory) {
        return deposits[nonce];
    }

    /// @notice Gets current value of a deposit's shares in the vault
    function getDepositValue(uint256 nonce) external view returns (uint256) {
        return _getShareValue(deposits[nonce].shares);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
