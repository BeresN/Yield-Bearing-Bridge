// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title BridgedToken
 * @notice Wrapped token (wUSDC) minted on destination chain by DestBridge
 * @dev Only the bridge contract can mint and burn tokens
 */
contract BridgedToken is ERC20 {
    error OnlyBridge();
    error ZeroAddress();

    event BridgeUpdated(address indexed oldBridge, address indexed newBridge);

    address public bridge;
    address public owner;

    modifier onlyBridge() {
        if (msg.sender != bridge) revert OnlyBridge();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyBridge();
        _;
    }

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                          BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external onlyBridge {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyBridge {
        _burn(from, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setBridge(address newBridge) external onlyOwner {
        if (newBridge == address(0)) revert ZeroAddress();
        address oldBridge = bridge;
        bridge = newBridge;
        emit BridgeUpdated(oldBridge, newBridge);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
}
