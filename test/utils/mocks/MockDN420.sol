// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN420.sol";

contract MockDN420 is DN420 {
    string private _name;

    string private _symbol;

    bool useDirectTransfersIfPossible;

    bool givePermit2DefaultInfiniteAllowance;

    function initializeDN420(uint256 initialTokenSupply, address initialSupplyOwner) public {
        _initializeDN420(initialTokenSupply, initialSupplyOwner);
    }

    function setNameAndSymbol(string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function mintNext(address to, uint256 amount) public {
        _mintNext(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
    
    function getAddressDataInitialized(address target) public view returns (bool) {
        return _getDN420Storage().addressData[target].flags & _ADDRESS_DATA_INITIALIZED_FLAG != 0;
    }

    function setAux(address target, uint88 value) public {
        _setAux(target, value);
    }

    function getAux(address target) public view returns (uint88) {
        return _getAux(target);
    }

    function getNextTokenId() public view returns (uint32) {
        return _getDN420Storage().nextTokenId;
    }

    function findOwnedIds(address owner, uint256 begin, uint256 end) public view returns (uint256[] memory) {
        return _findOwnedIds(owner, begin, end);
    }

    function findOwnedIds(address owner) public view returns (uint256[] memory) {
        return _findOwnedIds(owner, 0, type(uint256).max);
    }

    function ownedCount(address owner) public view returns (uint256) {
        return _getDN420Storage().addressData[owner].ownedCount;
    }

    function exists(uint256 id) public view returns (bool) {
        return _exists(id);
    }

    function transferFromNFT(address from, address to, uint256 id) public {
        _transferFromNFT(from, to, id);
    }

    function setGivePermit2DefaultInfiniteAllowance(bool value) public {
        givePermit2DefaultInfiniteAllowance = value;
    }

    function _givePermit2DefaultInfiniteAllowance() internal view virtual override returns (bool) {
        return givePermit2DefaultInfiniteAllowance;
    }

    function setUseDirectTransfersIfPossible(bool value) public {
        useDirectTransfersIfPossible = value;
    }

    function _useDirectTransfersIfPossible() internal view virtual override returns (bool) {
        return useDirectTransfersIfPossible;
    }

    function _afterNFTTransfer(address from, address to, uint256 id) internal virtual override {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, from)
            mstore(0x20, to)
            mstore(0x10, id)
        }
    }
}
