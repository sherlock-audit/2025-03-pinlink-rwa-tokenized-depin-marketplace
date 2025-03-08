// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC1155, ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {IERC7572} from "src/interfaces/IERC7572.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract FractionalAssets is ERC1155Supply, AccessControl, IERC7572 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string internal _baseURI;

    error FractionalAssets_InvalidTotalSupply();
    error FractionalAssets_TokenIdAlreadyExists();

    constructor(string memory _contractUri) ERC1155("") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        _baseURI = _contractUri;
    }

    /// @dev The msg.sender must be a valid minter.
    /// @dev A tokenId must not have any supply
    function mint(uint256 tokenId, address to, uint256 assetSupply) external onlyRole(MINTER_ROLE) {
        if (assetSupply == 0) revert FractionalAssets_InvalidTotalSupply();
        if (totalSupply(tokenId) != 0) revert FractionalAssets_TokenIdAlreadyExists();

        _mint(to, tokenId, assetSupply, "");
    }

    ///////////////////////////////////////////////////////

    function updateContractURI(string memory newContractUri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseURI = newContractUri;

        emit ContractURIUpdated();
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        // The _baseURI must be ended in "/"
        return string(abi.encodePacked(_baseURI, Strings.toString(tokenId)));
    }

    function contractURI() external view returns (string memory) {
        return _baseURI;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155)
        returns (bool)
    {
        return AccessControl.supportsInterface(interfaceId) || ERC1155.supportsInterface(interfaceId);
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override
    {
        ERC1155Supply._update(from, to, ids, values);
    }
}
