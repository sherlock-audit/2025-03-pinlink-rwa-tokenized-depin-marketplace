// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {ERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC20, SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC1155Holder} from "lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {RewardsStream, StreamHandler} from "./streams.sol";

import {IFractionalAssets} from "src/fractional/IFractionalAssets.sol";
import {IPinlinkOracle} from "src/oracles/IPinlinkOracle.sol";

/// @notice information of a tokenId being listed for sale by a seller
struct Listing {
    // contract address containing multiple fractional assets, each of them with a tokenId
    address fractionalAssets;
    // tokenId of the asset being listed
    uint256 tokenId;
    // owner of the listing. The only one who can make modifications to the listing
    // the `seller` cannot be modified once created
    address seller;
    // number of tokens of fractions of the asset currently for sale
    // `amount` is decreased when tokens are purchased or delisted
    uint256 amount;
    // price per asset fraction in usd with 18 decimals
    uint256 usdPricePerFraction;
    // until when the listing is valid
    uint256 deadline;
}

/// @title PinLink: RWA-Tokenized DePIN Markatplace
/// @author PinLink (@jacopod: https://github.com/JacoboLansac)
/// @notice A marketplace where users can trade Pinlink Fractional assets, earning rewards while assets are listed for sale
contract PinlinkShop is ERC165, ERC1155Holder, AccessControl {
    using SafeERC20 for IERC20;
    using StreamHandler for RewardsStream;

    /// @dev operator can deposit rewards
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @dev admin cannot set the fee percentage above 10%
    uint256 public constant MAX_FEE_PERC = 1000;

    /// @notice divisor when calculating the purchase fee
    uint256 public constant FEE_DENOMINATOR = 10_000;

    /// @notice PIN ERC20 token address (only allowed payment token in purchases)
    address public immutable PIN;

    /// @notice ERC20 token in which rewards are distributed to all assets (USDC)
    address public immutable REWARDS_TOKEN;

    /// @notice default fee initialized at 5%
    uint256 public purchaseFeePerc = 500;

    /// @notice address to collect purchase fees
    address public feeReceiver;

    /// @notice proxy address where all rewards go when assets are withdrawn
    address public constant REWARDS_PROXY_ACCOUNT = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;

    /// @notice oracle to convert between PIN and USD pricing
    address public oracle;

    /// @notice handles the rewards streams for each asset (fractionalAssets, tokenId)
    mapping(address fractionalAssets => mapping(uint256 tokenId => RewardsStream)) public streams;

    /// keeps track of the listings per listingId
    mapping(bytes32 listinId => Listing) internal _listings;

    /// balances of how many assets are listed by a seller
    /// fractionalAssets ==> tokenId ==> seller ==> amount
    mapping(address fractionalAssets => mapping(uint256 tokenId => mapping(address seller => uint256 balance))) internal
        _listedBalances;

    ///////////////////// Errors /////////////////////

    error SenderIsNotSeller();
    error AssetNotEnabled();
    error NotEnoughTokens();
    error NotEnoughUnlistedTokens();
    error ExpectedNonZeroAmount();
    error ExpectedNonZeroPrice();
    error ExpectedNonZero();
    error InvalidParameter();
    error InvalidListingId();
    error ListingIdAlreadyExists();
    error SlippageExceeded();
    error AlreadyEnabled();
    error ListingDeadlineExpired();
    error DeadlineHasExpiredAlready();
    error InvalidOraclePrice();
    error InvalidOracleInterface();
    error StaleOraclePrice();

    ///////////////////// Events /////////////////////

    event FeeReceiverSet(address indexed receiver);
    event FeePercentageSet(uint256 newFeePerc);
    event AssetEnabled(
        address indexed fractionalAssets,
        uint256 indexed tokenId,
        uint256 assetSupply,
        address depositor,
        address receiver
    );
    event OracleSet(address indexed oracle);
    event RewardsDistributed(
        address indexed fractionalAssets,
        uint256 indexed tokenId,
        address indexed operator,
        uint256 amount,
        uint256 drippingPeriod
    );

    event Listed(
        bytes32 indexed listingId,
        address indexed seller,
        uint256 indexed tokenId,
        address fractionalAssets,
        uint256 amount,
        uint256 usdPricePerFraction,
        uint256 deadline
    );
    event Delisted(bytes32 indexed listingId, uint256 amount);
    event PriceUpdated(bytes32 indexed listingId, uint256 usdPricePerItem);
    event DeadlineExtended(bytes32 indexed listingId, uint256 newDeadline);
    event Purchased(
        bytes32 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint256 paymentForSellerInTokens,
        uint256 FeesInTokens,
        uint256 usdTotalAmount
    );
    event Claimed(address indexed fractionalAssets, uint256 indexed tokenId, address indexed account, uint256 amount);
    event FractionsWithdrawn(
        address indexed fractionalAssets, uint256 indexed tokenId, uint256 amount, address receiver
    );
    event FractionsDeposited(
        address indexed fractionalAssets, uint256 indexed tokenId, uint256 amount, address receiver
    );

    ///////////////////////////////////////////////////

    constructor(address pin_, address pinOracle_, address rewardToken_) {
        PIN = pin_;
        REWARDS_TOKEN = rewardToken_; // USDC exclusively, in ethereum mainnet.

        oracle = pinOracle_;
        feeReceiver = msg.sender;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    modifier onlySeller(bytes32 listingId) {
        address seller = _listings[listingId].seller;
        if (seller == address(0)) revert InvalidListingId();
        if (seller != msg.sender) revert SenderIsNotSeller();
        _;
    }

    ///////////////////// only certain roles /////////////////////

    function setFeeReceiver(address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (receiver == address(0)) revert ExpectedNonZero();
        feeReceiver = receiver;
        emit FeeReceiverSet(receiver);
    }

    function setFee(uint256 newFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newFee > MAX_FEE_PERC) revert InvalidParameter();
        purchaseFeePerc = newFee;
        emit FeePercentageSet(newFee);
    }

    function setOracle(address oracle_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(IPinlinkOracle(oracle_).supportsInterface(type(IPinlinkOracle).interfaceId), InvalidOracleInterface());

        // a stale oracle will return 0. Potentially this also validates the oracle has at least 18dp
        uint256 testValue = IPinlinkOracle(oracle_).convertToUsd(PIN, 1e18);
        if (testValue < 1e6) revert InvalidOraclePrice();

        emit OracleSet(oracle_);
        oracle = oracle_;
    }

    /// @notice Enables an asset in the echosystem
    /// @dev Once enabled, assets cannot be disabled.
    function enableAsset(address fractionalAssets, uint256 tokenId, address receiver)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        RewardsStream storage stream = streams[fractionalAssets][tokenId];

        if (stream.isEnabled()) revert AlreadyEnabled();

        uint256 assetSupply = IFractionalAssets(fractionalAssets).totalSupply(tokenId);
        stream.enableAsset(assetSupply, receiver);

        emit AssetEnabled(fractionalAssets, tokenId, assetSupply, msg.sender, receiver);
        IFractionalAssets(fractionalAssets).safeTransferFrom(msg.sender, address(this), tokenId, assetSupply, "");
    }

    function depositRewards(address fractionalAssets, uint256 tokenId, uint256 amount, uint256 drippingPeriod)
        external
        onlyRole(OPERATOR_ROLE)
    {
        RewardsStream storage stream = streams[fractionalAssets][tokenId];

        stream.depositRewards(amount, drippingPeriod);

        emit RewardsDistributed(fractionalAssets, tokenId, msg.sender, amount, drippingPeriod);
        IERC20(REWARDS_TOKEN).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @notice allows an admin to collect the unassigned rewards resulting from assets leaving the pinlinkShop
    function claimUnassignedRewards(address fractionalAssets, uint256 tokenId, address to)
        external
        onlyRole(OPERATOR_ROLE)
    {
        uint256 claimed = streams[fractionalAssets][tokenId].claimRewards(REWARDS_PROXY_ACCOUNT);
        if (claimed == 0) return;

        IERC20(REWARDS_TOKEN).safeTransfer(to, claimed);
        emit Claimed(fractionalAssets, tokenId, to, claimed);
    }

    ///////////////////// seller functions ///////////////////////////

    /// @notice lists a certain amount of fractions of a tokenId for sale, with the price denominated in USD (18 dps)
    /// @dev two identical listings sent in the same block by the same seller will revert due to a conflicting listingId
    function list(
        address fractionalAssets,
        uint256 tokenId,
        uint256 amount,
        uint256 usdPricePerFraction, // usd price with 18 decimals
        uint256 deadline
    ) external returns (bytes32 listingId) {
        listingId = _list(fractionalAssets, tokenId, amount, usdPricePerFraction, deadline);
    }

    /// @notice delists a certain amount of fractions from a listingId
    /// @dev accepts amount=type(uint256).max to delist all the fractions
    function delist(bytes32 listingId, uint256 amount) external onlySeller(listingId) {
        require(amount > 0, ExpectedNonZero());

        Listing storage listing = _listings[listingId];
        uint256 listedAmount = listing.amount;

        if (amount == type(uint256).max) {
            amount = listedAmount;
        }

        if (amount > listedAmount) revert NotEnoughTokens();

        listing.amount = listing.amount - amount;
        _listedBalances[listing.fractionalAssets][listing.tokenId][msg.sender] -= amount;

        emit Delisted(listingId, amount);
    }

    /// @notice modifies the price or deadline of a listing
    /// @dev accepts 0 as a value to keep the existing value of both parameters
    /// @dev nothing prevents from setting the existing values again. No harm either.
    function modifyListing(bytes32 listingId, uint256 usdPricePerFraction, uint256 newDeadline)
        external
        onlySeller(listingId)
    {
        if (usdPricePerFraction > 0) {
            _listings[listingId].usdPricePerFraction = usdPricePerFraction;
            emit PriceUpdated(listingId, usdPricePerFraction);
        }
        if (newDeadline > 0) {
            require(newDeadline > block.timestamp, DeadlineHasExpiredAlready());
            _listings[listingId].deadline = newDeadline;
            emit DeadlineExtended(listingId, newDeadline);
        }
    }
    /// @notice allows a buyer to purchase a certain amount of fractions from a listing
    /// @dev The buyer pays in PIN tokens, but the listing is denominated in USD.
    /// @dev An oracle is used internally to convert between PIN and USD
    /// @dev the maxTotalPinAmount protects from slippage and also from a malicious sellers frontrunning the purchase and increasing the price

    function purchase(bytes32 listingId, uint256 fractionsAmount, uint256 maxTotalPinAmount) external {
        require(fractionsAmount > 0, ExpectedNonZero());

        Listing storage listing = _listings[listingId];

        address seller = listing.seller;
        uint256 tokenId = listing.tokenId;
        address fractionalAssets = listing.fractionalAssets;

        // make InvalidListingId be the one that fails first
        require(seller != address(0), InvalidListingId());
        // purchases on the exact deadline not allowed
        require(block.timestamp < listing.deadline, ListingDeadlineExpired());

        {
            // to prevent stack too deep
            uint256 listedAmount = listing.amount;
            if (listedAmount < fractionsAmount) revert NotEnoughTokens();
            // update listing information in storage
            listing.amount = listedAmount - fractionsAmount;
            _listedBalances[fractionalAssets][tokenId][seller] -= fractionsAmount;

            streams[fractionalAssets][tokenId].transferBalances(seller, msg.sender, fractionsAmount);
        }

        uint256 totalUsdPayment = listing.usdPricePerFraction * fractionsAmount;
        uint256 totalPinPayment = IPinlinkOracle(oracle).convertFromUsd(address(PIN), totalUsdPayment);

        if (totalPinPayment == 0) revert StaleOraclePrice();
        if (totalPinPayment > maxTotalPinAmount) revert SlippageExceeded();

        // transfers the payment to the seller and the fees to the feeReceiver
        // note: ERC20 with callbacks (ERC777) are not supported, so the following should be safe
        (uint256 paymentForSeller, uint256 fees) = _handlePayments(msg.sender, seller, totalPinPayment);

        // buyer receives purchased tokens at the very end (IFractionalAssets.onReceived callback is the most dangerous external call)
        emit Purchased(listingId, msg.sender, seller, fractionsAmount, paymentForSeller, fees, totalUsdPayment);
    }

    /// @notice claims rewards for a certain asset and transfers it to the caller
    function claimRewards(address fractionalAssets, uint256 tokenId) external {
        uint256 claimed = streams[fractionalAssets][tokenId].claimRewards(msg.sender);
        if (claimed == 0) return;

        IERC20(REWARDS_TOKEN).safeTransfer(msg.sender, claimed);
        emit Claimed(fractionalAssets, tokenId, msg.sender, claimed);
    }

    /// @notice claims rewards for multiple assets and transfers them to the caller
    function claimRewardsMultiple(address fractionalAssets, uint256[] calldata tokenIds) external {
        uint256 totalClaimed;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            // stream.claimRewards resets the rewards, so no harm in putting the same tokenId multiple times
            uint256 claimed = streams[fractionalAssets][tokenIds[i]].claimRewards(msg.sender);
            totalClaimed += claimed;
            // we emit here individual events for each tokenId for accountability reasons
            emit Claimed(fractionalAssets, tokenIds[i], msg.sender, claimed);
        }
        IERC20(REWARDS_TOKEN).safeTransfer(msg.sender, totalClaimed);
    }

    /// @notice withdraws an asset outside of the Pinlink ecosystem.
    /// @dev Listed assets cannot be withdrawn, they have to be first delisted
    /// @dev When assets are withdrawn, the corresponding rewards are redirected to the REWARDS_PROXY_ACCOUNT account
    function withdrawAsset(address fractionalAssets, uint256 tokenId, uint256 amount, address receiver) external {
        if (_nonListedBalance(fractionalAssets, tokenId, msg.sender) < amount) revert NotEnoughUnlistedTokens();

        // this does't transfer the assets, but only the internal accounting of staking balances
        streams[fractionalAssets][tokenId].transferBalances(msg.sender, REWARDS_PROXY_ACCOUNT, amount);

        emit FractionsWithdrawn(fractionalAssets, tokenId, amount, receiver);
        IFractionalAssets(fractionalAssets).safeTransferFrom(address(this), receiver, tokenId, amount, "");
    }

    /// @notice deposit an enabled asset into the ecosystem
    /// @dev the assets are automatically staked as they enter in the ecosystem
    function depositAsset(address fractionalAssets, uint256 tokenId, uint256 amount) external {
        _deposit(fractionalAssets, tokenId, amount);
    }

    function depositAndList(
        address fractionalAssets,
        uint256 tokenId,
        uint256 amount,
        uint256 usdPricePerFraction,
        uint256 deadline
    ) external returns (bytes32 listingId) {
        _deposit(fractionalAssets, tokenId, amount);
        listingId = _list(fractionalAssets, tokenId, amount, usdPricePerFraction, deadline);
    }

    function rescueToken(address erc20Token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (erc20Token == address(REWARDS_TOKEN)) revert InvalidParameter();

        // PIN is not expected to stay in this contract balance, so it is ok to recover
        IERC20(erc20Token).safeTransfer(to, IERC20(erc20Token).balanceOf(address(this)));
    }

    /////////////////// view ///////////////////

    /// @notice returns the total amount of PIN tokens to pay for a certain amount of fractions of a listingId
    /// @dev This view function should not revert, so when the quote request is invalid, it will return "error codes":
    ///      - uint256.max - 1: not enough fractions in listing
    ///      - uint256.max - 2: listing deadline has expired
    ///      - uint256.max - 3: stale oracle price
    /// @dev This returns uint256.max if the price is stale, if the quote request is invalid
    ///      Invalid request == not enough fractions, past deadline, invalid listing, ... etc
    function getQuoteInTokens(bytes32 listingId, uint256 fractionsAmount)
        external
        view
        returns (uint256 totalPurchasePriceInPIN)
    {
        // not worth checking that fractionsAmount must be greater than 0
        if (_listings[listingId].amount < fractionsAmount) return type(uint256).max - 1;
        if (_listings[listingId].deadline < block.timestamp) return type(uint256).max - 2;

        uint256 usdTotalPrice = _listings[listingId].usdPricePerFraction * fractionsAmount;

        // in the case of oracle staleness or wrong token, IPinlinkOracle should revert
        totalPurchasePriceInPIN = IPinlinkOracle(oracle).convertFromUsd(address(PIN), usdTotalPrice);
        if (totalPurchasePriceInPIN == 0) return type(uint256).max - 3;
    }

    function getAssetInfo(address fractionalAssets, uint256 tokenId)
        external
        view
        returns (
            uint256 assetSupply,
            uint256 currentGlobalRewardsPerStaked,
            uint256 lastDepositTimestamp,
            uint256 drippingPeriod
        )
    {
        RewardsStream storage stream = streams[fractionalAssets][tokenId];
        return (stream.assetSupply, stream.globalRewardsPerStaked(), stream.lastDepositTimestamp, stream.drippingPeriod);
    }

    /// @notice Returns the `amount` of an asset owned by `account`, and the amount of them that are listed
    /// @dev Note that the `listedBalance` and `notListedBalance` ignore the deadline parameter here, so this is only an approximation
    function getBalances(address fractionalAssets, uint256 tokenId, address account)
        external
        view
        returns (uint256 stakedBalance, uint256 listedBalance, uint256 notListedBalance)
    {
        /// listedBalance is a subset of stakedBalance, so `stakedBalance >= listedBalance` always
        stakedBalance = streams[fractionalAssets][tokenId].stakedBalances[account];
        listedBalance = _listedBalances[fractionalAssets][tokenId][account];
        notListedBalance = stakedBalance - listedBalance;
    }

    /// @notice returns a listing object with all its attributes
    function getListing(bytes32 listingId) external view returns (Listing memory) {
        return _listings[listingId];
    }

    /// @notice returns True if the admins have enabled the asset in the echosystem
    function isAssetEnabled(address fractionalAssets, uint256 tokenId) external view returns (bool) {
        return streams[fractionalAssets][tokenId].isEnabled();
    }

    function getPendingRewards(address fractionalAssets, uint256 tokenId, address account)
        external
        view
        returns (uint256)
    {
        return streams[fractionalAssets][tokenId].getPendingRewards(account);
    }

    function getRewardsConstants()
        public
        pure
        returns (
            uint256 minRewardsDepositAmount,
            uint256 maxAssetSupply,
            uint256 minDrippingPeriod,
            uint256 maxDrippingPeriod
        )
    {
        return (
            StreamHandler.MIN_REWARDS_DEPOSIT_AMOUNT,
            StreamHandler.MAX_ASSET_SUPPLY,
            StreamHandler.MIN_DRIPPING_PERIOD,
            StreamHandler.MAX_DRIPPING_PERIOD
        );
    }

    /////////////////// ERC165 compliancy ///////////////////

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165, AccessControl, ERC1155Holder)
        returns (bool)
    {
        return ERC1155Holder.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }

    /////////////////// internal functions ///////////////////

    /// @dev listing with same price in same block reverts. Wait one block to list the exact same listing
    function _list(
        address fractionalAssets,
        uint256 tokenId,
        uint256 amount,
        uint256 usdPricePerFraction, // usd price with 18 decimals
        uint256 deadline
    ) internal returns (bytes32 listingId) {
        listingId = keccak256(
            abi.encode(fractionalAssets, tokenId, msg.sender, amount, usdPricePerFraction, deadline, block.number)
        );

        require(amount > 0, ExpectedNonZeroAmount());
        require(deadline > block.timestamp, DeadlineHasExpiredAlready());
        require(usdPricePerFraction > 0, ExpectedNonZeroPrice());
        require(_listings[listingId].seller == address(0), ListingIdAlreadyExists());

        if (amount > _nonListedBalance(fractionalAssets, tokenId, msg.sender)) revert NotEnoughUnlistedTokens();

        // register listing information
        _listings[listingId] = Listing({
            fractionalAssets: fractionalAssets,
            tokenId: tokenId,
            seller: msg.sender,
            amount: amount,
            usdPricePerFraction: usdPricePerFraction,
            deadline: deadline
        });

        _listedBalances[fractionalAssets][tokenId][msg.sender] += amount;

        emit Listed(listingId, msg.sender, tokenId, fractionalAssets, amount, usdPricePerFraction, deadline);
    }

    function _deposit(address fractionalAssets, uint256 tokenId, uint256 amount) internal {
        // it is only possible to deposit in already enabled assets in the ecosystem
        if (!streams[fractionalAssets][tokenId].isEnabled()) revert AssetNotEnabled();

        // When assets are withdrawn, the rewards are directed to the feeReceiver.
        // When they are deposited back, they are redirected to the staker who deposits
        streams[fractionalAssets][tokenId].transferBalances(REWARDS_PROXY_ACCOUNT, msg.sender, amount);

        emit FractionsDeposited(fractionalAssets, tokenId, amount, msg.sender);
        IFractionalAssets(fractionalAssets).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
    }

    function _handlePayments(address buyer, address seller, uint256 totalPinPayment)
        internal
        returns (uint256 paymentForSeller, uint256 fees)
    {
        // fees are rounded in favor of the protocol
        paymentForSeller = totalPinPayment * (FEE_DENOMINATOR - purchaseFeePerc) / FEE_DENOMINATOR;
        fees = totalPinPayment - paymentForSeller;

        // no need to verfy that msg.value==0, because purchases with tokens are done with purchaseWithToken() which is non-payable
        IERC20(PIN).safeTransferFrom(buyer, seller, paymentForSeller);
        IERC20(PIN).safeTransferFrom(buyer, feeReceiver, fees);
    }

    function _nonListedBalance(address fractionalAssets, uint256 tokenId, address account)
        internal
        view
        returns (uint256)
    {
        uint256 accountBalance = streams[fractionalAssets][tokenId].stakedBalances[account];
        uint256 listedBalance = _listedBalances[fractionalAssets][tokenId][account];

        return (accountBalance > listedBalance) ? accountBalance - listedBalance : 0;
    }
}
