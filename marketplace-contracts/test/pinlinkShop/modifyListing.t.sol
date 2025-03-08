// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {PinlinkShop, Listing} from "src/marketplaces/pinlinkShop.sol";

contract StakingShop_ModifyListing_Tests is BaseStakingShopTests {
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

    // check that pshop.modifyListing() reverts with expired deadline
    function test_modifyListing_revertsDuetoExpiredDeadline() public {
        vm.prank(alice);
        vm.expectRevert(PinlinkShop.DeadlineHasExpiredAlready.selector);
        pshop.modifyListing(listingId, 700e18, block.timestamp - 1 minutes);
    }

    // check that pshop.modifyListing() works fine if current deadline is expired but new deadline is not
    function test_modifyListing_worksFineWithNewDeadline() public {
        Listing memory listing = pshop.getListing(listingId);
        vm.warp(listing.deadline + 1 days);

        uint256 newDeadline = listing.deadline + 4 days;

        vm.prank(alice);
        pshop.modifyListing(listingId, 800e18, newDeadline);

        Listing memory updatedListing = pshop.getListing(listingId);
        assertEq(updatedListing.usdPricePerFraction, 800e18);
        assertEq(updatedListing.deadline, newDeadline);
    }

    // check that pshop.modifyListing() reverts with seller is not sender
    function test_modifyListing_revertsDuetoSellerIsNotSender() public {
        vm.prank(bob);
        vm.expectRevert(PinlinkShop.SenderIsNotSeller.selector);
        pshop.modifyListing(listingId, 700e18, block.timestamp + 5 days);
    }

    // check that pshop.modifyListing() reverts for wrong listingId
    function test_modifyListing_revertsDuetoWrongListingId() public {
        vm.prank(alice);
        vm.expectRevert(PinlinkShop.InvalidListingId.selector);
        pshop.modifyListing(bytes32(0), 700e18, block.timestamp + 5 days);
    }

    // check that pshop.modifyListing() doesn't alter _listedBalance and _stakedBalance for caller
    function test_modifyListing_doesntAlterBalances() public {
        uint256 listedBalanceBefore = _listedBalance(address(fractions), asset1, alice);
        uint256 stakedBalanceBefore = _stakedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.modifyListing(listingId, 700e18, block.timestamp + 5 days);

        assertEq(_listedBalance(address(fractions), asset1, alice), listedBalanceBefore);
        assertEq(_stakedBalance(address(fractions), asset1, alice), stakedBalanceBefore);
    }

    // check functionality of only updating price
    function test_modifyListing_onlyUpdatePrice() public {
        Listing memory listing = pshop.getListing(listingId);
        uint256 newPrice = 700e18;

        vm.prank(alice);
        pshop.modifyListing(listingId, newPrice, 0);

        Listing memory updatedListing = pshop.getListing(listingId);
        assertEq(updatedListing.usdPricePerFraction, newPrice);
        assertEq(updatedListing.deadline, listing.deadline);
    }

    // check functionality of only updating deadline
    function test_modifyListing_onlyUpdateDeadline() public {
        Listing memory listing = pshop.getListing(listingId);
        uint256 newDeadline = listing.deadline + 4 days;

        vm.prank(alice);
        pshop.modifyListing(listingId, 0, newDeadline);

        Listing memory updatedListing = pshop.getListing(listingId);
        assertEq(updatedListing.usdPricePerFraction, listing.usdPricePerFraction);
        assertEq(updatedListing.deadline, newDeadline);
    }

    // check that pshop.modifyListing() updates both price and deadline
    function test_modifyListing_updatePriceAndDeadline() public {
        Listing memory listing = pshop.getListing(listingId);
        uint256 newPrice = 1234e18;
        uint256 newDeadline = listing.deadline + 4 days;

        vm.prank(alice);
        pshop.modifyListing(listingId, newPrice, newDeadline);

        Listing memory updatedListing = pshop.getListing(listingId);
        assertEq(updatedListing.usdPricePerFraction, newPrice);
        assertEq(updatedListing.deadline, newDeadline);
    }
}
