// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {BridgeTypes} from "../libraries/BridgeTypes.sol";

/**
 * @notice Abstract adapter for standardizing ERC-4626 vault interactions
 */
abstract contract VaultAdapter {
    using SafeTransferLib for ERC20;

    ERC4626 public immutable vault;
    ERC20 public immutable depositToken;

    constructor(address vault_) {
        if (vault_ == address(0)) revert BridgeTypes.ZeroAddress();
        vault = ERC4626(vault_);
        depositToken = ERC20(address(vault.asset()));
    }

    function _depositToVault(uint256 assets) internal returns (uint256 shares) {
        depositToken.safeApprove(address(vault), assets);
        shares = vault.deposit(assets, address(this));

        if (shares == 0) revert BridgeTypes.VaultDepositFailed();
    }

    function _redeemFromVault(uint256 shares, address receiver) internal returns (uint256 assets) {
        assets = vault.redeem(shares, receiver, address(this));

        if (assets == 0) revert BridgeTypes.VaultWithdrawFailed();
    }

    function _getShareValue(uint256 shares) internal view returns (uint256 assets) {
        return vault.convertToAssets(shares);
    }

    function _getSharesForAssets(uint256 assets) internal view returns (uint256 shares) {
        return vault.convertToShares(assets);
    }

    function totalVaultAssets() public view returns (uint256) {
        uint256 shares = vault.balanceOf(address(this));
        return vault.convertToAssets(shares);
    }

    function totalVaultShares() public view returns (uint256) {
        return vault.balanceOf(address(this));
    }
}
