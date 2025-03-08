// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {PinlinkShop} from "src/marketplaces/pinlinkShop.sol";
import {DummyOracle} from "src/oracles/DummyOracle.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract StakingShop_AdminSetters_Tests is BaseStakingShopTests {
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

    // check that pshop.setFeeReceiver reverts if called by non-admin
    function testUnauthorizedSetFeeReceiver() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        pshop.setFeeReceiver(address(0x1234));
    }

    // check that pshop.setFeeReeceiver doesn't accept address 0
    function test_setFeeReceiver_zeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert(PinlinkShop.ExpectedNonZero.selector);
        pshop.setFeeReceiver(address(0));
    }

    // check that pshop.setFeeReceiver updates the fee receiver in storage
    function test_setFeeReceiver() public {
        assertEq(pshop.feeReceiver(), feeReceiver);

        vm.startPrank(admin);
        pshop.setFeeReceiver(alice);
        assertEq(pshop.feeReceiver(), alice);
    }

    // check that pshop.setOracle reverts if called by non-admin
    function testUnauthorizedSetOracle() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        pshop.setOracle(address(0x1234));
    }

    // check that pshop.setOracle reverts InvalidOracleInterface when passing an oracle that doesnt implement the required interface
    function test_setOracle_invalidOracleInterface() public {
        vm.startPrank(admin);
        vm.expectRevert(PinlinkShop.InvalidOracleInterface.selector);
        pshop.setOracle(address(fractions));
    }

    // check that pshop.setOracle reverts with InvalidOracle if the price returned has decimals in wrong order of magnitude
    function test_setOracle_invalidPrice() public {
        DummyOracle dummyOracle = new DummyOracle(address(PIN), 0.95 ether);

        dummyOracle.updateTokenPrice(1e5);

        vm.startPrank(admin);
        vm.expectRevert(PinlinkShop.InvalidOraclePrice.selector);
        pshop.setOracle(address(dummyOracle));
    }

    // check that pshop.setOracle updates the oracle address in storage
    function test_setOracle() public {
        assertEq(pshop.oracle(), address(oracle));

        DummyOracle newOracle = new DummyOracle(address(PIN), 0.95 ether);
        vm.startPrank(admin);
        pshop.setOracle(address(newOracle));
        assertEq(pshop.oracle(), address(newOracle));
    }

    // check that pshop.setFee reverts if called by non-admin
    function testUnauthorizedSetFee() public {
        vm.prank(makeAddr("unauthorized"));
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        pshop.setFee(0.1 ether);
    }

    // check that pshop.setFee reverts if setting a fee higher than the allowed MAX_FEE_PERC
    function test_setFee_tooHigh() public {
        uint256 maxFee = pshop.MAX_FEE_PERC();
        vm.startPrank(admin);
        vm.expectRevert(PinlinkShop.InvalidParameter.selector);
        pshop.setFee(maxFee + 1);
    }

    // check that pshop.setFee reverts if setting a fee higher than 100% (redundant)
    function test_setFee_100perc() public {
        vm.startPrank(admin);
        vm.expectRevert(PinlinkShop.InvalidParameter.selector);
        pshop.setFee(10_001);
    }

    // check that pshop.setFee is updated in storage
    function test_setFee() public {
        uint256 initialFee = pshop.purchaseFeePerc();

        vm.startPrank(admin);
        pshop.setFee(2 * initialFee);
        assertEq(pshop.purchaseFeePerc(), 2 * initialFee);
    }

    // check that we can rescue ERC20 tokens sent by mistake to the contract
    function test_rescueERC20() public {
        ERC20Mock token = new ERC20Mock();
        deal(address(token), address(pshop), 1000e18);
        assertEq(token.balanceOf(address(pshop)), 1000e18);
        assertEq(token.balanceOf(admin), 0);

        vm.prank(admin);
        pshop.rescueToken(address(token), admin);

        assertEq(token.balanceOf(address(pshop)), 0);
        assertEq(token.balanceOf(admin), 1000e18);
    }

    // check that we cannot rescue USDC tokens
    function test_rescueUSDC_USDC_notAllowed() public {
        deal(address(USDC), address(pshop), 1000e6);

        assertGt(USDC.balanceOf(address(pshop)), 0);

        vm.prank(admin);
        vm.expectRevert(PinlinkShop.InvalidParameter.selector);
        pshop.rescueToken(address(USDC), admin);
    }
}
