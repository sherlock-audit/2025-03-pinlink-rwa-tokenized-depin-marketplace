// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {PinlinkShop} from "src/marketplaces/pinlinkShop.sol";

contract StakingShop_Withdraw_Tests is BaseStakingShopTests {
    bytes32 listingId0;
    bytes32 listingId1;
    bytes32 listingId2;
    bytes32 listingId3;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        pshop.enableAsset(address(fractions), asset1, admin);
        pshop.enableAsset(address(fractions), asset2, admin);
        listingId0 = pshop.list(address(fractions), asset1, 70, 8000e18, block.timestamp + 12 days);
        listingId1 = pshop.list(address(fractions), asset1, 30, 10000e18, block.timestamp + 12 days);
        listingId2 = pshop.list(address(fractions), asset2, 100, 2000e18, block.timestamp + 5 days);
        vm.stopPrank();

        // she needs a lot of funds to purchase 30 fractions
        deal(address(PIN), alice, 10_000_000e18);
        deal(address(PIN), bob, 10_000_000e18);

        _doPurchase(listingId0, 30, alice);
        vm.prank(alice);
        listingId3 = pshop.list(address(fractions), asset1, 15, 900e18, block.timestamp + 3 days);

        // required to deposit assets
        vm.prank(alice);
        fractions.setApprovalForAll(address(pshop), true);
        vm.prank(bob);
        fractions.setApprovalForAll(address(pshop), true);
    }

    function _doWithdraw(address _fractions, uint256 assetId, uint256 amount, address user) internal {
        vm.prank(user);
        pshop.withdrawAsset(_fractions, assetId, amount, user);
    }

    // check that pshop.depositAsset() reverts for non-enabled assets with AssetNotEnabled
    function test_depositAsset_notEnabled() public {
        vm.prank(bob);
        vm.expectRevert(PinlinkShop.AssetNotEnabled.selector);
        pshop.depositAsset(address(fractions), asset3, 3);
    }

    // check that pshop.depositAsset() decreases asset balance of caller
    function test_depositAsset_decereaseBalanceOfCaller() public {
        _doWithdraw(address(fractions), asset1, 5, alice);

        uint256 amount = 3;
        uint256 balanceBefore = fractions.balanceOf(alice, asset1);

        vm.prank(alice);
        pshop.depositAsset(address(fractions), asset1, amount);

        assertEq(fractions.balanceOf(alice, asset1), balanceBefore - amount);
    }

    // check that pshop.depositAsset() increases asset balance of pshop contract
    function test_depositAsset_increaseBalanceOfPshop() public {
        _doWithdraw(address(fractions), asset1, 5, alice);

        uint256 amount = 3;
        uint256 balanceBefore = fractions.balanceOf(address(pshop), asset1);

        vm.prank(alice);
        pshop.depositAsset(address(fractions), asset1, amount);

        assertEq(fractions.balanceOf(address(pshop), asset1), balanceBefore + amount);
    }

    // check that pshop.depositAsset() increases _stakedBalance of caller
    function test_depositAsset_increasesStakedBalanceOfCaller() public {
        _doWithdraw(address(fractions), asset1, 5, alice);

        uint256 amount = 3;
        uint256 stakedBalanceBefore = _stakedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.depositAsset(address(fractions), asset1, amount);

        assertEq(_stakedBalance(address(fractions), asset1, alice), stakedBalanceBefore + amount);
    }

    // check that pshop.depositAsset() does not alter _listedBalance of caller
    function test_depositAsset_doesntAlterListedBalanceOfCaller() public {
        _doWithdraw(address(fractions), asset1, 5, alice);

        uint256 listedBalanceBefore = _listedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.depositAsset(address(fractions), asset1, 3);

        assertEq(_listedBalance(address(fractions), asset1, alice), listedBalanceBefore);
    }

    // check that pshop.depositAsset() does not alter pending rewards for caller
    function test_depositAsset_doesntAlterPendingRewardsForCaller() public {
        _doWithdraw(address(fractions), asset1, 5, alice);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 1100e6, 6 hours);

        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.depositAsset(address(fractions), asset1, 3);

        assertEq(pshop.getPendingRewards(address(fractions), asset1, alice), pendingRewardsBefore);
    }

    // check that pshop.depositAsset() does not alter pending rewards for any other user
    function test_depositAsset_doesntAlterPendingRewardsForOtherUsers() public {
        _doWithdraw(address(fractions), asset1, 5, alice);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 1100e6, 1 days);

        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, bob);

        vm.prank(alice);
        pshop.depositAsset(address(fractions), asset1, 3);

        assertEq(pshop.getPendingRewards(address(fractions), asset1, bob), pendingRewardsBefore);
    }

    // check that pshop.depositAsset() does not alter _stakedBalance of any other user
    function test_depositAsset_doesntAlterStakedBalanceOfOtherUsers() public {
        _doWithdraw(address(fractions), asset1, 5, alice);

        uint256 stakedBalanceBefore = _stakedBalance(address(fractions), asset1, bob);

        vm.prank(alice);
        pshop.depositAsset(address(fractions), asset1, 3);

        assertEq(_stakedBalance(address(fractions), asset1, bob), stakedBalanceBefore);
    }

    // check that users don't earn rewards for the period they have withdrawn their assets
    function test_usersDontEarnRewardsWhileWithdrawn() public {
        uint256 amount = 5;
        _doPurchase(listingId1, amount, bob);
        assertEq(_stakedBalance(address(fractions), asset1, bob), amount);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 1100e6, 6 hours);
        skip(_getDrippingPeriod(address(fractions), asset1) + 1 hours);

        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, bob);
        assertGt(pendingRewardsBefore, 0);

        _doWithdraw(address(fractions), asset1, amount, bob);

        // now some more rewards are deposited while bob was exited
        skip(2 hours);
        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 1100e6, 6 hours);

        // now bob comes back during dripping period
        skip(2 hours);
        assertEq(pshop.getPendingRewards(address(fractions), asset1, bob), pendingRewardsBefore);
        vm.prank(bob);
        pshop.depositAsset(address(fractions), asset1, amount);
        // pending rewards should have not changed for bob
        assertEq(pshop.getPendingRewards(address(fractions), asset1, bob), pendingRewardsBefore);

        // however, if bob waits, the dripping will also increase his rewards
        skip(2 hours);
        assertGt(pshop.getPendingRewards(address(fractions), asset1, bob), pendingRewardsBefore);
    }

    // check that on withdraw, the percentage of rewards to another users doesn't
    function test_depositAsset_sameRewardsRateForOtherUsers() public {
        _doPurchase(listingId0, 10, bob);
        _doWithdraw(address(fractions), asset1, 7, bob);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 500e6, 5 days);

        uint256 pendingRewards = pshop.getPendingRewards(address(fractions), asset1, alice);
        skip(1 days);
        uint256 dailyRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice) - pendingRewards;

        vm.prank(bob);
        pshop.depositAsset(address(fractions), asset1, 5);

        pendingRewards = pshop.getPendingRewards(address(fractions), asset1, alice);
        skip(1 days);
        uint256 dailyRewardsAfter = pshop.getPendingRewards(address(fractions), asset1, alice) - pendingRewards;

        assertEq(dailyRewardsBefore, dailyRewardsAfter);
    }
}
