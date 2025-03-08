// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {PinlinkShop} from "src/marketplaces/pinlinkShop.sol";

contract StakingShop_Delisting_Tests is BaseStakingShopTests {
    bytes32 listingId;

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        pshop.enableAsset(address(fractions), asset1, admin);
        bytes32 initialListingId = pshop.list(address(fractions), asset1, 100, 1050e18, block.timestamp + 5 days);
        vm.stopPrank();

        _doPurchase(initialListingId, 50, alice);
        vm.prank(alice);
        listingId = pshop.list(address(fractions), asset1, 30, 900e18, block.timestamp + 3 days);
    }

    function test_setupConditions() public view {
        assertEq(_stakedBalance(address(fractions), asset1, alice), 50);
    }

    // check that pshop.delist() alters the listedBalance and unlistedBalance
    function test_delist() public {
        uint256 listedBalanceBefore = _listedBalance(address(fractions), asset1, alice);

        uint256 delistAmount = 10;
        vm.prank(alice);
        pshop.delist(listingId, delistAmount);

        assertEq(_listedBalance(address(fractions), asset1, alice), listedBalanceBefore - delistAmount);
    }

    // check that pshop.delist() doesn't alter the _stakedBalance of the caller
    function test_delist_doesntAlterStakedBalance() public {
        uint256 stakedBalanceBefore = _stakedBalance(address(fractions), asset1, alice);

        uint256 delistAmount = 10;
        vm.prank(alice);
        pshop.delist(listingId, delistAmount);

        assertEq(_stakedBalance(address(fractions), asset1, alice), stakedBalanceBefore);
    }

    // check that pshop.delist() doesn't alter the pendingRewards for the caller
    function test_delist_doesntAlterPendingRewards() public {
        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, 100e6, 12 hours);

        skip(1 days);
        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice);
        assertGt(pendingRewardsBefore, 0);

        uint256 delistAmount = 10;
        vm.prank(alice);
        pshop.delist(listingId, delistAmount);

        assertEq(pshop.getPendingRewards(address(fractions), asset1, alice), pendingRewardsBefore);
    }

    // check that pshop.delist() reverts with authorized if caller is not the seller of the listingId
    function test_delistNotSeller() public {
        vm.expectRevert(PinlinkShop.SenderIsNotSeller.selector);
        vm.prank(bob);
        pshop.delist(listingId, 10);
    }

    // check that pshop.delist() reverts if trying to delist more amount than is currently listed
    function test_delistMoreThanListed() public {
        uint256 listedBalance = _listedBalance(address(fractions), asset1, alice);
        vm.expectRevert(PinlinkShop.NotEnoughTokens.selector);
        vm.prank(alice);
        pshop.delist(listingId, listedBalance + 1);
    }

    // check that delisting from invalidId reverts
    function test_delistInvalidId() public {
        bytes32 nonExistingListingId = bytes32(abi.encode("asdfad"));
        vm.expectRevert(PinlinkShop.InvalidListingId.selector);
        vm.prank(alice);
        pshop.delist(nonExistingListingId, 10);
    }

    // chech that delisting 0 amount reverts with ExpectedNonZero
    function test_delistZeroAmount() public {
        vm.expectRevert(PinlinkShop.ExpectedNonZero.selector);
        vm.prank(alice);
        pshop.delist(listingId, 0);
    }

    // check that delist with type(uint256).max delists all listed amount of listing
    function test_delistAll() public {
        uint256 listedAmountBefore = _listingAmount(listingId);
        assertGt(listedAmountBefore, 0);

        vm.prank(alice);
        pshop.delist(listingId, type(uint256).max);

        assertEq(_listingAmount(listingId), 0);
    }
}
