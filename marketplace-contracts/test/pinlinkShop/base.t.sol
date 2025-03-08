// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {FractionalAssets} from "src/fractional/FractionalAssets.sol";
import {PinlinkShop, Listing} from "src/marketplaces/pinlinkShop.sol";
import {Test} from "forge-std/Test.sol";
import {IPinToken} from "src/interfaces/IPinToken.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {DummyOracle} from "src/oracles/DummyOracle.sol";
import {CentralizedOracle} from "src/oracles/CentralizedOracle.sol";
import {ERC1155, ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

contract BaseStakingShopTests is Test {
    FractionalAssets fractions;
    PinlinkShop pshop;
    CentralizedOracle oracle;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");

    address feeReceiver = makeAddr("feeReceiver");

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 asset1 = 111;
    uint256 asset2 = 222;
    uint256 asset3 = 333;

    /// mainnet owner of PIN token
    address pinOwner = 0x29c3b3588B30be185dC7E54dcb09fa82d8442bCB;

    // mainnet PIN
    IERC20 PIN = IERC20(0x2e44f3f609ff5aA4819B323FD74690f07C3607c4);
    // mainnet USDC is the `rewardToken` in pshop
    IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public virtual {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(MAINNET_RPC_URL, 21947000);

        vm.startPrank(admin);
        oracle = new CentralizedOracle(address(PIN), 0.95 ether);

        fractions = new FractionalAssets("https://metadata.pinlink.dev/metadata/0xaaaa/");
        fractions.mint(asset1, admin, 100);
        fractions.mint(asset2, admin, 100);
        fractions.mint(asset3, admin, 100);
        pshop = new PinlinkShop(address(PIN), address(oracle), address(USDC));
        fractions.setApprovalForAll(address(pshop), true);
        pshop.grantRole(pshop.OPERATOR_ROLE(), operator);
        pshop.setFeeReceiver(feeReceiver);
        vm.stopPrank();

        // the operator is who will deposit/distribute rewards in the contract
        deal(address(USDC), operator, 100_000e18);
        vm.prank(operator);
        USDC.approve(address(pshop), type(uint256).max);

        // let's give some PIN for users that will buy/sell fractions
        deal(address(PIN), alice, 100_000e18);
        vm.prank(alice);
        PIN.approve(address(pshop), type(uint256).max);

        deal(address(PIN), bob, 100_000e18);
        vm.prank(bob);
        PIN.approve(address(pshop), type(uint256).max);

        // incrase the max per wallet ratio allowed, so that purchases don't revert for big sellers
        vm.prank(pinOwner);
        IPinToken(address(PIN)).setMaxWalletRatio(10);
    }

    function _listedBalance(address fractions_, uint256 tokenId, address account) internal view returns (uint256) {
        (, uint256 listedBalance,) = pshop.getBalances(fractions_, tokenId, account);
        return listedBalance;
    }

    function _stakedBalance(address fractions_, uint256 tokenId, address account) internal view returns (uint256) {
        (uint256 stakedBalance,,) = pshop.getBalances(fractions_, tokenId, account);
        return stakedBalance;
    }

    function _unlistedBalance(address fractions_, uint256 tokenId, address account) internal view returns (uint256) {
        (,, uint256 unlistedBalance) = pshop.getBalances(fractions_, tokenId, account);
        return unlistedBalance;
    }

    function _doPurchase(bytes32 listingId, uint256 amount, address buyer) internal {
        uint256 pinAmount = pshop.getQuoteInTokens(listingId, amount);
        if (pinAmount == type(uint256).max) revert("Invalid quote for some reason");

        vm.prank(buyer);
        pshop.purchase(listingId, amount, pinAmount);
    }

    function _listingAmount(bytes32 listingId) internal view returns (uint256) {
        Listing memory listing = pshop.getListing(listingId);
        return listing.amount;
    }

    function _getDrippingPeriod(address fractionalAssets, uint256 tokenId) internal view returns (uint256) {
        (,,, uint256 drippingPeriod) = pshop.getAssetInfo(fractionalAssets, tokenId);
        return drippingPeriod;
    }
}

contract UnlimitedSupplyFractions is ERC1155Supply {
    constructor() ERC1155("") {}

    // no limit to totalSupply
    function mint(uint256 tokenId, address to, uint256 assetSupply) external {
        _mint(to, tokenId, assetSupply, "");
    }
}
