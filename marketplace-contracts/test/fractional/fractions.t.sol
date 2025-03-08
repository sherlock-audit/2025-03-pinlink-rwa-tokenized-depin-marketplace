// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import "src/fractional/FractionalAssets.sol";
import {Test} from "forge-std/Test.sol";

contract FractionalAssetsTest is Test {
    FractionalAssets fractionalAssets;

    address admin = makeAddr("admin");
    address minter = makeAddr("minter");
    address user = makeAddr("user");

    string constant baseURI = "https://metadata.pinlink.dev/metadata/0xaaa/";

    function setUp() public {
        vm.startPrank(admin);
        fractionalAssets = new FractionalAssets(baseURI);
        fractionalAssets.grantRole(fractionalAssets.MINTER_ROLE(), minter);
        vm.stopPrank();
    }

    // access control on mint (only minters)
    function testUnauthorizedMinting() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        fractionalAssets.mint(1, user, 10);

        // but an authorized minter is allowed
        vm.prank(minter);
        fractionalAssets.mint(1, user, 10);
    }

    // access controll on only admin functions
    function testUnauthorizedFunctions() public {
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert();
        fractionalAssets.updateContractURI("https://example.com/api/token/newToken.json");
    }

    // mint to user
    function testMintingFunctionality() public {
        vm.prank(minter);
        fractionalAssets.mint(1, user, 10);
        assertEq(fractionalAssets.balanceOf(user, 1), 10);
        assertEq(fractionalAssets.uri(1), "https://metadata.pinlink.dev/metadata/0xaaa/1");
    }

    // mint to minter
    function testMintToMinter() public {
        vm.prank(minter);
        fractionalAssets.mint(1, minter, 10);
        assertEq(fractionalAssets.balanceOf(minter, 1), 10);
    }

    // mint with invalid totalSupply
    function testInvalidTotalSupply() public {
        vm.prank(minter);
        vm.expectRevert(FractionalAssets.FractionalAssets_InvalidTotalSupply.selector);
        fractionalAssets.mint(1, user, 0);
    }

    // mint existing token reverts
    function testTokenIdAlreadyExists() public {
        vm.startPrank(minter);

        fractionalAssets.mint(1, user, 10);

        vm.expectRevert(FractionalAssets.FractionalAssets_TokenIdAlreadyExists.selector);
        fractionalAssets.mint(1, user, 10);
    }

    // mint non-sequential tokenIds
    function testNonSequentialTokenIds() public {
        vm.startPrank(minter);
        fractionalAssets.mint(1, user, 100);
        fractionalAssets.mint(1234523452, user, 100);
        fractionalAssets.mint(5, user, 100);

        assertEq(fractionalAssets.balanceOf(user, 1), 100);
        assertEq(fractionalAssets.balanceOf(user, 1234523452), 100);
        assertEq(fractionalAssets.balanceOf(user, 5), 100);
    }

    // read tokenURI
    function testReadTokenURI() public {
        vm.prank(minter);
        fractionalAssets.mint(123411, user, 10);
        assertEq(fractionalAssets.uri(123411), "https://metadata.pinlink.dev/metadata/0xaaa/123411");
    }

    // transfer fractions
    function testTransferFractions() public {
        vm.prank(minter);
        fractionalAssets.mint(1, user, 10);

        vm.prank(user);
        fractionalAssets.safeTransferFrom(user, admin, 1, 5, "");

        assertEq(fractionalAssets.balanceOf(user, 1), 5);
        assertEq(fractionalAssets.balanceOf(admin, 1), 5);
    }

    function testContratURI() public {
        vm.prank(admin);
        fractionalAssets.updateContractURI("https://example.com/api/token/piiinnliiiiinkkkk");

        assertEq(fractionalAssets.contractURI(), "https://example.com/api/token/piiinnliiiiinkkkk");
    }
}
