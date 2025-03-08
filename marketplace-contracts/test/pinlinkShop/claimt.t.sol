// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {PinlinkShop} from "src/marketplaces/pinlinkShop.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract StakingShop_ClaimRewards_Tests is BaseStakingShopTests {
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
    }

    modifier depositRewards(uint256 assetId, uint256 amount) {
        vm.prank(operator);
        pshop.depositRewards(address(fractions), assetId, amount, 6 hours);
        _;
    }

    function _assetsIdsArray() internal view returns (uint256[] memory) {
        uint256[] memory assets = new uint256[](2);
        assets[0] = asset1;
        assets[1] = asset2;
        return assets;
    }

    // check that claimRewards with no rewards deposited yields nothing
    function test_claimRewards_noRewards() public {
        uint256 balanceBefore = USDC.balanceOf(alice);
        pshop.claimRewards(address(fractions), asset1);
        assertEq(USDC.balanceOf(alice), balanceBefore);
    }

    // check that pshop.claimRewards() increases USDC balance of claimor if penddingRewards > 0
    function test_claimRewards() public depositRewards(asset1, 100e6) {
        skip(1 hours);
        uint256 pendingRewards = pshop.getPendingRewards(address(fractions), asset1, alice);
        uint256 balanceBefore = USDC.balanceOf(alice);

        vm.prank(alice);
        pshop.claimRewards(address(fractions), asset1);

        assertEq(USDC.balanceOf(alice), balanceBefore + pendingRewards);
    }

    // check that pshop.claimRewards() decreases USDC balance of contract
    function test_claimRewards_decreasesContractBalance() public depositRewards(asset1, 100e6) {
        skip(1 hours);
        uint256 pendingRewards = pshop.getPendingRewards(address(fractions), asset1, alice);
        uint256 balanceBefore = USDC.balanceOf(address(pshop));

        vm.prank(alice);
        pshop.claimRewards(address(fractions), asset1);

        assertEq(USDC.balanceOf(address(pshop)), balanceBefore - pendingRewards);
    }

    // check that pshop.claimRewards() twice does not alter balances twice for neither pshop or alice
    function test_claimRewards_twice() public depositRewards(asset1, 100e6) {
        skip(4 hours);
        uint256 pendingRewards = pshop.getPendingRewards(address(fractions), asset1, alice);
        uint256 balanceBefore = USDC.balanceOf(alice);
        uint256 balanceBeforePshop = USDC.balanceOf(address(pshop));

        vm.prank(alice);
        pshop.claimRewards(address(fractions), asset1);
        pshop.claimRewards(address(fractions), asset1);

        assertEq(USDC.balanceOf(alice), balanceBefore + pendingRewards);
        assertEq(USDC.balanceOf(address(pshop)), balanceBeforePshop - pendingRewards);
    }

    // check that pshop.claimRewardsMultiple() with no pending rewards deposited yields nothing
    function test_claimRewardsMultiple_noRewards() public {
        uint256 balanceBefore = USDC.balanceOf(alice);
        uint256[] memory assetIds = _assetsIdsArray();
        pshop.claimRewardsMultiple(address(fractions), assetIds);
        assertEq(USDC.balanceOf(alice), balanceBefore);
    }

    // check that pshop.claimRewardsMultiple() increases USDC balance of claimor if penddingRewards > 0
    function test_claimRewardsMultiple_increaseClaimorBalance()
        public
        depositRewards(asset1, 100e6)
        depositRewards(asset2, 1000e6)
    {
        skip(1 hours);

        uint256 pendingRewards1 = pshop.getPendingRewards(address(fractions), asset1, alice);
        uint256 pendingRewards2 = pshop.getPendingRewards(address(fractions), asset2, alice);
        uint256 balanceBefore = USDC.balanceOf(alice);

        vm.prank(alice);
        uint256[] memory assetIds = _assetsIdsArray();
        pshop.claimRewardsMultiple(address(fractions), assetIds);

        assertEq(USDC.balanceOf(alice), balanceBefore + pendingRewards1 + pendingRewards2);
    }

    // check that pshop.claimRewardsMultiple() decreases USDC balance of contract
    function test_claimRewardsMultiple_decreasesContractBalance()
        public
        depositRewards(asset1, 100e6)
        depositRewards(asset2, 1000e6)
    {
        skip(10 hours);

        uint256 pendingRewards1 = pshop.getPendingRewards(address(fractions), asset1, alice);
        uint256 pendingRewards2 = pshop.getPendingRewards(address(fractions), asset2, alice);
        uint256 balanceBefore = USDC.balanceOf(address(pshop));

        vm.prank(alice);
        uint256[] memory assetIds = _assetsIdsArray();
        pshop.claimRewardsMultiple(address(fractions), assetIds);

        assertEq(USDC.balanceOf(address(pshop)), balanceBefore - pendingRewards1 - pendingRewards2);
    }

    // check that pshop.claimRewardsMultiple() with a repeated assetId doesnt alter balance twice for that assetId
    function test_claimRewardsMultiple_twice() public depositRewards(asset1, 100e6) depositRewards(asset2, 1000e6) {
        skip(10 hours);

        uint256 pendingRewards1 = pshop.getPendingRewards(address(fractions), asset1, alice);
        uint256 pendingRewards2 = pshop.getPendingRewards(address(fractions), asset2, alice);
        uint256 balanceBefore = USDC.balanceOf(alice);
        uint256 balanceBeforePshop = USDC.balanceOf(address(pshop));

        // an array with the same asset twice
        uint256[] memory assetIds = new uint256[](2);
        assetIds[0] = asset1;
        assetIds[1] = asset1;
        vm.prank(alice);
        pshop.claimRewardsMultiple(address(fractions), assetIds);

        assertEq(USDC.balanceOf(alice), balanceBefore + pendingRewards1);
        assertEq(USDC.balanceOf(address(pshop)), balanceBeforePshop - pendingRewards1);
        assertEq(pshop.getPendingRewards(address(fractions), asset1, alice), 0);
        assertEq(pshop.getPendingRewards(address(fractions), asset2, alice), pendingRewards2);
    }

    // check pshop.claimUnassignedRewards() reverts if called by other than admin or feeReceiver
    function test_claimUnassignedRewards_unauthorized() public {
        vm.prank(alice);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        pshop.claimUnassignedRewards(address(fractions), asset1, alice);
    }

    function test_claimUnassignedRewards_feeReceiverOrAdmin() public {
        vm.prank(operator);
        pshop.claimUnassignedRewards(address(fractions), asset1, alice);

        vm.prank(admin);
        pshop.claimUnassignedRewards(address(fractions), asset1, alice);
    }

    function test_claimUnassignedRewards_balanceChanges() public {
        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 1000e6, 6 days);

        skip(10 hours);

        // this should give some rewards to the proxy rewards account
        vm.prank(alice);
        pshop.withdrawAsset(address(fractions), asset1, 5, alice);

        skip(2 days);
        assertGt(pshop.getPendingRewards(address(fractions), asset1, pshop.REWARDS_PROXY_ACCOUNT()), 0);

        vm.startPrank(alice);
        fractions.setApprovalForAll(address(pshop), true);
        pshop.depositAsset(address(fractions), asset1, 5);
        vm.stopPrank();

        uint256 pendingForProxy = pshop.getPendingRewards(address(fractions), asset1, pshop.REWARDS_PROXY_ACCOUNT());
        uint256 balanceBeforeAdmin = USDC.balanceOf(admin);
        uint256 balanceBeforePshop = USDC.balanceOf(address(pshop));

        vm.prank(operator);
        pshop.claimUnassignedRewards(address(fractions), asset1, admin);

        assertEq(USDC.balanceOf(admin), balanceBeforeAdmin + pendingForProxy);
        assertEq(USDC.balanceOf(address(pshop)), balanceBeforePshop - pendingForProxy);
    }
}
