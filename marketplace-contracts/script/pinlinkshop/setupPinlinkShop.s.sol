// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import "src/marketplaces/pinlinkShop.sol";
import "src/fractional/FractionalAssets.sol";

contract PinlinkShopSetupScript is Script {
    address DEV_WALLET = vm.envAddress("PINDEV_ADDRESS");
    address FRONT_WALLET = 0x8754Dd14aB904d970860C02f76164293da9727F0;

    ////////////////////////////// update ////////////////////////////////////////
    address feeReceiver = DEV_WALLET;
    address pinOracle = 0xc13827D7B2Cd3309952352D0C030e96bc7b9fcF5;
    FractionalAssets fractionalAssets = FractionalAssets(0x82C4b8FF3C9016C775eD160D8D40E2614c44b9BA);
    PinlinkShop pshop = PinlinkShop(0x46564999721055c7E5C32d857BCf766Aa4A4f626);
    ////////////////////////////// update ////////////////////////////////////////

    function run() public {
        vm.broadcast();
        fractionalAssets.setApprovalForAll(address(pshop), true);

        vm.broadcast();
        pshop.setOracle(pinOracle);

        // obviously, update these to be the actual admin accounts

        vm.startBroadcast();
        pshop.enableAsset(address(fractionalAssets), 3662385719, DEV_WALLET);
        pshop.enableAsset(address(fractionalAssets), 2011064538, DEV_WALLET);
        pshop.enableAsset(address(fractionalAssets), 896145707, DEV_WALLET);
        pshop.enableAsset(address(fractionalAssets), 459559817, DEV_WALLET);
        pshop.enableAsset(address(fractionalAssets), 2983557137, DEV_WALLET);
        pshop.enableAsset(address(fractionalAssets), 4267555790, DEV_WALLET);
        pshop.enableAsset(address(fractionalAssets), 2889119958, FRONT_WALLET);
        pshop.enableAsset(address(fractionalAssets), 2418779085, FRONT_WALLET);
        pshop.enableAsset(address(fractionalAssets), 182352940, FRONT_WALLET);
        pshop.enableAsset(address(fractionalAssets), 3252672878, FRONT_WALLET);
        vm.stopBroadcast();

        vm.broadcast();
        pshop.setFeeReceiver(DEV_WALLET);
    }
}
