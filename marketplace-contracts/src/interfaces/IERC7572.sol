// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

interface IERC7572 {
    function contractURI() external view returns (string memory);

    event ContractURIUpdated();
}

// https://eips.ethereum.org/EIPS/eip-7572
