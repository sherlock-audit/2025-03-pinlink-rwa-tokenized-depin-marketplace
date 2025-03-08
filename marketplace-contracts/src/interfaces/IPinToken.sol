//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.15;

import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";

interface IPinToken is IERC20 {
    function setExcludedFromFee(address account, bool isExcluded) external;
    function setMaxWalletRatio(uint32 maxWalletRatio) external;
}
