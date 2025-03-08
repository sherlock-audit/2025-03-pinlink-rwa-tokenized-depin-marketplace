// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {BaseStakingShopTests} from "test/pinlinkShop/base.t.sol";
import {IERC1155Receiver} from "lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

contract StakingShop_AfterDeployment_Tests is BaseStakingShopTests {
    // Ensure that the feeReceiver is not the zero address
    function testFeeReceiverIsNotZero() public view {
        assertTrue(pshop.feeReceiver() != address(0), "Fee receiver should not be zero address");
    }

    // Check if the admin has the DEFAULT_ADMIN_ROLE
    function testAdminHasDefaultAdminRole() public view {
        assertTrue(pshop.hasRole(pshop.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
    }

    // Check if the admin has the OPERATOR_ROLE
    function testAdminHasOperatorRole() public view {
        assertTrue(pshop.hasRole(pshop.OPERATOR_ROLE(), admin), "Admin should have OPERATOR_ROLE");
    }

    // Ensure that the rewardsToken is USDC
    function testRewardsTokenIsUSDC() public view {
        assertTrue(pshop.REWARDS_TOKEN() == address(USDC), "Rewards token should be USDC");
    }

    // check  that suports interface returns true for ERC1155 holder
    function testSupportsInterfaceIERC1155Receiver() public view {
        assertTrue(pshop.supportsInterface(type(IERC1155Receiver).interfaceId), "Should support IERC1155Receiver");
    }

    // check  that suports interface returns true for AccessControl
    function testSupportsInterfaceAccessControl() public view {
        assertTrue(pshop.supportsInterface(type(IAccessControl).interfaceId), "Should support AccessControl");
    }
}
