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
    }

    modifier depositRewards(uint256 assetId, uint256 amount) {
        vm.prank(operator);
        pshop.depositRewards(address(fractions), assetId, amount, 6 hours);
        _;
    }

    // check that pshop.withdrawAsset() reverts for non-enabled assets with NotEnoughUnlistedTokens
    function test_withdrawAsset_notEnabled() public {
        vm.prank(bob);
        vm.expectRevert(PinlinkShop.NotEnoughUnlistedTokens.selector);
        pshop.withdrawAsset(address(fractions), asset3, 3, bob);
    }

    // check that pshop.withdrawAsset() reverts if trying to remove assets than the balance with NotEnoughUnlistedTokens
    function test_withdrawAsset_notEnoughUnlistedTokens() public {
        _doPurchase(listingId3, 10, bob);

        vm.prank(bob);
        vm.expectRevert(PinlinkShop.NotEnoughUnlistedTokens.selector);
        pshop.withdrawAsset(address(fractions), asset1, 11, bob);
    }

    // check that phsop.withdrawAsset() reverts if the assets are part of _listedAmount with NotEnoughUnlistedTokens
    function test_withdrawAsset_notEnoughUnlistedTokens2() public {
        uint256 listedBalance = _listedBalance(address(fractions), asset1, alice);
        uint256 stakedBalance = _stakedBalance(address(fractions), asset1, alice);

        uint256 withdrawAmount = listedBalance + 1;
        assertLt(withdrawAmount, stakedBalance);

        vm.prank(alice);
        vm.expectRevert(PinlinkShop.NotEnoughUnlistedTokens.selector);
        pshop.withdrawAsset(address(fractions), asset1, withdrawAmount, alice);
    }

    // check that pshop.withdrawAsset() increases asset balance of caller
    function test_withdrawAsset() public {
        uint256 withdrawAmount = 5;
        uint256 balanceBefore = fractions.balanceOf(alice, asset1);

        vm.prank(alice);
        pshop.withdrawAsset(address(fractions), asset1, withdrawAmount, alice);

        assertEq(fractions.balanceOf(alice, asset1), balanceBefore + withdrawAmount);
    }

    // check that pshop.withdrawAsset() decreases asset balance of pshop contract
    function test_withdrawAsset_decreasesContractBalance() public {
        uint256 withdrawAmount = 5;
        uint256 balanceBefore = fractions.balanceOf(address(pshop), asset1);

        vm.prank(alice);
        pshop.withdrawAsset(address(fractions), asset1, withdrawAmount, alice);

        assertEq(fractions.balanceOf(address(pshop), asset1), balanceBefore - withdrawAmount);
    }

    // check that pshop.withdrawAsset() decreases _stakedBalance of caller
    function test_withdrawAsset_decreasesStakedBalance() public {
        uint256 withdrawAmount = 5;
        uint256 stakedBalanceBefore = _stakedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.withdrawAsset(address(fractions), asset1, withdrawAmount, alice);

        assertEq(_stakedBalance(address(fractions), asset1, alice), stakedBalanceBefore - withdrawAmount);
    }

    // check that pshop.withdrawAsset() does not alter _listedBalance of caller
    function test_withdrawAsset_doesNotAlterListedBalance() public {
        uint256 listedBalanceBefore = _listedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.withdrawAsset(address(fractions), asset1, 5, alice);

        assertEq(_listedBalance(address(fractions), asset1, alice), listedBalanceBefore);
    }

    // check that pshop.withdrawAsset() does not alter pending rewards for caller
    function test_withdrawAsset_doesNotAlterPendingRewards() public depositRewards(asset1, 100e6) {
        skip(5 hours);
        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.withdrawAsset(address(fractions), asset1, 5, alice);

        assertEq(pshop.getPendingRewards(address(fractions), asset1, alice), pendingRewardsBefore);
    }

    // check that pshop.withdrawAsset() does not alter pending rewards for any other user
    function test_withdrawAsset_doesNotAlterPendingRewards2() public depositRewards(asset1, 100e6) {
        skip(5 hours);
        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, bob);

        vm.prank(alice);
        pshop.withdrawAsset(address(fractions), asset1, 5, alice);

        assertEq(pshop.getPendingRewards(address(fractions), asset1, bob), pendingRewardsBefore);
    }

    // check that pshop.withdrawAsset() does not alter _stakedBalance of any other user
    function test_withdrawAsset_doesNotAlterStakedBalance() public {
        uint256 stakedBalanceBefore = _stakedBalance(address(fractions), asset1, bob);

        vm.prank(alice);
        pshop.withdrawAsset(address(fractions), asset1, 5, alice);

        assertEq(_stakedBalance(address(fractions), asset1, bob), stakedBalanceBefore);
    }

    // check that on withdraw, the percentage of rewards to another users doesn't
    function test_withdrawAsset_sameRewardsRateForOtherUsers() public {
        _doPurchase(listingId0, 10, bob);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 500e6, 5 days);

        uint256 pendingRewards = pshop.getPendingRewards(address(fractions), asset1, alice);
        skip(1 days);
        uint256 dailyRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice) - pendingRewards;

        vm.prank(bob);
        pshop.withdrawAsset(address(fractions), asset1, 5, bob);

        pendingRewards = pshop.getPendingRewards(address(fractions), asset1, alice);
        skip(1 days);
        uint256 dailyRewardsAfter = pshop.getPendingRewards(address(fractions), asset1, alice) - pendingRewards;

        assertEq(dailyRewardsBefore, dailyRewardsAfter);
    }

    // check that when assets are withdrawn, the fee receiver receives the equivalent fees
    function test_withdrawAsset_proxyReceiverReceivesFees() public {
        address proxyRewardsAccount = pshop.REWARDS_PROXY_ACCOUNT();

        _doPurchase(listingId0, 10, bob);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 500e6, 5 days);

        uint256 proxyPendingRewards = pshop.getPendingRewards(address(fractions), asset1, proxyRewardsAccount);
        uint256 bobPendingRewards = pshop.getPendingRewards(address(fractions), asset1, bob);
        skip(1 days);
        uint256 proxyDailyRewardsBefore =
            pshop.getPendingRewards(address(fractions), asset1, proxyRewardsAccount) - proxyPendingRewards;
        uint256 bobDailyRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, bob) - bobPendingRewards;

        // bob withdraws everything
        vm.prank(bob);
        pshop.withdrawAsset(address(fractions), asset1, 10, bob);
        assertEq(_stakedBalance(address(fractions), asset1, bob), 0);

        // so now proxyRewardsAccount should receive the same amount of rewards as bob did, and bob should receive zero
        skip(1 days);
        uint256 proxyExtraRewards =
            pshop.getPendingRewards(address(fractions), asset1, proxyRewardsAccount) - proxyDailyRewardsBefore;
        uint256 bobExtraRewards = pshop.getPendingRewards(address(fractions), asset1, bob) - bobDailyRewardsBefore;

        assertEq(proxyExtraRewards, bobDailyRewardsBefore + proxyDailyRewardsBefore);
        assertEq(bobExtraRewards, 0);
    }
}
