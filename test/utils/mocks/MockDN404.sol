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
        _setSkipNFT(target, status);
    }

    function registerAndResolveAlias(address target) public returns (uint32) {
        return _registerAndResolveAlias(_addressData(target), target);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    function initializeDN404(
        uint256 initialTokenSupply,
        address initialSupplyOwner,
        address mirrorNFTContract
    ) public {
        _initializeDN404(initialTokenSupply, initialSupplyOwner, mirrorNFTContract);
    }

    function ownerAt(uint256 id) public view returns (address) {
        return _ownerAt(id);
    }

    function getAddressDataInitialized(address target) public view returns (bool) {
        return _getDN404Storage().addressData[target].flags & _ADDRESS_DATA_INITIALIZED_FLAG != 0;
    }

    function setAux(address target, uint88 value) public {
        _setAux(target, value);
    }

    function getAux(address target) public view returns (uint88) {
        return _getAux(target);
    }
}
