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
        vm.startPrank(alice);
        listingId3 = pshop.list(address(fractions), asset1, 15, 900e18, block.timestamp + 3 days);
        pshop.withdrawAsset(address(fractions), asset1, 10, alice);
        // required to deposit assets
        fractions.setApprovalForAll(address(pshop), true);
        vm.stopPrank();
    }

    // check that depositAndList() decreases balance of caller
    function test_depositAndList_stakedBalance() public {
        uint256 amount = 3;
        uint256 balanceBefore = fractions.balanceOf(alice, asset1);

        vm.prank(alice);
        pshop.depositAndList(address(fractions), asset1, amount, 987e18, block.timestamp + 1 days);

        assertEq(fractions.balanceOf(alice, asset1), balanceBefore - amount);
    }

    // check that depositAndList() increases balance of pshop
    function test_depositAndList_listedBalance() public {
        uint256 amount = 3;
        uint256 balanceBefore = fractions.balanceOf(address(pshop), asset1);

        vm.prank(alice);
        pshop.depositAndList(address(fractions), asset1, amount, 987e18, block.timestamp + 1 days);

        assertEq(fractions.balanceOf(address(pshop), asset1), balanceBefore + amount);
    }

    // check that depositAndList() increases _stakedBalance of caller
    function test_depositAndList_stakedBalanceOfCaller() public {
        uint256 amount = 3;
        uint256 balanceBefore = _stakedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.depositAndList(address(fractions), asset1, amount, 987e18, block.timestamp + 1 days);

        assertEq(_stakedBalance(address(fractions), asset1, alice), balanceBefore + amount);
    }

    // check that depositAndList() increases _listedBalance of caller
    function test_depositAndList_listedBalanceOfCaller() public {
        uint256 amount = 3;
        uint256 balanceBefore = _listedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.depositAndList(address(fractions), asset1, amount, 987e18, block.timestamp + 1 days);

        assertEq(_listedBalance(address(fractions), asset1, alice), balanceBefore + amount);
    }

    // check that depositAndList() does not alter _unlistedBalance of caller
    function test_depositAndList_unlistedBalanceOfCaller() public {
        uint256 amount = 3;
        uint256 balanceBefore = _unlistedBalance(address(fractions), asset1, alice);

        vm.prank(alice);
        pshop.depositAndList(address(fractions), asset1, amount, 987e18, block.timestamp + 1 days);

        assertEq(_unlistedBalance(address(fractions), asset1, alice), balanceBefore);
    }

    // check that depositAndList() ends up with the same state as depositAsset() and list() (all balances are the same)
    function test_depositAndList_sameStateAsDepositAndList() public {
        uint256 amount = 3;
        uint256 pricePerFraction = 1009e18;
        uint256 deadline = block.timestamp + 2 days;

        uint256 snapshotId = vm.snapshotState();
        vm.prank(alice);
        pshop.depositAndList(address(fractions), asset1, amount, pricePerFraction, deadline);

        uint256 aliceBalanceSingleTx = fractions.balanceOf(alice, asset1);
        uint256 pshopBalanceSingleTx = fractions.balanceOf(address(pshop), asset1);
        uint256 stakedBalanceSingleTx = _stakedBalance(address(fractions), asset1, alice);
        uint256 listedBalanceSingleTx = _listedBalance(address(fractions), asset1, alice);
        uint256 unlistedBalanceSingleTx = _unlistedBalance(address(fractions), asset1, alice);

        vm.revertToState(snapshotId);

        vm.startPrank(alice);
        pshop.depositAsset(address(fractions), asset1, amount);
        pshop.list(address(fractions), asset1, amount, pricePerFraction, deadline);
        vm.stopPrank();

        assertEq(aliceBalanceSingleTx, fractions.balanceOf(alice, asset1));
        assertEq(pshopBalanceSingleTx, fractions.balanceOf(address(pshop), asset1));
        assertEq(stakedBalanceSingleTx, _stakedBalance(address(fractions), asset1, alice));
        assertEq(listedBalanceSingleTx, _listedBalance(address(fractions), asset1, alice));
        assertEq(unlistedBalanceSingleTx, _unlistedBalance(address(fractions), asset1, alice));
    }
}
