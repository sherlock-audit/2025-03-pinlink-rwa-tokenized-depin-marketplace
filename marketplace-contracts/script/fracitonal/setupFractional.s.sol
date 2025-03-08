// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import "src/fractional/FractionalAssets.sol";

contract FractionalTokenScript is Script {
    address DEV_WALLET = vm.envAddress("PINDEV_ADDRESS");

    FractionalAssets public fractionalAssets = FractionalAssets(0x82C4b8FF3C9016C775eD160D8D40E2614c44b9BA);
    string constant baseUri = "https://metadata.pinlink.dev/metadata/0x82C4b8FF3C9016C775eD160D8D40E2614c44b9BA/";

    function run() public {
        vm.broadcast();
        // update contract uri
        fractionalAssets.updateContractURI(baseUri);

        // These are only the miners
        // assets are minted to the dev wallet, which will deposit in the pshop to the admin account
        vm.startBroadcast();
        fractionalAssets.mint(3662385719, DEV_WALLET, 100);
        fractionalAssets.mint(2011064538, DEV_WALLET, 100);
        fractionalAssets.mint(896145707, DEV_WALLET, 100);
        fractionalAssets.mint(459559817, DEV_WALLET, 100);
        fractionalAssets.mint(2983557137, DEV_WALLET, 100);
        fractionalAssets.mint(4267555790, DEV_WALLET, 100);
        fractionalAssets.mint(2889119958, DEV_WALLET, 100);
        fractionalAssets.mint(2418779085, DEV_WALLET, 100);
        fractionalAssets.mint(182352940, DEV_WALLET, 100);
        fractionalAssets.mint(3252672878, DEV_WALLET, 100);
        vm.stopBroadcast();
    }
}
