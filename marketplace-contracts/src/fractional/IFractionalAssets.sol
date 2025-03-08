// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {IERC1155} from "lib/forge-std/src/interfaces/IERC1155.sol";

interface IFractionalAssets is IERC1155 {
    function totalSupply(uint256 tokenId) external view returns (uint256);
}
