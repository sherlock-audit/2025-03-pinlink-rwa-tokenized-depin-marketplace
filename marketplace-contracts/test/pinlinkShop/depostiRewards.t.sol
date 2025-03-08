// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import "src/marketplaces/streams.sol";

contract StakingShop_DepositRewards_Tests is BaseStakingShopTests {
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
        _doPurchase(listingId0, 30, alice);
        vm.prank(alice);
        listingId3 = pshop.list(address(fractions), asset1, 25, 900e18, block.timestamp + 3 days);

        _doPurchase(listingId3, 5, bob);
        _doPurchase(listingId1, 5, bob);
    }

    function _totalPendingRewards(address _fractional, uint256 assetId) internal view returns (uint256 totalPending) {
        // assets are enabled with admin as receiver
        uint256 adminRewards = pshop.getPendingRewards(_fractional, assetId, admin);
        uint256 bobRewards = pshop.getPendingRewards(_fractional, assetId, bob);
        uint256 aliceRewards = pshop.getPendingRewards(_fractional, assetId, alice);
        totalPending = adminRewards + bobRewards + aliceRewards;
    }

    // check that pshop.depositRewards() increases the rewardToken balance of the contract
    function test_depositRewards_increasesRewardTokenBalance() public {
        uint256 amount = 100e6;
        uint256 balanceBefore = USDC.balanceOf(address(pshop));

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 1 days);

        assertEq(USDC.balanceOf(address(pshop)), balanceBefore + amount);
    }

    // check that pshop.depositRewards() decreases the rewardToken balance of the operator
    function test_depositRewards_decreasesAdminRewardTokenBalance() public {
        uint256 amount = 10e6;
        uint256 balanceBefore = USDC.balanceOf(operator);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 6 hours);

        assertEq(USDC.balanceOf(operator), balanceBefore - amount);
    }

    // check that pshop.depositRewards() reverts if pshop.DRIPPING_PERIOD() hasn't passed since last rewards deposit
    function test_depositRewards_revertsDuetoInsufficientTime() public {
        uint256 amount = 100e6;
        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 6 hours);
        // pshop.drippingPeriod() is about 6 hours
        skip(1 hours);
        vm.prank(operator);
        vm.expectRevert(PinlinkRewards_DepositRewardsTooEarly.selector);
        pshop.depositRewards(address(fractions), asset1, amount, 6 hours);
    }

    // check that pshop.depositRewards() reverts if rewards deposited is tooooo small
    function test_depositRewards_revertsDuetoInsufficientAmount() public {
        (uint256 MIN_REWARDS_DEPOSIT_AMOUNT,,,) = pshop.getRewardsConstants();
        uint256 amount = MIN_REWARDS_DEPOSIT_AMOUNT - 1;
        vm.prank(operator);
        vm.expectRevert(PinlinkRewards_AmountTooLow.selector);
        pshop.depositRewards(address(fractions), asset1, amount, 2 days);
    }

    // check that pshop.depositRewards() reverts if depositing for a non-enabled asset
    function test_depositRewards_revertsDuetoAssetNotEnabled() public {
        uint256 amount = 100e6;
        vm.prank(operator);
        vm.expectRevert(PinlinkRewards_AssetNotEnabled.selector);
        pshop.depositRewards(address(fractions), asset3, amount, 1 days);
    }

    // check that pshop.depositRewards() reverts if called by unauthorized role
    function test_depositRewards_revertsDuetoUnauthorizedRole() public {
        uint256 amount = 100e6;
        vm.prank(bob);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        pshop.depositRewards(address(fractions), asset1, amount, 6 hours);
    }

    // check that pshop.depositRewards() does not alter the total pending rewards immediately after deposit
    function test_depositRewards_doesntAlterPendingRewardsImmediately() public {
        uint256 amount = 100e6;
        uint256 pendingRewardsBefore = _totalPendingRewards(address(fractions), asset1);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 12 hours);

        assertEq(_totalPendingRewards(address(fractions), asset1), pendingRewardsBefore);
    }

    // check that pshop.depositRewards() does not alter the individual (alice) pending rewards immediately after deposit
    function test_depositRewards_doesntAlterIndividualPendingRewardsImmediately() public {
        uint256 amount = 100e6;
        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 12 hours);

        assertEq(pshop.getPendingRewards(address(fractions), asset1, alice), pendingRewardsBefore);
    }

    // check that total pending rewards increases by 25% after 25% of the dripping period has passed
    function test_depositRewards_increasesTotalPendingRewardsAfter25PercentOfDrippingPeriod() public {
        uint256 amount = 100e6;
        uint256 pendingRewardsBefore = _totalPendingRewards(address(fractions), asset1);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 18 hours);
        skip(_getDrippingPeriod(address(fractions), asset1) / 4);

        assertEq(_totalPendingRewards(address(fractions), asset1), pendingRewardsBefore + (amount / 4));
    }

    // check that individual (alice) pending rewards increases by 25% after 25% of the dripping period has passed
    function test_depositRewards_increasesIndividualPendingRewardsAfter25PercentOfDrippingPeriod() public {
        // calculate alice's share
        uint256 aliceBalance = _stakedBalance(address(fractions), asset1, alice);
        uint256 assetSupply = fractions.balanceOf(address(pshop), asset1);

        uint256 amount = 100e6;
        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 2 days);
        skip(_getDrippingPeriod(address(fractions), asset1) / 4);

        uint256 expectedAliceRewards = amount * aliceBalance / assetSupply;
        assertEq(
            pshop.getPendingRewards(address(fractions), asset1, alice), pendingRewardsBefore + expectedAliceRewards / 4
        );
    }

    // check that total pending rewards matches the full deposited amount after DRIPPING PERIOD has passed
    function test_depositRewards_increasesTotalPendingRewardsAfterFullDrippingPeriod() public {
        uint256 amount = 100e6;
        uint256 pendingRewardsBefore = _totalPendingRewards(address(fractions), asset1);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 4 days);
        skip(_getDrippingPeriod(address(fractions), asset1));

        assertEq(_totalPendingRewards(address(fractions), asset1), pendingRewardsBefore + amount);
    }

    // check that total pending rewards matches the full deposited amount after DRIPPING PERIOD has passed. Repeat the logic twice
    function test_depositRewards_increasesTotalPendingRewardsAfterFullDrippingPeriodTwice() public {
        uint256 amount = 10e6;
        uint256 pendingRewardsBefore = _totalPendingRewards(address(fractions), asset1);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 2 days);
        skip(_getDrippingPeriod(address(fractions), asset1) + 1 hours);
        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 2 days);
        skip(_getDrippingPeriod(address(fractions), asset1) + 1);

        assertEq(_totalPendingRewards(address(fractions), asset1), pendingRewardsBefore + 2 * amount);
    }

    // check that individual (alice) pending rewards matches her share of the full deposited amount after DRIPPING PERIOD has passed. Repeat the logic twice
    function test_depositRewards_increasesIndividualPendingRewardsAfterFullDrippingPeriodTwice() public {
        // calculate alice's share
        uint256 aliceBalance = _stakedBalance(address(fractions), asset1, alice);
        uint256 assetSupply = fractions.balanceOf(address(pshop), asset1);

        uint256 amount = 10e6;
        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 1 days);
        skip(_getDrippingPeriod(address(fractions), asset1) + 1 hours);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 1 days);
        skip(_getDrippingPeriod(address(fractions), asset1));

        uint256 expectedAliceRewards = amount * aliceBalance / assetSupply;
        assertEq(
            pshop.getPendingRewards(address(fractions), asset1, alice), pendingRewardsBefore + 2 * expectedAliceRewards
        );
    }

    // check that total pending rewards of an asset with no deposit has the total pending rewards unchanged
    function test_depositRewards_doesntAlterTotalPendingRewardsForAssetWithNoDeposit() public {
        uint256 amount = 100e6;
        uint256 pendingRewardsBefore = _totalPendingRewards(address(fractions), asset2);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 12 hours);

        skip(24 hours);
        assertEq(_totalPendingRewards(address(fractions), asset2), pendingRewardsBefore);
    }

    // check that depositing with too short drippingPeriod reverts PinlinkRewards_DrippingPeriodTooShort
    function test_depositRewards_revertsDuetoDrippingPeriodTooShort() public {
        (,, uint256 minDrippingPeriod,) = pshop.getRewardsConstants();

        vm.startPrank(operator);
        vm.expectRevert(PinlinkRewards_DrippingPeriodTooShort.selector);
        pshop.depositRewards(address(fractions), asset1, 900e6, minDrippingPeriod - 1);

        pshop.depositRewards(address(fractions), asset1, 900e6, minDrippingPeriod);
    }

    // check that depositing with too long drippingPeriod reverts PinlinkRewards_DrippingPeriodTooLong
    function test_depositRewards_revertsDuetoDrippingPeriodTooLong() public {
        (,,, uint256 maxDrippingPeriod) = pshop.getRewardsConstants();
        vm.prank(operator);
        vm.expectRevert(PinlinkRewards_DrippingPeriodTooLong.selector);
        pshop.depositRewards(address(fractions), asset1, 900e6, maxDrippingPeriod + 1);

        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 900e6, maxDrippingPeriod);
    }

    // check that depositing while an ongoing dripping period reverts PinlinkRewards_DepositRewardsTooEarly
    function test_depositRewards_revertsDuetoDepositRewardsTooEarly() public {
        vm.startPrank(operator);
        pshop.depositRewards(address(fractions), asset1, 100e6, 3 days);

        skip(3 days - 1);

        vm.expectRevert(PinlinkRewards_DepositRewardsTooEarly.selector);
        pshop.depositRewards(address(fractions), asset1, 100e6, 6 hours);
    }
}
