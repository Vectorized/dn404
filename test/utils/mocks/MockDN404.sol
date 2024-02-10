// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN404.sol";


contract MockDN404 is DN404 {
    function name() public view virtual override returns (string memory) {
        return "DN404";
    }

    function symbol() public view virtual override returns (string memory) {
        return "DN";
    }

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function setWhitelist(address target, bool status) public {
        _setSkipNFTWhitelist(target, status);
    }

    function registerAndResolveAlias(address target) public returns (uint32) {
        return _registerAndResolveAlias(target);
    }

    function initializeDN404(uint32 totalNFTSupply, address initialSupplyOwner, address sisterNFTContract) public {
         _initializeDN404(totalNFTSupply, initialSupplyOwner, sisterNFTContract);
    }
}