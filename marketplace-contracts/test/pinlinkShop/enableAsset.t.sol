// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {PinlinkShop} from "src/marketplaces/pinlinkShop.sol";
import {UnlimitedSupplyFractions} from "test/pinlinkShop/base.t.sol";
import "src/marketplaces/streams.sol";

contract StakingShop_EnablingAssets_Tests is BaseStakingShopTests {
    // check pshop.enableAsset() increases fractions balance of pshop and decreases from caller (admin)
    function testEnableAsset() public {
        uint256 balanceBefore = fractions.balanceOf(address(pshop), asset1);
        uint256 balanceAdminBefore = fractions.balanceOf(admin, asset1);

        vm.prank(admin);
        pshop.enableAsset(address(fractions), asset1, admin);

        assertTrue(fractions.balanceOf(address(pshop), asset1) > balanceBefore, "Balance of pshop should increase");
        assertTrue(fractions.balanceOf(admin, asset1) < balanceAdminBefore, "Balance of admin should decrease");
    }

    // check that pshop.isAssetEnabled() returns true after enabling an asset
    function testIsAssetEnabled() public {
        vm.startPrank(admin);
        assertFalse(pshop.isAssetEnabled(address(fractions), asset1));
        pshop.enableAsset(address(fractions), asset1, admin);
        assertTrue(pshop.isAssetEnabled(address(fractions), asset1));
    }

    // check pshop.enableAsset() already enabled asset reverts with AlreadyEnabled
    function testEnableAssetAlreadyEnabled() public {
        vm.startPrank(admin);

        UnlimitedSupplyFractions unlimitedFractions = new UnlimitedSupplyFractions();
        unlimitedFractions.mint(asset1, admin, 100);
        unlimitedFractions.setApprovalForAll(address(pshop), true);

        pshop.enableAsset(address(unlimitedFractions), asset1, admin);

        unlimitedFractions.mint(asset1, admin, 100);

        vm.expectRevert(PinlinkShop.AlreadyEnabled.selector);
        pshop.enableAsset(address(unlimitedFractions), asset1, admin);
    }

    // check pshop.enableAsset() with an ERC1155 asset totalSupply=0 reverts
    function testEnableAssetInvalidZeroTotalSupply() public {
        assertEq(fractions.totalSupply(222222222222), 0);
        assertEq(fractions.totalSupply(asset1), 100);

        vm.startPrank(admin);
        vm.expectRevert(PinlinkRewards_AssetSupplyIsZero.selector);
        pshop.enableAsset(address(fractions), 222222222222, admin);

        // but a non-zero supply asset is fine
        pshop.enableAsset(address(fractions), asset1, admin);
    }

    // check pshop.enableAsset() with an ERC1155 asset totalSupply=0 reverts
    function testEnableAssetInvalidTooHighTotalSupply() public {
        (, uint256 maxTotalSupplyAllowed,,) = pshop.getRewardsConstants();
        uint256 assetId = 444111444;
        vm.prank(admin);
        fractions.mint(assetId, admin, maxTotalSupplyAllowed + 1);

        assertGt(fractions.totalSupply(assetId), maxTotalSupplyAllowed);

        vm.prank(admin);
        vm.expectRevert(PinlinkRewards_AssetSupplyTooHigh.selector);
        pshop.enableAsset(address(fractions), assetId, admin);
    }

    // check pshop.enableAsset() reverts if not authorized
    function testEnableAssetNotAuthorized() public {
        vm.startPrank(makeAddr("unauthorized"));
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        pshop.enableAsset(address(fractions), asset1, alice);
    }

    // check the staked amount of receiver increased by the asset supply
    function testEnableAssetStakedAmount() public {
        uint256 stakedBalance = _stakedBalance(address(fractions), asset1, feeReceiver);

        uint256 assetSupply = fractions.totalSupply(asset1);
        vm.prank(admin);
        pshop.enableAsset(address(fractions), asset1, feeReceiver);

        uint256 stakedBalanceAfter = _stakedBalance(address(fractions), asset1, feeReceiver);
        assertEq(stakedBalanceAfter, stakedBalance + assetSupply);
    }

    // check the asset supply is set when enabling the asset
    function testEnableAssetSupply() public {
        vm.prank(admin);
        pshop.enableAsset(address(fractions), asset1, admin);

        (uint256 assetSupply,,,) = pshop.getAssetInfo(address(fractions), asset1);
        assertEq(fractions.totalSupply(asset1), assetSupply);
    }
}
