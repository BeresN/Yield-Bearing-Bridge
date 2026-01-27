// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {BridgeTypes} from "../libraries/BridgeTypes.sol";

/**
 * @title VaultAdapter
 * @notice Abstract adapter for standardizing ERC-4626 vault interactions
 * @dev Inherited by BridgeBank to handle vault deposits and redemptions
 */
abstract contract VaultAdapter {
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    ERC4626 public immutable vault;
    ERC20 public immutable depositToken;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address vault_) {
        if (vault_ == address(0)) revert BridgeTypes.ZeroAddress();
        vault = ERC4626(vault_);
        depositToken = ERC20(address(vault.asset()));
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL VAULT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Deposits assets into vault and returns shares received
    function _depositToVault(uint256 assets) internal returns (uint256 shares) {
        depositToken.safeApprove(address(vault), assets);
        shares = vault.deposit(assets, address(this));
        
        if (shares == 0) revert BridgeTypes.VaultDepositFailed();
    }

    /// @dev Redeems shares from vault and returns assets received
    function _redeemFromVault(uint256 shares, address receiver) internal returns (uint256 assets) {
        assets = vault.redeem(shares, receiver, address(this));
        
        if (assets == 0) revert BridgeTypes.VaultWithdrawFailed();
    }

    /// @dev Converts shares to their current asset value
    function _getShareValue(uint256 shares) internal view returns (uint256 assets) {
        return vault.convertToAssets(shares);
    }

    /// @dev Converts assets to their share equivalent
    function _getSharesForAssets(uint256 assets) internal view returns (uint256 shares) {
        return vault.convertToShares(assets);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns total assets held by this contract in the vault
    function totalVaultAssets() public view returns (uint256) {
        uint256 shares = vault.balanceOf(address(this));
        return vault.convertToAssets(shares);
    }

    /// @notice Returns total shares this contract owns in the vault
    function totalVaultShares() public view returns (uint256) {
        return vault.balanceOf(address(this));
    }
}
