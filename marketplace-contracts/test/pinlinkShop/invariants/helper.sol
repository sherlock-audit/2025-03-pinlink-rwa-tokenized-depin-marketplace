// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {FractionalAssets} from "src/fractional/FractionalAssets.sol";
import {PinlinkShop, Listing} from "src/marketplaces/pinlinkShop.sol";
import {Test} from "forge-std/Test.sol";
import {IPinToken} from "src/interfaces/IPinToken.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {DummyOracle} from "src/oracles/DummyOracle.sol";
import {ERC1155, ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {EnumerableSet} from "lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

contract InvariantsHelperSingleAsset is Test {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    PinlinkShop public pshop;
    FractionalAssets public fractions;
    IERC20 public pin;
    IERC20 public usdc;
    uint256 tokenId;

    // this is to only check invariants on the last modified asset
    uint256 lastModifiedAsset;
    address lastActor;

    address tmp = makeAddr("tmp");

    address admin = makeAddr("admin");
    address feeReceiver = makeAddr("feeReceiver");
    address operator = makeAddr("operator");

    EnumerableSet.AddressSet internal _actors;
    EnumerableSet.UintSet internal _assets;

    address public currentActor;
    uint256 public timestamp;
    uint256 MAX_TIME_JUMP = 1 days;
    uint256 MIN_TIME_JUMP = 1;
    uint256 MIN_PRICE_USD = 0.0001e18;
    uint256 MAX_PRICE_USD = 10000e18;

    // mapping(address seller => bytes32[] listingId) public listingsPerSeller;
    // mapping(uint256 tokenId => bytes32[] listingId) public listingsPerAsset;

    // in this invariant suite, we only work with one tokenId, so we can ignore it here
    mapping(address account => uint256) public _staked;
    mapping(address account => uint256) public _listed;
    mapping(address account => uint256) public _unlisted;

    mapping(address account => uint256) public _claimed;

    mapping(address account => bytes32[] listingId) public _userListings;

    bytes32[] public _allListings;

    uint256 public pinCirculating;

    uint256 public totalClaimedRewards;
    uint256 public totalDepositedRewards;

    uint256 public totalDepositedAssets;
    uint256 public totalWithdrawnAssets;

    /////////////////////////////////////////////////////
    constructor(FractionalAssets fractions_, PinlinkShop pshop_, address pin_, address usdc_, uint256 assetId_) {
        tokenId = assetId_;

        fractions = fractions_;
        pshop = pshop_;
        pin = IERC20(pin_);
        usdc = IERC20(usdc_);

        _actors.add(address(makeAddr("actor1")));
        _actors.add(address(makeAddr("actor2")));
        _actors.add(address(makeAddr("actor3")));
        _actors.add(address(makeAddr("actor4")));
        _actors.add(address(makeAddr("actor5")));
        _actors.add(feeReceiver);
        _actors.add(admin);

        deal(address(pin), tmp, _actors.length() * 100_000e18);

        vm.prank(admin);
        pshop.enableAsset(address(fractions), uint256(tokenId), feeReceiver);
        _staked[feeReceiver] = 100;
        _unlisted[feeReceiver] = 100;

        vm.prank(operator);
        usdc.approve(address(pshop), type(uint256).max);

        for (uint256 i = 0; i < _actors.length(); i++) {
            vm.startPrank(_actors.at(i));
            pin.approve(address(pshop), type(uint256).max);
            vm.stopPrank();

            vm.prank(tmp);
            pin.transfer(_actors.at(i), 100_000e18);
            pinCirculating += 100_000e18;
        }
    }

    modifier passTime(uint256 seed) {
        timestamp += _bound(seed, MIN_TIME_JUMP, MAX_TIME_JUMP);
        vm.warp(timestamp);
        _;
    }

    modifier choseActor(uint256 seed) {
        currentActor = _actors.at(seed % _actors.length());
        _;
    }

    //////////////////////////////////////////////////////////
    // UTILS
    //////////////////////////////////////////////////////////

    function list(uint256 seed) public passTime(seed) choseActor(seed) {
        uint256 unlisted = _unlistedBalance(currentActor);

        if (unlisted == 0) return;

        uint256 amount = _bound(seed, 1, unlisted);
        uint256 price = _bound(seed, MIN_PRICE_USD, MAX_PRICE_USD);
        uint256 deadline = block.timestamp + _bound(seed, 1, 30 days);

        vm.prank(currentActor);
        bytes32 listingId = pshop.list(address(fractions), tokenId, amount, price, deadline);

        _listed[currentActor] += amount;
        _unlisted[currentActor] -= amount;
        _userListings[currentActor].push(listingId);
        _allListings.push(listingId);
    }

    function delist(uint256 seed) public passTime(seed) choseActor(seed) {
        if (_userListings[currentActor].length == 0) return;

        uint256 listingIndex = seed % _userListings[currentActor].length;
        bytes32 listingId = _userListings[currentActor][listingIndex];

        Listing memory listing = pshop.getListing(listingId);
        if (listing.amount == 0) return;

        uint256 amount = _bound(seed, 1, listing.amount);

        vm.prank(currentActor);
        pshop.delist(listingId, amount);

        _listed[currentActor] -= amount;
        _unlisted[currentActor] += amount;
    }

    function modifyListing(uint256 seed) public passTime(seed) choseActor(seed) {
        if (_userListings[currentActor].length == 0) return;

        uint256 listingIndex = seed % _userListings[currentActor].length;
        bytes32 listingId = _userListings[currentActor][listingIndex];

        uint256 price = _bound(seed, MIN_PRICE_USD, MAX_PRICE_USD);
        uint256 deadline = block.timestamp + _bound(seed, 1, 7 days);

        vm.prank(currentActor);
        pshop.modifyListing(listingId, price, deadline);
    }

    // multiple purchase functions to increase the likelihood compare to list/delist/modifyListing
    function purchase1(uint256 seed) public passTime(seed) choseActor(seed) {
        _purchase(seed);
    }

    function purchase2(uint256 seed) public passTime(seed) choseActor(seed) {
        _purchase(seed);
    }

    function _purchase(uint256 seed) internal {
        if (_allListings.length == 0) return;

        uint256 listingIndex = seed % _allListings.length;
        bytes32 listingId = _allListings[listingIndex];

        Listing memory listing = pshop.getListing(listingId);

        if (block.timestamp >= listing.deadline) return;
        if (listing.amount == 0) return;

        uint256 amount = _bound(seed, 1, listing.amount);
        uint256 totalPinTokens = pshop.getQuoteInTokens(listingId, amount);
        if (totalPinTokens > pin.balanceOf(currentActor)) return;

        uint256 overallBalanceBefore = _aggergatedPinBalances();

        vm.prank(currentActor);
        pshop.purchase(listingId, amount, totalPinTokens);

        assertEq(overallBalanceBefore, _aggergatedPinBalances(), "aggregated PIN balance changed");

        _listed[listing.seller] -= amount;
        _unlisted[currentActor] += amount;

        _staked[listing.seller] -= amount;
        _staked[currentActor] += amount;
    }

    function depositRewards(uint256 seed) public {
        if (!_isDrippingComplete()) return;

        uint256 rewards = _bound(seed, 1e6, 100_000e6);
        uint256 newDrippingPeriod = _bound(seed, 6 hours, 15 days);

        deal(address(usdc), operator, rewards);
        vm.prank(operator);
        pshop.depositRewards(address(fractions), tokenId, rewards, newDrippingPeriod);

        totalDepositedRewards += rewards;
    }

    function claimRewards(uint256 seed) public passTime(seed) choseActor(seed) {
        uint256 rewards = pshop.getPendingRewards(address(fractions), tokenId, currentActor);
        if (rewards == 0) return;

        vm.prank(currentActor);
        pshop.claimRewards(address(fractions), tokenId);

        totalClaimedRewards += rewards;
        _claimed[currentActor] += rewards;
    }

    function depositAsset(uint256 seed) public passTime(seed) choseActor(seed) {
        uint256 assetBalance = fractions.balanceOf(currentActor, tokenId);
        if (assetBalance == 0) return;

        uint256 amount = _bound(seed, 1, assetBalance);

        vm.startPrank(currentActor);
        fractions.setApprovalForAll(address(pshop), true);
        pshop.depositAsset(address(fractions), tokenId, amount);
        vm.stopPrank();

        _staked[currentActor] += amount;
        _unlisted[currentActor] += amount;
        _staked[pshop.REWARDS_PROXY_ACCOUNT()] -= amount;
        _unlisted[pshop.REWARDS_PROXY_ACCOUNT()] -= amount;

        totalDepositedAssets += amount;
    }

    function withdrawAsset(uint256 seed) public passTime(seed) choseActor(seed) {
        uint256 unlistedBalance = _unlisted[currentActor];
        if (unlistedBalance == 0) return;

        uint256 amount = _bound(seed, 1, unlistedBalance);

        vm.prank(currentActor);
        pshop.withdrawAsset(address(fractions), tokenId, amount, currentActor);

        _staked[currentActor] -= amount;
        _unlisted[currentActor] -= amount;
        _staked[pshop.REWARDS_PROXY_ACCOUNT()] += amount;
        _unlisted[pshop.REWARDS_PROXY_ACCOUNT()] += amount;

        totalWithdrawnAssets += amount;
    }

    function actorAt(uint256 i) public view returns (address) {
        return _actors.at(i);
    }

    function nActors() public view returns (uint256) {
        return _actors.length();
    }

    /////////////////// internals //////////////////////////////

    function _aggergatedPinBalances() internal view returns (uint256 totalPinInSystem) {
        for (uint256 i = 0; i < _actors.length(); i++) {
            totalPinInSystem += pin.balanceOf(_actors.at(i));
        }
    }

    function _unlistedBalance(address account) internal view returns (uint256) {
        (,, uint256 unlisted) = pshop.getBalances(address(fractions), tokenId, account);
        return unlisted;
    }

    function _isDrippingComplete() internal view returns (bool) {
        (,, uint256 lastDepositTimestamp, uint256 drippingPeriod) = pshop.getAssetInfo(address(fractions), tokenId);
        return block.timestamp > lastDepositTimestamp + drippingPeriod;
    }
}
