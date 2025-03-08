// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {CentralizedOracle} from "src/oracles/CentralizedOracle.sol";
import {IPinlinkOracle} from "src/oracles/IPinlinkOracle.sol";

contract CentralizedOracleTest is Test {
    CentralizedOracle public oracle;
    ERC20Mock public token;

    address admin = makeAddr("admin");

    function setUp() public {
        vm.warp(12341234);
        token = new ERC20Mock();

        vm.prank(admin);
        oracle = new CentralizedOracle(address(token), 1e18);
    }

    function test_deploy_invalidPrice() public {
        vm.expectRevert(CentralizedOracle.PinlinkCentralizedOracle__InvalidPrice.selector);
        new CentralizedOracle(address(token), 0);

        vm.expectRevert(CentralizedOracle.PinlinkCentralizedOracle__InvalidPrice.selector);
        new CentralizedOracle(address(token), 24);
    }

    function test_updatePrice_lastPriceUpdateTimestamp() public {
        assertEq(oracle.lastPriceUpdateTimestamp(), 12341234);

        skip(1 hours);
        vm.prank(admin);
        oracle.updateTokenPrice(2e18);

        assertEq(oracle.lastPriceUpdateTimestamp(), 12341234 + 1 hours);
    }

    function test_updateTokenPrice_unauthorized() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        oracle.updateTokenPrice(2e18);
    }

    function test_updateTokenPrice_zeroPrice() public {
        vm.expectRevert(CentralizedOracle.PinlinkCentralizedOracle__NewPriceTooLow.selector);
        vm.prank(admin);
        oracle.updateTokenPrice(0);
    }

    function test_updateTokenPrice() public {
        vm.prank(admin);
        oracle.updateTokenPrice(2e18);
        assertEq(oracle.convertToUsd(address(token), 1e18), 2e18);
    }

    function test_updateTokenPrice_twice() public {
        vm.prank(admin);
        oracle.updateTokenPrice(2e18);
        assertEq(oracle.convertToUsd(address(token), 1e18), 2e18);

        vm.prank(admin);
        oracle.updateTokenPrice(3e18);
        assertEq(oracle.convertToUsd(address(token), 1e18), 3e18);
    }

    function test_updateTokenPrice_priceTooLow() public {
        vm.expectRevert(CentralizedOracle.PinlinkCentralizedOracle__NewPriceTooLow.selector);
        vm.prank(admin);
        oracle.updateTokenPrice(0.005e18);
    }

    function test_updateTokenPrice_priceTooHigh() public {
        vm.expectRevert(CentralizedOracle.PinlinkCentralizedOracle__NewPriceTooHigh.selector);
        vm.prank(admin);
        oracle.updateTokenPrice(100e18);
    }

    function test_readTokenPriceInUsd() public view {
        assertEq(oracle.convertToUsd(address(token), 1e18), 1e18);
    }

    function test_convertToUsd_stalePrice() public {
        skip(8 days);
        assertEq(oracle.convertToUsd(address(token), 1e18), 0);
    }

    function test_convertToUsd_wrongToken() public {
        address otherToken = makeAddr("other-token");
        vm.expectRevert(IPinlinkOracle.PinlinkCentralizedOracle__InvalidToken.selector);
        oracle.convertToUsd(address(otherToken), 1e18);
    }

    function test_convertToUsd_updated() public {
        assertEq(oracle.convertToUsd(address(token), 1e18), 1e18);

        vm.prank(admin);
        oracle.updateTokenPrice(2e18);

        assertEq(oracle.convertToUsd(address(token), 1e18), 2e18);
    }

    function test_convertFromUsd_wrongToken() public {
        address otherToken = makeAddr("other-token");
        vm.expectRevert(IPinlinkOracle.PinlinkCentralizedOracle__InvalidToken.selector);
        oracle.convertFromUsd(address(otherToken), 1e18);
    }

    function test_convertFromUsd_stalePrice() public {
        skip(8 days);
        assertEq(oracle.convertFromUsd(address(token), 1e18), 0);
    }

    function convertToUsd_decimals() public {
        oracle.updateTokenPrice(2.1234123412341e18);

        assertEq(oracle.convertToUsd(address(token), 0.0001e18), 0.00021234123412341e18);
    }

    function convertFromUsd_decimals() public {
        oracle.updateTokenPrice(2.1234123412341e18);

        assertEq(oracle.convertFromUsd(address(token), 0.0001e18), 0.00021234123412341e18);
    }

    function test_convertToUsd_lowPrice() public view {
        assertGt(oracle.convertToUsd(address(token), 1000), 0);
    }

    function test_quote_returnTrip() public view {
        // USD -> token -> USD
        assertEq(oracle.convertToUsd(address(token), oracle.convertFromUsd(address(token), 1.2345e18)), 1.2345e18);
    }

    // check that oracle.supportsInterface returns True for IPinlinkOracle interface
    function test_supportsInterface() public view {
        assert(oracle.supportsInterface(type(IPinlinkOracle).interfaceId));
    }

    // check that oracle.supportsInterface returns False for another random interface
    function test_supportsInterface_false() public view {
        assert(!oracle.supportsInterface(type(Ownable).interfaceId));
    }
}
