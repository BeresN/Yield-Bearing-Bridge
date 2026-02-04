// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @notice A mock USDC token for testnet simulation with a public faucet
/// @dev Implements ERC20 with permit extension for gasless approvals
contract MockERC20 is ERC20, ERC20Permit {
    uint256 public constant FAUCET_AMOUNT = 1000e6;
    uint256 public constant FAUCET_COOLDOWN = 1 hours;

    mapping(address => uint256) public lastFaucetClaim;

    error FaucetCooldownActive(uint256 remainingTime);

    event FaucetClaimed(address indexed claimer, uint256 amount);

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC20Permit(name_) {}

    /// @notice Public faucet to claim test tokens
    /// @dev Enforces a cooldown period between claims
    function faucet() external {
        uint256 lastClaim = lastFaucetClaim[msg.sender];

        if (lastClaim != 0) {
            uint256 timeSinceLastClaim = block.timestamp - lastClaim;
            if (timeSinceLastClaim < FAUCET_COOLDOWN) {
                revert FaucetCooldownActive(FAUCET_COOLDOWN - timeSinceLastClaim);
            }
        }

        lastFaucetClaim[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);

        emit FaucetClaimed(msg.sender, FAUCET_AMOUNT);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Returns the number of decimals (6 for USDC compatibility)
    /// @return The number of decimals
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
