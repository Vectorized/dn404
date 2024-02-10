// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN404.sol";

contract MockDN404 is DN404 {
    string private _name;

    string private _symbol;

    string private _baseURI;

    function setNameAndSymbol(string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function setBaseURI(string memory baseURI_) public {
        _baseURI = baseURI_;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        return string(abi.encodePacked(_baseURI, id));
    }

    function setWhitelist(address target, bool status) public {
        _setSkipNFTWhitelist(target, status);
    }

    function registerAndResolveAlias(address target) public returns (uint32) {
        return _registerAndResolveAlias(target);
    }

    function initializeDN404(
        uint32 totalNFTSupply,
        address initialSupplyOwner,
        address mirrorNFTContract
    ) public {
        _initializeDN404(totalNFTSupply, initialSupplyOwner, mirrorNFTContract);
    }
}
