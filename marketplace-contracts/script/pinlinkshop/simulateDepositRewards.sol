// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import "src/marketplaces/pinlinkShop.sol";
import "src/fractional/FractionalAssets.sol";

contract PinlinkShopSetupScript is Script {
    IERC20 USDCmock = IERC20(0x31548a5E3504BffD5CD9a350d1DFcc66c1ab7Ddb);
    IERC20 PIN = IERC20(0xb7c06D906C7CB7193Eb4D8ADC25983aEaf99729f);
    PinlinkShop pshop = PinlinkShop(0x46564999721055c7E5C32d857BCf766Aa4A4f626);
    FractionalAssets fractionalAssets = FractionalAssets(0x82C4b8FF3C9016C775eD160D8D40E2614c44b9BA);

    function run() public {
        vm.startBroadcast();
        USDCmock.approve(address(pshop), type(uint256).max);

        pshop.depositRewards(address(fractionalAssets), 3662385719, 1000e6, 7 days);
        pshop.depositRewards(address(fractionalAssets), 2011064538, 800e6, 7 days);
        pshop.depositRewards(address(fractionalAssets), 896145707, 700e6, 7 days);
        pshop.depositRewards(address(fractionalAssets), 459559817, 1500e6, 7 days);
        pshop.depositRewards(address(fractionalAssets), 2983557137, 1000e6, 7 days);
        // pshop.depositRewards(address(fractionalAssets), 4267555790, 1000e6, 7 days);
        // pshop.depositRewards(address(fractionalAssets), 2889119958, 1000e6, 7 days);
        // pshop.depositRewards(address(fractionalAssets), 2418779085, 1000e6, 7 days);
        // pshop.depositRewards(address(fractionalAssets), 182352940, 1000e6, 7 days);
        // pshop.depositRewards(address(fractionalAssets), 3252672878, 1000e6, 7 days);

        vm.stopBroadcast();
    }
}
