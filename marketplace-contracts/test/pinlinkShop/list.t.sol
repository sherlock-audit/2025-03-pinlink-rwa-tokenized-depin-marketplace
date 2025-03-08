// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {PinlinkShop, Listing} from "src/marketplaces/pinlinkShop.sol";

contract StakingShop_ListingByAdmin_Tests is BaseStakingShopTests {
    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        pshop.enableAsset(address(fractions), asset1, admin);
        pshop.enableAsset(address(fractions), asset2, admin);
        pshop.enableAsset(address(fractions), asset3, admin);
        vm.stopPrank();
    }

    // check successful listing by admin (after deposited)
    function test_listingByAdmin() public {
        vm.prank(admin);
        bytes32 listingId = pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        Listing memory listing = pshop.getListing(listingId);
        // (address _fractions, uint256 tokenId, address seller, uint256 amount, uint256 pricePerUsd, uint256 deadline) = pshop.getListing(listingId);
        assertEq(listing.fractionalAssets, address(fractions));
        assertEq(listing.tokenId, asset1);
        assertEq(listing.seller, admin);
        assertEq(listing.amount, 20);
        assertEq(listing.usdPricePerFraction, 1000e18);
        assertEq(listing.deadline, block.timestamp + 7 days);
    }

    // check that pshop.list() doesnt alter contract or caller balances
    function test_listingByAdmin_doesntAlterBalances() public {
        uint256 adminBalanceBefore = fractions.balanceOf(admin, asset1);
        uint256 pshopBalanceBefore = fractions.balanceOf(address(pshop), asset1);
        uint256 totalSupplyBefore = fractions.totalSupply(asset1);

        vm.prank(admin);
        pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        assertEq(adminBalanceBefore, fractions.balanceOf(admin, asset1));
        assertEq(pshopBalanceBefore, fractions.balanceOf(address(pshop), asset1));
        assertEq(totalSupplyBefore, fractions.totalSupply(asset1));
    }

    // check that pshop.list() doesnt alter the staked assets owned by the caller inside the ecosystem (listed + unlisted)
    function test_listingByAdmin_doesntAlterStakedBalance() public {
        uint256 stakedBalance = _stakedBalance(address(fractions), asset1, admin);

        vm.prank(admin);
        pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        uint256 stakedBalanceAfter = _stakedBalance(address(fractions), asset1, admin);

        assertEq(stakedBalance, stakedBalanceAfter);
    }

    // check that pshop.list() increases the listedBalance of the asset
    function test_listingByAdmin_increasesListedBalance() public {
        uint256 listedBalance = _listedBalance(address(fractions), asset1, admin);

        uint256 amount = 5;
        vm.prank(admin);
        pshop.list(address(fractions), asset1, amount, 1000e18, block.timestamp + 7 days);

        uint256 listedBalanceAfter = _listedBalance(address(fractions), asset1, admin);

        assertEq(listedBalance, listedBalanceAfter - amount);
    }

    // check that pshop.list() requires that the caller owns the asset
    function test_listingByAdmin_requiresAssetOwnership() public {
        // there are some fractions of this asset in the contract, but owned by admin
        assertGt(fractions.balanceOf(address(pshop), asset1), 0);
        assertGt(_stakedBalance(address(fractions), asset1, admin), 0);
        assertEq(_stakedBalance(address(fractions), asset1, alice), 0);

        vm.expectRevert(PinlinkShop.NotEnoughUnlistedTokens.selector);
        vm.prank(alice);
        pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);
    }

    // check that listing twice in same block with same prices revert with ListingIdAlreadyExists
    function test_listingByAdmin_twiceInSameBlock() public {
        vm.startPrank(admin);
        pshop.list(address(fractions), asset1, 2, 1000e18, block.timestamp + 7 days);

        vm.expectRevert(PinlinkShop.ListingIdAlreadyExists.selector);
        pshop.list(address(fractions), asset1, 2, 1000e18, block.timestamp + 7 days);
    }

    function test_listingByAdmin_twiceInNextBlock() public {
        uint256 amount = 3;
        vm.startPrank(admin);
        pshop.list(address(fractions), asset1, amount, 1000e18, block.timestamp + 7 days);

        vm.roll(block.number + 1);

        pshop.list(address(fractions), asset1, amount, 2000e18, block.timestamp + 3 days);

        assertEq(_listedBalance(address(fractions), asset1, admin), amount * 2);
    }

    // check that listing with expired deadline reverts with DeadlineHasExpiredAlready
    function test_listingByAdmin_expiredDeadline() public {
        vm.startPrank(admin);
        vm.expectRevert(PinlinkShop.DeadlineHasExpiredAlready.selector);
        pshop.list(address(fractions), asset1, 2, 1000e18, block.timestamp - 1);
    }

    // check that listing with amount 0 reverts with ExpectedNonZeroAmount
    function test_listingByAdmin_amountZero() public {
        vm.startPrank(admin);
        vm.expectRevert(PinlinkShop.ExpectedNonZeroAmount.selector);
        pshop.list(address(fractions), asset1, 0, 1000e18, block.timestamp + 7 days);
    }

    // check that listing with price 0 reverts with ExpectedNonZeroPrice
    function test_listingByAdmin_priceZero() public {
        vm.startPrank(admin);
        vm.expectRevert(PinlinkShop.ExpectedNonZeroPrice.selector);
        pshop.list(address(fractions), asset1, 5, 0, block.timestamp + 7 days);
    }

    // check that pshop.list() doesn't alter the pending rewards for the caller
    function test_listingByAdmin_doesntAlterPendingRewards() public {
        // lets deposit some rewards, that go to admin as he is the only staked
        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 100e6, 6 hours);

        skip(1 days);

        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, admin);
        assertGt(pendingRewardsBefore, 0);

        vm.prank(admin);
        pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        assertEq(pendingRewardsBefore, pshop.getPendingRewards(address(fractions), asset1, admin));
    }

    // check the listingId is as expected
    function test_listingByAdmin_listingId() public {
        bytes32 expectedListingId = keccak256(
            abi.encode(
                address(fractions), asset1, admin, uint256(20), uint256(1000e18), block.timestamp + 7 days, block.number
            )
        );

        vm.prank(admin);
        bytes32 listingId = pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        assertEq(listingId, expectedListingId);
    }
}

contract StakingShop_ListingByBuyer_Tests is BaseStakingShopTests {
    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        pshop.enableAsset(address(fractions), asset1, admin);
        pshop.enableAsset(address(fractions), asset2, admin);
        pshop.enableAsset(address(fractions), asset3, admin);
        bytes32 listingId = pshop.list(address(fractions), asset1, 25, 1000e18, block.timestamp + 7 days);
        vm.stopPrank();

        _doPurchase(listingId, 20, alice);
        assertGt(_stakedBalance(address(fractions), asset1, alice), 0);
    }

    // check successful listing by alice (after purchasing from admin)
    function test_listingByAlice() public {
        vm.prank(alice);
        bytes32 aliceListingId = pshop.list(address(fractions), asset1, 10, 2000e18, block.timestamp + 3 days);

        Listing memory listing = pshop.getListing(aliceListingId);
        // (address _fractions, uint256 tokenId, address seller, uint256 amount, uint256 pricePerUsd, uint256 deadline) = pshop.getListing(listingId);
        assertEq(listing.fractionalAssets, address(fractions));
        assertEq(listing.tokenId, asset1);
        assertEq(listing.seller, alice);
        assertEq(listing.amount, 10);
        assertEq(listing.usdPricePerFraction, 2000e18);
        assertEq(listing.deadline, block.timestamp + 3 days);
    }

    // check that pshop.list() doesnt alter contract or caller balances
    function test_listingByAlice_doesntAlterBalances() public {
        uint256 aliceBalanceBefore = fractions.balanceOf(alice, asset1);
        uint256 pshopBalanceBefore = fractions.balanceOf(address(pshop), asset1);
        uint256 totalSupplyBefore = fractions.totalSupply(asset1);

        vm.prank(alice);
        pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        assertEq(aliceBalanceBefore, fractions.balanceOf(alice, asset1));
        assertEq(pshopBalanceBefore, fractions.balanceOf(address(pshop), asset1));
        assertEq(totalSupplyBefore, fractions.totalSupply(asset1));
    }

    // check that pshop.list() doesnt alter the staked assets owned by the caller inside the ecosystem (listed + unlisted)
    function test_listingByAlice_doesntAlterStakedBalance() public {
        uint256 stakedBalance = _stakedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        uint256 stakedBalanceAfter = _stakedBalance(address(fractions), asset1, alice);

        assertEq(stakedBalance, stakedBalanceAfter);
    }

    // check that pshop.list() increases the listedBalance of the asset
    function test_listingByAlice_increasesListedBalance() public {
        uint256 listedBalance = _listedBalance(address(fractions), asset1, alice);

        uint256 amount = 5;
        vm.prank(alice);
        pshop.list(address(fractions), asset1, amount, 1000e18, block.timestamp + 7 days);

        uint256 listedBalanceAfter = _listedBalance(address(fractions), asset1, alice);

        assertEq(listedBalance, listedBalanceAfter - amount);
    }

    // check that pshop.list() requires that the caller owns the asset
    function test_listingByAlice_requiresAssetOwnership() public {
        assertGt(fractions.balanceOf(address(pshop), asset1), 0);
        assertGt(_stakedBalance(address(fractions), asset1, alice), 0);
        assertEq(_stakedBalance(address(fractions), asset1, bob), 0);

        vm.expectRevert(PinlinkShop.NotEnoughUnlistedTokens.selector);
        vm.prank(bob);
        pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);
    }

    // check that listing twice in same block with same prices revert with ListingIdAlreadyExists
    function test_listingByAlice_twiceInSameBlock() public {
        vm.startPrank(alice);
        pshop.list(address(fractions), asset1, 2, 1000e18, block.timestamp + 7 days);

        vm.expectRevert(PinlinkShop.ListingIdAlreadyExists.selector);
        pshop.list(address(fractions), asset1, 2, 1000e18, block.timestamp + 7 days);
    }

    function test_listingByAlice_twiceInNextBlock() public {
        uint256 amount = 3;
        vm.startPrank(alice);
        pshop.list(address(fractions), asset1, amount, 1000e18, block.timestamp + 7 days);

        vm.roll(block.number + 1);

        pshop.list(address(fractions), asset1, amount, 2000e18, block.timestamp + 3 days);

        assertEq(_listedBalance(address(fractions), asset1, alice), amount * 2);
    }

    // check that listing with expired deadline reverts with DeadlineHasExpiredAlready
    function test_listingByAlice_expiredDeadline() public {
        vm.startPrank(alice);
        vm.expectRevert(PinlinkShop.DeadlineHasExpiredAlready.selector);
        pshop.list(address(fractions), asset1, 2, 1000e18, block.timestamp - 1);
    }

    // check that listing with amount 0 reverts with ExpectedNonZeroAmount
    function test_listingByAlice_amountZero() public {
        vm.startPrank(alice);
        vm.expectRevert(PinlinkShop.ExpectedNonZeroAmount.selector);
        pshop.list(address(fractions), asset1, 0, 1000e18, block.timestamp + 7 days);
    }

    // check that listing with price 0 reverts with ExpectedNonZeroPrice
    function test_listingByAlice_priceZero() public {
        vm.startPrank(alice);
        vm.expectRevert(PinlinkShop.ExpectedNonZeroPrice.selector);
        pshop.list(address(fractions), asset1, 5, 0, block.timestamp + 7 days);
    }

    // check that pshop.list() doesn't alter the pending rewards for the caller
    function test_listingByAlice_doesntAlterPendingRewards() public {
        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 100e6, 12 hours);

        skip(1 days);

        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice);
        assertGt(pendingRewardsBefore, 0);

        vm.prank(alice);
        pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        assertEq(pendingRewardsBefore, pshop.getPendingRewards(address(fractions), asset1, alice));
    }

    // check the listingId is as expected
    function test_listingByAlice_listingId() public {
        bytes32 expectedListingId = keccak256(
            abi.encode(
                address(fractions), asset1, alice, uint256(20), uint256(1000e18), block.timestamp + 7 days, block.number
            )
        );

        vm.prank(alice);
        bytes32 listingId = pshop.list(address(fractions), asset1, 20, 1000e18, block.timestamp + 7 days);

        assertEq(listingId, expectedListingId);
    }

    // todo

    // check that pshop.list() doesn't alter the pending rewards for the caller
}
