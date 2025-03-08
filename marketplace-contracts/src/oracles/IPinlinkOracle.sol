// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

/// @title Pinlink Oracles Interface
/// @notice Interface for oracles to integrate with the PinlinkShop
interface IPinlinkOracle is IERC165 {
    ////////////////////// EVENTS ///////////////////////

    event PriceUpdated(uint256 indexed usdPerToken);

    ////////////////////// ERRORS ///////////////////////

    error PinlinkCentralizedOracle__InvalidToken();

    /// @notice Converts an amount of a token to USD (18 decimals)
    /// @dev If the price is stale, it should NOT revert, but return 0.
    function convertToUsd(address _token, uint256 _amount) external view returns (uint256);

    /// @notice Converts an amount of USD (18 decimals) to a token amount
    /// @dev If the price is stale, it should NOT revert, but return 0.
    function convertFromUsd(address _token, uint256 _usdAmount) external view returns (uint256);
}
