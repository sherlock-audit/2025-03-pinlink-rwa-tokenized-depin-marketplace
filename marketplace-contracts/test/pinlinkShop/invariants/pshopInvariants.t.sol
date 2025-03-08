// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {InvariantsHelperSingleAsset} from "./helper.sol";
import {FractionalAssets} from "src/fractional/FractionalAssets.sol";
import {PinlinkShop, Listing} from "src/marketplaces/pinlinkShop.sol";
import {Test} from "forge-std/Test.sol";
import {DummyOracle} from "src/oracles/DummyOracle.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract StakingShop_Invariant_Tests_SingleAsset is Test {
    FractionalAssets fractions;
    PinlinkShop pshop;
    DummyOracle oracle;

    ERC20Mock PIN;
    ERC20Mock USDC;

    InvariantsHelperSingleAsset helper;

    uint256 tokenId = 2222;

    // actors
    address admin = makeAddr("admin");
    address feeReceiver = makeAddr("feeReceiver");
    address operator = makeAddr("operator");

    function setUp() public {
        PIN = new ERC20Mock();
        USDC = new ERC20Mock();

        oracle = new DummyOracle(address(PIN), 0.95 ether);

        vm.startPrank(admin);
        fractions = new FractionalAssets("https://metadata.pinlink.dev/metadata/0xaaaa/");
        fractions.mint(uint256(tokenId), admin, 100);
        pshop = new PinlinkShop(address(PIN), address(oracle), address(USDC));
        pshop.setFeeReceiver(feeReceiver);
        fractions.setApprovalForAll(address(pshop), true);
        pshop.grantRole(pshop.OPERATOR_ROLE(), operator);
        vm.stopPrank();

        helper = new InvariantsHelperSingleAsset(fractions, pshop, address(PIN), address(USDC), tokenId);

        targetContract(address(helper));
    }

    // invariant: for each staker for each asset, _stakedBalance == _listedBalance + _unlistedBalance (inside pshop)
    function invariant_userBalances() public view {
        address actor = helper.currentActor();
        (uint256 stakedBalance, uint256 listedBalance, uint256 unlistedBalance) =
            pshop.getBalances(address(fractions), tokenId, actor);

        assertEq(stakedBalance, listedBalance + unlistedBalance, "inconsistent contract balances");
        assertEq(stakedBalance, helper._staked(actor), "inconsistent staked balance");
        assertEq(listedBalance, helper._listed(actor), "inconsistent listed balance");
        assertEq(unlistedBalance, helper._unlisted(actor), "inconsistent unlisted balance");
    }

    // invariant: ghost totalClaimed matches contract totalClaimed
    function invariant_totalClaimedRewards() public view {
        assertEq(helper.totalClaimedRewards(), _totalClaimedRewardsInWallets(), "total claimed rewards inconsistency");
    }

    // invariant: sum(getPendingRewards) + sum(claimedRewards) == totalDepositedRewards  (with completed dripping period)
    function invariant_totalDepositedAndPendingRewards_drippingComplete() public view {
        if (!_isDrippingComplete()) return;
        assertApproxEqAbs(
            _totalPendingRewards() + helper.totalClaimedRewards(),
            helper.totalDepositedRewards(),
            1000 // 0.0001 $ error allowed
        );
    }

    // invariant: sum(getPendingRewards) + sum(claimedRewards) == totalDepositedRewards
    function invariant_totalDepositedAndPendingRewards_duringDripping() public view {
        if (_isDrippingComplete()) return;

        // not all deposited have been released as pending rewards
        assertLe(_totalPendingRewards() + helper.totalClaimedRewards(), helper.totalDepositedRewards());
    }

    // invariant: total rewards pending < contract USDC balance
    function invariant_totalPendingRewardsSolvency() public view {
        assertLe(_totalPendingRewards(), USDC.balanceOf(address(pshop)));
    }

    // invariant: sum of staked assets in pshop is constant after asset is enabled
    function invariant_stakedAssets() public view {
        assertEq(_totalStaked(), fractions.totalSupply(tokenId), "total staked assets inconsistency");
    }

    // invariant: contract asset supply = asset supply - withdraws + deposits
    function invariant_assetSupplyInPinlinkShop() public view {
        uint256 assetsOutsideContract = helper.totalWithdrawnAssets() - helper.totalDepositedAssets();
        assertEq(
            fractions.balanceOf(address(pshop), tokenId) + assetsOutsideContract,
            fractions.totalSupply(tokenId),
            "asset supply inconsistency"
        );
    }

    // invariant: PIN paid = sellers PIN balance + feeReceiver PIN balance
    function invariant_pinPaidAccrossSystem() public view {
        uint256 nActors = helper.nActors();

        uint256 totalPinInSystem = 0;
        for (uint256 i = 0; i < nActors; i++) {
            address actor = helper.actorAt(i);
            totalPinInSystem += PIN.balanceOf(actor);
        }

        assertEq(totalPinInSystem, helper.pinCirculating(), "PIN balances inconsistency");
    }

    // invariant: none of the view functions ever reverts
    function invariant_viewFunctionsDontRevert() public view {
        pshop.getQuoteInTokens(0x0, 1);
        pshop.getListing(0x0);
        pshop.getBalances(address(fractions), tokenId, address(0x0));
        pshop.getPendingRewards(address(fractions), tokenId, address(0x0));
        pshop.getAssetInfo(address(fractions), tokenId);
        pshop.isAssetEnabled(address(fractions), tokenId);
        _totalPendingRewards();
    }

    /////////////////////////////////////////////////////////////////
    // utils
    /////////////////////////////////////////////////////////////////

    function _isDrippingComplete() internal view returns (bool) {
        (,, uint256 lastDepositTimestamp, uint256 drippingPeriod) = pshop.getAssetInfo(address(fractions), tokenId);
        return block.timestamp > lastDepositTimestamp + drippingPeriod;
    }

    function _totalClaimedRewardsInWallets() internal view returns (uint256 totalClaimedRewards) {
        for (uint256 i = 0; i < helper.nActors(); i++) {
            totalClaimedRewards += USDC.balanceOf(helper.actorAt(i));
        }
    }

    function _totalPendingRewards() internal view returns (uint256 totalPendingRewards) {
        uint256 nActors = helper.nActors();
        for (uint256 i = 0; i < nActors; i++) {
            totalPendingRewards += pshop.getPendingRewards(address(fractions), tokenId, helper.actorAt(i));
        }
        // weird rewards reserved from assets withdrawn from the system. Not an actor really
        totalPendingRewards += pshop.getPendingRewards(address(fractions), tokenId, pshop.REWARDS_PROXY_ACCOUNT());
    }

    function _totalStaked() internal view returns (uint256 totalStaked) {
        uint256 nActors = helper.nActors();
        for (uint256 i = 0; i < nActors; i++) {
            (uint256 stakedBalance,,) = pshop.getBalances(address(fractions), tokenId, helper.actorAt(i));
            totalStaked += stakedBalance;
        }
        (uint256 _unassignedStaked,,) = pshop.getBalances(address(fractions), tokenId, pshop.REWARDS_PROXY_ACCOUNT());
        totalStaked += _unassignedStaked;
    }
}
