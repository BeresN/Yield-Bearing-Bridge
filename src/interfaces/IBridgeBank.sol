// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {BridgeTypes} from "../libraries/BridgeTypes.sol";

interface IBridgeBank {
    /// @notice Deposits tokens to bridge and routes to vault
    function deposit(BridgeTypes.DepositParams calldata params) external returns (uint256 nonce);

    /// @notice Refunds a pending deposit back to the depositor
    function refund(uint256 nonce) external;

    /// @notice Marks a deposit as completed (prevents refund)
    function markCompleted(uint256 nonce) external;

    function depositNonce() external view returns (uint256);

    function getDeposit(uint256 nonce) external view returns (BridgeTypes.DepositRecord memory);

    function getDepositValue(uint256 nonce) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external;

    function unpause() external;
}
