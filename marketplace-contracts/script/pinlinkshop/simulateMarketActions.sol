// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import "src/marketplaces/pinlinkShop.sol";
import "src/fractional/FractionalAssets.sol";

contract PinlinkShopSetupScript is Script {
    uint256 DEV_PKEY = vm.envUint("PINDEV_PKEY");
    uint256 USER_PKEY = vm.envUint("PINUSER_PKEY");
    address PINDEV_ADDRESS = vm.envAddress("PINDEV_ADDRESS");
    address USER_ADDRESS = vm.envAddress("PINUSER_ADDRESS");

    ////////////////////////////// update ////////////////////////////////////////
    IERC20 PIN = IERC20(0xb7c06D906C7CB7193Eb4D8ADC25983aEaf99729f);
    PinlinkShop pshop = PinlinkShop(0x46564999721055c7E5C32d857BCf766Aa4A4f626);
    FractionalAssets fractionalAssets = FractionalAssets(0x82C4b8FF3C9016C775eD160D8D40E2614c44b9BA);
    //////////////////////////////////////////////////////////////////////////////

    function run() public {
        // _list();
        _marketActions();
    }

    function _list() internal {
        vm.startBroadcast(DEV_PKEY);
        pshop.list(address(fractionalAssets), 3662385719, 20, 1500e18, block.timestamp + 365 days);
        pshop.list(address(fractionalAssets), 3662385719, 10, 2200e18, block.timestamp + 365 days);
        pshop.list(address(fractionalAssets), 896145707, 15, 200e18, block.timestamp + 365 days);

        pshop.list(address(fractionalAssets), 459559817, 10, 1000e18, block.timestamp + 365 days);

        // put a listing with a short deadline to filter it out in the frontend
        pshop.list(address(fractionalAssets), 2983557137, 10, 1000e18, block.timestamp + 1 minutes);
        vm.stopBroadcast();
    }

    function _marketActions() public {
        vm.broadcast(USER_PKEY);
        PIN.approve(address(pshop), type(uint256).max);
        vm.broadcast(DEV_PKEY);
        PIN.approve(address(pshop), type(uint256).max);

        bytes32 listingId1 = 0x017a99ee85ca598443e3e7078ed54f8832290ee6f14582e528082ec1c817884c;
        bytes32 listingId2 = 0x04656f134ceeb70e91d1182ff9f49e943be9194122cbfce5ebfcb4d0802cb40e;
        bytes32 listingId3 = 0x43e7b23b21e0803ac7bd9ba5242b0c7cbf4dd65fabb18a4c39fc43aa06613f72;
        // bytes32 listingId4 = 0x468cc812c058da092753fbdacecf8553c33eda5ca7171df3241b11c7d3337606;
        // bytes32 listingId5 = 0x1acf5be37c7080dfd1a822b4e2998a5b066733380af06ad962d867230984945b;

        vm.startBroadcast(DEV_PKEY);
        pshop.modifyListing(listingId1, 15e18, 0);
        pshop.modifyListing(listingId1, 0, block.timestamp + 70 days);
        pshop.modifyListing(listingId2, 10e18, block.timestamp + 170 days);
        vm.stopBroadcast();

        vm.startBroadcast(USER_PKEY);
        pshop.purchase(listingId1, 5, type(uint256).max);
        uint256 pinQuote = pshop.getQuoteInTokens(listingId1, 3);
        pshop.purchase(listingId1, 3, pinQuote);
        vm.stopBroadcast();

        vm.startBroadcast(DEV_PKEY);
        pshop.delist(listingId2, 2);
        pshop.modifyListing(listingId2, 5e18, 0);
        vm.stopBroadcast();

        pinQuote = pshop.getQuoteInTokens(listingId2, 3);
        vm.broadcast(USER_PKEY);
        pshop.purchase(listingId2, 3, pinQuote);

        vm.broadcast(DEV_PKEY);
        pshop.delist(listingId3, 2);

        vm.broadcast(USER_PKEY);
        pshop.list(address(fractionalAssets), 3662385719, 2, 111e18, block.timestamp + 65 days);
    }
}
