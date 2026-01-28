// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {BridgeTypes} from "../libraries/BridgeTypes.sol";

interface IDestBridge {
    event RelayerUpdated(address indexed oldRelayer, address indexed newRelayer);

    event TokensMinted(address indexed recipient, uint256 amount, uint256 indexed nonce, uint256 sourceChainId);

    /*//////////////////////////////////////////////////////////////
                          BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints bridged tokens after verifying relayer signature
    function mint(BridgeTypes.BridgeMessage calldata message, bytes calldata signature) external;

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function token() external view returns (address);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function relayer() external view returns (address);

    function usedNonces(uint256 nonce) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setRelayer(address newRelayer) external;

    function pause() external;

    function unpause() external;
}
