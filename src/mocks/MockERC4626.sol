// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/**
 * @title MockERC4626
 * @notice Mock ERC-4626 vault for testnet yield simulation
 * @dev Includes simulateYield() to programmatically increase share price for demos
 */
contract MockERC4626 is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyOwner();
    error ZeroYieldAmount();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event YieldSimulated(uint256 amount, uint256 newTotalAssets);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public simulatedYield;
    address public owner;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(ERC20 asset_, string memory name_, string memory symbol_) ERC4626(asset_, name_, symbol_) {
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                          YIELD SIMULATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Simulates yield accrual by increasing the vault's perceived assets
    function simulateYield(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroYieldAmount();
        simulatedYield += amount;
        emit YieldSimulated(amount, totalAssets());
    }

    /// @notice Resets the simulated yield to zero
    function resetSimulatedYield() external onlyOwner {
        simulatedYield = 0;
        emit YieldSimulated(0, totalAssets());
    }

    /*//////////////////////////////////////////////////////////////
                              OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    function transferOwnership(address newOwner) external onlyOwner {
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) + simulatedYield;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current share price in asset terms (1e18 = 1:1)
    function sharePrice() external view returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) {
            return 10 ** decimals;
        }
        return (totalAssets() * 10 ** decimals) / supply;
    }

    /// @notice Returns the current yield rate in basis points (100 = 1%)
    function currentYieldBps() external view returns (uint256) {
        uint256 realAssets = asset.balanceOf(address(this));
        if (realAssets == 0) return 0;
        return (simulatedYield * 10000) / realAssets;
    }
}
