// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MockERC4626
/// @notice A mock ERC4626 vault for testnet yield simulation
/// @dev Includes simulateYield() to programmatically increase share price for demos
contract MockERC4626 is ERC4626 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public simulatedYield;
    address public owner;

    error OnlyOwner();
    error ZeroYieldAmount();
    event YieldSimulated(uint256 amount, uint256 newTotalAssets);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC4626(asset_) ERC20(name_, symbol_) {
        owner = msg.sender;
    }

    /// @notice Simulates yield accrual by increasing the vault's perceived assets
    /// @dev This artificially increases the share price for testing purposes
    /// @param amount The amount of yield to simulate (in asset terms)
    function simulateYield(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroYieldAmount();

        simulatedYield += amount;

        emit YieldSimulated(amount, totalAssets());
    }

    function transferOwnership(address newOwner) external onlyOwner {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /// @notice Resets the simulated yield to zero
    function resetSimulatedYield() external onlyOwner {
        simulatedYield = 0;
        emit YieldSimulated(0, totalAssets());
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + simulatedYield;
    }

    /// @notice Returns decimals matching the underlying asset
    function decimals() public view override returns (uint8) {
        return ERC4626.decimals();
    }

    /// @notice Returns the current share price in asset terms
    /// @dev Useful for tracking yield simulation effects
    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return 10 ** decimals();
        }
        return totalAssets().mulDiv(10 ** decimals(), supply);
    }

    /// @notice Returns the current yield rate as basis points
    /// @dev (simulatedYield * 10000) / (totalAssets - simulatedYield)
    /// @return The yield rate in basis points (100 = 1%)
    function currentYieldBps() external view returns (uint256) {
        uint256 realAssets = IERC20(asset()).balanceOf(address(this));
        if (realAssets == 0) return 0;
        return (simulatedYield * 10000) / realAssets;
    }
}
