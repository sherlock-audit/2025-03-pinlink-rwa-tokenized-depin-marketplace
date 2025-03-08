// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {PinlinkShop, Listing} from "src/marketplaces/pinlinkShop.sol";
import {IPinToken} from "src/interfaces/IPinToken.sol";

contract StakingShop_Purchase_Tests is BaseStakingShopTests {
    bytes32 listingId0;
    bytes32 listingId1;
    bytes32 listingId2;
    bytes32 listingId3;

    modifier depositRewards(uint256 amount) {
        vm.prank(operator);
        pshop.depositRewards(address(fractions), asset1, amount, 6 hours);
        // let some time pass so that some rewards are dripped
        vm.warp(block.timestamp + 4 hours);
        _;
    }

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

    // check that pshop.purchase() reverts for a wrong listingId
    function test_purchase_revertsDuetoWrongListingId() public {
        bytes32 wrongListingId = bytes32(abi.encode("asdfasd"));
        vm.prank(bob);
        vm.expectRevert(PinlinkShop.InvalidListingId.selector);
        pshop.purchase(wrongListingId, 10, 1000e18);
    }

    // check that pshop.purchase() reverts if trying to purchase more fractions than available in the listing
    function test_purchase_revertsDuetoInsufficientFractions() public {
        uint256 listedAmount = _listingAmount(listingId3);
        vm.prank(bob);
        vm.expectRevert(PinlinkShop.NotEnoughTokens.selector);
        pshop.purchase(listingId3, listedAmount + 1, 1000e18);
    }

    // check that pshop.purchase() reverts if attempting to purchase 0 fractions
    function test_purchase_revertsDuetoZeroAmount_zeroMaxTotalPin() public {
        vm.prank(bob);
        vm.expectRevert(PinlinkShop.ExpectedNonZero.selector);
        pshop.purchase(listingId3, 0, 0);
    }
    // check that pshop.purchase() reverts if attempting to purchase 0 fractions

    function test_purchase_revertsDuetoZeroAmount_highMaxTokens() public {
        vm.prank(bob);
        vm.expectRevert(PinlinkShop.ExpectedNonZero.selector);
        pshop.purchase(listingId3, 0, 10000e18);
    }

    // check that pshop.purchase() reverts for a listing with an expired deadline
    function test_purchase_pastTheExpirationDeadline() public {
        Listing memory listing = pshop.getListing(listingId3);

        vm.warp(listing.deadline + 1 hours);

        vm.prank(bob);
        vm.expectRevert(PinlinkShop.ListingDeadlineExpired.selector);
        pshop.purchase(listingId3, 5, 1000e18);
    }

    // check that pshop.purchase() reverts if purchasing exactly on the deadline
    function test_purchase_onTheDeadline() public {
        Listing memory listing = pshop.getListing(listingId3);

        vm.warp(listing.deadline);

        vm.prank(bob);
        vm.expectRevert(PinlinkShop.ListingDeadlineExpired.selector);
        pshop.purchase(listingId3, 5, 1000e18);
    }

    // check that pshop.purchase() reduces the listedBalance of the seller
    function test_purchase_reducesListedBalance() public {
        uint256 listedBalanceBefore = _listedBalance(address(fractions), asset1, alice);

        uint256 buyAmount = 2;
        _doPurchase(listingId3, buyAmount, bob);

        assertEq(_listedBalance(address(fractions), asset1, alice), listedBalanceBefore - buyAmount);
    }

    // check that pshop.purchase() reduces the overall stakedBalance of the seller
    function test_purchase_reducesStakedBalance() public {
        uint256 stakedBalanceBefore = _stakedBalance(address(fractions), asset1, alice);

        uint256 buyAmount = 4;
        _doPurchase(listingId3, buyAmount, bob);

        assertEq(_stakedBalance(address(fractions), asset1, alice), stakedBalanceBefore - buyAmount);
    }

    // check that pshop.purchase() increases the unlistedBalance of the buyer
    function test_purchase_increasesUnlistedBalance() public {
        uint256 unlistedBalanceBefore = _unlistedBalance(address(fractions), asset1, bob);

        uint256 buyAmount = 5;
        _doPurchase(listingId3, buyAmount, bob);

        assertEq(_unlistedBalance(address(fractions), asset1, bob), unlistedBalanceBefore + buyAmount);
    }

    // check that pshop.purchase() PIN token max wallet will be exceeded for non-excluded big sellers
    function test_purchase_sellerNotExcludedFromFeeTriggersMaxPerWalletExceeded() public {
        // set the maxWalletRatio back to its original value to trigger the requirement
        vm.prank(pinOwner);
        IPinToken(address(PIN)).setMaxWalletRatio(100);

        uint256 amount = 10;
        uint256 pinAmount = pshop.getQuoteInTokens(listingId3, amount);
        vm.prank(bob);
        vm.expectRevert("Max wallet will be exceeded.");
        pshop.purchase(listingId3, amount, pinAmount);
    }

    // check that pshop.purchase() reduces listed amount in the listing
    function test_purchase_reducesListedAmount() public {
        uint256 listedAmountBefore = _listingAmount(listingId3);
        uint256 buyAmount = 5;
        _doPurchase(listingId3, buyAmount, bob);

        assertEq(_listingAmount(listingId3), listedAmountBefore - buyAmount);
    }

    // check that pshop.purchase() reverts if total PIN price given by the oracle exceeds the max accepted by buyer
    function test_purchase_revertsDuetoMaxPinAmountExceeded() public {
        uint256 amount = 2;
        uint256 agreedQuoteAmount = pshop.getQuoteInTokens(listingId3, amount);

        // price of PIN drops, so more PIN are required than the initial pinQuoteAmount
        uint256 pinPrice = oracle.convertToUsd(address(PIN), 1e18);

        vm.prank(admin);
        oracle.updateTokenPrice((pinPrice * 0.97 ether) / 1 ether);
        // check that the quote has increased
        assertGt(pshop.getQuoteInTokens(listingId3, amount), agreedQuoteAmount);

        vm.prank(bob);
        vm.expectRevert(PinlinkShop.SlippageExceeded.selector);
        pshop.purchase(listingId3, amount, agreedQuoteAmount);
    }

    // check that pshop.purchase() does not alter the pendingRewards for the seller
    function test_purchase_doesntAlterPendingRewardsForSeller() public depositRewards(100e6) {
        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, alice);
        assertGt(pendingRewardsBefore, 0);

        uint256 amount = 3;
        _doPurchase(listingId3, amount, bob);

        assertEq(pshop.getPendingRewards(address(fractions), asset1, alice), pendingRewardsBefore);
    }

    // check that pshop.purchase() does not alter the pendingRewards for the buyer
    function test_purchase_doesntAlterPendingRewardsForBuyer() public depositRewards(50e6) {
        uint256 pendingRewardsBefore = pshop.getPendingRewards(address(fractions), asset1, bob);
        assertEq(pendingRewardsBefore, 0);

        uint256 amount = 3;
        _doPurchase(listingId3, amount, bob);

        assertEq(pshop.getPendingRewards(address(fractions), asset1, bob), 0);
    }

    // check that pshop.purchase() does not alter the pshop balance of the asset
    function test_purchase_doesntAlterPshopBalance() public depositRewards(100e6) {
        uint256 pshopBalanceBefore = fractions.balanceOf(address(pshop), asset1);
        assertGt(pshopBalanceBefore, 0);

        uint256 amount = 3;
        _doPurchase(listingId3, amount, bob);

        assertEq(fractions.balanceOf(address(pshop), asset1), pshopBalanceBefore);
    }

    // check that pshop.purchase() alters all relevant balance of the asset when executed twice
    function test_purchase_twiceAltersBalancesTwice() public {
        uint256 listedBalanceBefore = _listedBalance(address(fractions), asset1, alice);
        uint256 stakedBalanceBefore = _stakedBalance(address(fractions), asset1, alice);
        uint256 unlistedBalanceBefore = _unlistedBalance(address(fractions), asset1, bob);
        uint256 listedAmountBefore = _listingAmount(listingId3);

        uint256 amount = 3;
        _doPurchase(listingId3, amount, bob);
        _doPurchase(listingId3, amount, bob);

        assertEq(_listedBalance(address(fractions), asset1, alice), listedBalanceBefore - 2 * amount);
        assertEq(_stakedBalance(address(fractions), asset1, alice), stakedBalanceBefore - 2 * amount);
        assertEq(_unlistedBalance(address(fractions), asset1, bob), unlistedBalanceBefore + 2 * amount);
        assertEq(_listingAmount(listingId3), listedAmountBefore - 2 * amount);
    }

    // check that pshop.purchase() transfers PIN a non zero fee to feeReceiver
    function test_purchase_transfersFeeToFeeReceiver() public {
        uint256 balanceBefore = PIN.balanceOf(feeReceiver);
        uint256 amount = 5;
        _doPurchase(listingId3, amount, bob);

        assertGt(PIN.balanceOf(feeReceiver), balanceBefore);
    }

    // check that pshop.purchase() fees are calculated correctly with the PIN price and purchaseFeePerc
    function test_purchase_feesAreCalculatedCorrectly() public {
        uint256 amount = 5;
        uint256 pinAmount = pshop.getQuoteInTokens(listingId3, amount);
        uint256 feeAmount = (pinAmount * pshop.purchaseFeePerc()) / pshop.FEE_DENOMINATOR();

        uint256 balanceBefore = PIN.balanceOf(feeReceiver);
        _doPurchase(listingId3, amount, bob);

        assertApproxEqRel(PIN.balanceOf(feeReceiver), balanceBefore + feeAmount, 1);
    }

    // check that pshop.purchase() transfers the non-fees to the seller
    function test_purchase_transfersPaymentToSeller() public {
        uint256 balanceBefore = PIN.balanceOf(alice);

        uint256 amount = 5;
        uint256 pinAmount = pshop.getQuoteInTokens(listingId3, amount);
        uint256 expectedFees = pshop.purchaseFeePerc() * pinAmount / pshop.FEE_DENOMINATOR();
        uint256 expectedAliceAmount = pinAmount - expectedFees;

        _doPurchase(listingId3, amount, bob);

        assertApproxEqRel(PIN.balanceOf(alice), balanceBefore + expectedAliceAmount, 1);
    }

    // check that pshop.purchase() doesn't alter the PIN balance of pshop contract
    function test_purchase_doesntAlterPshopPinBalance() public {
        uint256 balanceBefore = PIN.balanceOf(address(pshop));

        uint256 amount = 5;
        _doPurchase(listingId3, amount, bob);

        assertEq(PIN.balanceOf(address(pshop)), balanceBefore);
    }

    // check that getQuoteInTokens gives type(uint256).max - 1 if the amount requested is higher than the listing.amount
    function test_getQuoteInTokens_amountHigherThanListingAmount() public view {
        Listing memory listing = pshop.getListing(listingId3);

        assertEq(pshop.getQuoteInTokens(listingId3, listing.amount + 1), type(uint256).max - 1);
    }

    // check that getQuoteInTokens gives type(uint256).max - 2 if the deadline of the listing has passed
    function test_getQuoteInTokens_deadlinePassed() public {
        Listing memory listing = pshop.getListing(listingId3);
        vm.warp(listing.deadline + 1 hours);

        assertEq(pshop.getQuoteInTokens(listingId3, 5), type(uint256).max - 2);
    }

    // check that getQuoteInTokens gives type(uint256).max - 3 if the oracle price is stale
    function test_getQuoteInTokens_oraclePriceStale() public {
        // update the deadline to be past the STALENESS_THRESHOLD
        uint256 stalenessTime = block.timestamp + oracle.STALENESS_THRESHOLD();
        vm.prank(alice);
        pshop.modifyListing(listingId3, 0, stalenessTime + 10 hours);

        // this should make the price stale, but still within the listing deadline
        vm.warp(stalenessTime + 1);
        assertEq(oracle.convertFromUsd(address(PIN), 1e18), 0);
        assertEq(pshop.getQuoteInTokens(listingId3, 5), type(uint256).max - 3);
    }

    // check that a purchase when the oracle price is stale reverts with StaleOraclePrice()
    function test_purchase_revertsDuetoStaleOraclePrice() public {
        // update the deadline to be past the STALENESS_THRESHOLD
        uint256 stalenessTime = block.timestamp + oracle.STALENESS_THRESHOLD();
        vm.prank(alice);
        pshop.modifyListing(listingId3, 0, stalenessTime + 10 hours);

        // this should make the price stale, but still within the listing deadline
        vm.warp(stalenessTime + 1);
        vm.prank(bob);
        vm.expectRevert(PinlinkShop.StaleOraclePrice.selector);
        pshop.purchase(listingId3, 5, 1000e18);
    }

    // check that when a seller purchases to himself, he loses some fees to the feeReceiver
    function test_sellerSelfPurchases_pinLostInFees() public {
        uint256 aliceBalanceBefore = PIN.balanceOf(alice);
        uint256 receiverBalanceBefore = PIN.balanceOf(feeReceiver);
        uint256 totalBalanceBefore = aliceBalanceBefore + receiverBalanceBefore;

        // alice self-purchases
        _doPurchase(listingId3, 5, alice);

        uint256 aliceBalanceAfter = PIN.balanceOf(alice);
        uint256 receiverBalanceAfter = PIN.balanceOf(feeReceiver);
        uint256 totalBalanceAfter = aliceBalanceBefore + receiverBalanceBefore;

        assertEq(totalBalanceBefore, totalBalanceAfter);
        assertLt(aliceBalanceAfter, aliceBalanceBefore);
        assertGt(receiverBalanceAfter, receiverBalanceBefore);
    }

    // check that when the feeReceiver lists and self-purchases no pin tokens are created out of thin air
    function test_feeReceiverSelfPurchases_pinLostInFees() public {
        deal(address(PIN), feeReceiver, 100000e18);
        vm.prank(feeReceiver);
        PIN.approve(address(pshop), type(uint256).max);

        _doPurchase(listingId0, 5, feeReceiver);

        // feeReceiver lists
        vm.prank(feeReceiver);
        bytes32 listingId = pshop.list(address(fractions), asset1, 5, 1000e18, block.timestamp + 3 days);

        uint256 receiverBalanceBefore = PIN.balanceOf(feeReceiver);

        // feeReceiver self-purchases
        _doPurchase(listingId, 5, feeReceiver);

        assertEq(receiverBalanceBefore, PIN.balanceOf(feeReceiver));
    }
}
