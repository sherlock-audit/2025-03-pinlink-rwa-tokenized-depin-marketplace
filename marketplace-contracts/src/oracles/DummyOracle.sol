// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {IPinlinkOracle} from "src/oracles/IPinlinkOracle.sol";
import {ERC165, IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

/// @title Dummy Centralized Oracle for PIN/USD price
/// @notice Only sepolia testing purposes
contract DummyOracle is IPinlinkOracle, ERC165 {
    /// @notice The address of the token that this oracle is providing the price for
    address public immutable TOKEN;

    /// @notice TOKEN has 18 decimals
    uint256 public constant SCALE = 1e18;

    /// @notice The price of TOKEN in USD terms (18 decimals). [USD/TOKEN] = how many usd for 1 TOKEN
    /// @dev visibility is internal, so that the price is only accessed through the interface functions
    uint256 internal _tokenPriceInUsd;

    ////////////////////// ERRORS ///////////////////////
    error PinlinkCentralizedOracle__InvalidPrice();

    /////////////////////////////////////////////////////
    constructor(address token_, uint256 initialPriceInUsd_) {
        TOKEN = token_;
        _tokenPriceInUsd = initialPriceInUsd_;
        emit PriceUpdated(initialPriceInUsd_);
    }

    /////////////// MUTATIVE FUNCTIONS //////////////////

    /// @notice Update the price of TOKEN in USD terms
    /// @dev The price should be expressed with 18 decimals.
    /// @dev Example. To set the TOKEN price to 0.88 USD, the input should be 880000000000000000
    function updateTokenPrice(uint256 usdPerToken) external {
        _tokenPriceInUsd = usdPerToken;
        emit PriceUpdated(usdPerToken);
    }

    ///////////////// VIEW FUNCTIONS ////////////////////

    /// @notice Convert a given amount of TOKEN to USD
    /// @dev The output will be with 18 decimals as well
    function convertToUsd(address token, uint256 tokenAmountIn) external view returns (uint256 usdAmount) {
        if (token != TOKEN) revert PinlinkCentralizedOracle__InvalidToken();
        // TOKEN[18] * price[USD/TOKEN][18] / PIN_DECIMALS[18] = USD[18]
        return (tokenAmountIn * _tokenPriceInUsd) / SCALE;
    }

    /// @notice Convert a given amount of USD to TOKEN
    /// @dev The output will be with 18 decimals as well
    function convertFromUsd(address toToken, uint256 usdAmount) external view returns (uint256 tokenAmount) {
        if (toToken != TOKEN) revert PinlinkCentralizedOracle__InvalidToken();
        // USD[18] * PIN_DECIMALS[18] / price[USD/TOKEN][18] = TOKEN[18]
        return (usdAmount * SCALE) / _tokenPriceInUsd;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IPinlinkOracle).interfaceId || super.supportsInterface(interfaceId);
    }
}
