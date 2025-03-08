// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IPinlinkOracle} from "src/oracles/IPinlinkOracle.sol";
import {ERC165, IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";

/// @title Centralized Oracle for PIN/USD price
/// @notice This contract is used to get the price of PIN in USD terms
/// @dev The price is updated regularly by the owner of the contract
contract CentralizedOracle is IPinlinkOracle, ERC165, Ownable {
    /// @notice The address of the token that this oracle is providing the price for
    address public immutable TOKEN;

    /// @notice TOKEN has 18 decimals
    uint256 public constant SCALE = 1e18;

    /// @notice The maximum time that can pass since the last price update
    uint256 public constant STALENESS_THRESHOLD = 7 days;

    /// @notice Last time the price was updated
    uint256 public lastPriceUpdateTimestamp;

    /// @notice The price of TOKEN in USD terms (18 decimals). [USD/TOKEN] = how many usd for 1 TOKEN
    /// @dev visibility is internal, so that the price is only accessed through the interface functions
    uint256 internal _tokenPriceInUsd;

    ////////////////////// ERRORS ///////////////////////
    error PinlinkCentralizedOracle__InvalidPrice();
    error PinlinkCentralizedOracle__NewPriceTooLow();
    error PinlinkCentralizedOracle__NewPriceTooHigh();

    /////////////////////////////////////////////////////
    constructor(address token_, uint256 initialPriceInUsd_) Ownable(msg.sender) {
        TOKEN = token_;

        // this is more a check for decimals than for the actual price.
        // Pin has 18 decimals, so if the price is less than 1e6, it is virtually 0
        if (initialPriceInUsd_ < 1e6) revert PinlinkCentralizedOracle__InvalidPrice();

        _tokenPriceInUsd = initialPriceInUsd_;
        lastPriceUpdateTimestamp = block.timestamp;

        emit PriceUpdated(initialPriceInUsd_);
    }

    /////////////// MUTATIVE FUNCTIONS //////////////////

    /// @notice Update the price of TOKEN in USD terms
    /// @dev The price should be expressed with 18 decimals.
    /// @dev Example. To set the TOKEN price to 0.88 USD, the input should be 880000000000000000
    function updateTokenPrice(uint256 usdPerToken) external onlyOwner {
        uint256 _currentPrice = _tokenPriceInUsd;

        // sanity checks to avoid too large deviations caused by bot/human errors
        if (usdPerToken < _currentPrice / 5) revert PinlinkCentralizedOracle__NewPriceTooLow();
        if (usdPerToken > _currentPrice * 5) revert PinlinkCentralizedOracle__NewPriceTooHigh();

        _tokenPriceInUsd = usdPerToken;
        lastPriceUpdateTimestamp = block.timestamp;

        // todo potential improvement. Everytime we update, we crosscheck the price with the Uniswap spot price
        //  - centralized, but controlled by a decentralized oracle, so that we can't manipulate it
        //  - cheaper to run than a TWAP oracle
        //  - less manipulable (except by us)

        emit PriceUpdated(usdPerToken);
    }

    ///////////////// VIEW FUNCTIONS ////////////////////

    /// @notice Convert a given amount of TOKEN to USD
    /// @dev The output will be with 18 decimals as well
    function convertToUsd(address token, uint256 tokenAmountIn) external view returns (uint256 usdAmount) {
        if (token != TOKEN) revert PinlinkCentralizedOracle__InvalidToken();
        if (tokenAmountIn == 0) return 0;

        if ((block.timestamp - lastPriceUpdateTimestamp) > STALENESS_THRESHOLD) {
            return 0;
        }

        // it is accepted that this conversion is rounded down for the purpose of this MVP
        // TOKEN[18] * price[USD/TOKEN][18] / PIN_DECIMALS[18] = USD[18]
        return (tokenAmountIn * _tokenPriceInUsd) / SCALE;
    }

    /// @notice Convert a given amount of USD to TOKEN
    /// @dev The output will be with 18 decimals as well
    /// @dev The caller is responsible for checking that the price is not 0.
    function convertFromUsd(address toToken, uint256 usdAmount) external view returns (uint256 tokenAmount) {
        if (toToken != TOKEN) revert PinlinkCentralizedOracle__InvalidToken();
        if (usdAmount == 0) return 0;

        if ((block.timestamp - lastPriceUpdateTimestamp) > STALENESS_THRESHOLD) {
            return 0;
        }

        // it is accepted that this conversion is rounded down for the purpose of this MVP
        // USD[18] * PIN_DECIMALS[18] / price[USD/TOKEN][18] = TOKEN[18]
        return (usdAmount * SCALE) / _tokenPriceInUsd;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IPinlinkOracle).interfaceId || super.supportsInterface(interfaceId);
    }
}
