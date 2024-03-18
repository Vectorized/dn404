// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN420.sol";
import "./MockBrutalizer.sol";

contract MockDN420 is DN420, MockBrutalizer {
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

    function mint(address to, uint256 amount, bytes memory data) public {
        _brutalizeMemory();
        _mint(_brutalized(to), amount, data);
    }

    function mint(address to, uint256 amount) public {
        _brutalizeMemory();
        _mint(_brutalized(to), amount, "");
    }

    function mintNext(address to, uint256 amount, bytes memory data) public {
        _brutalizeMemory();
        _mintNext(_brutalized(to), amount, data);
    }

    function mintNext(address to, uint256 amount) public {
        _brutalizeMemory();
        _mintNext(_brutalized(to), amount, "");
    }

    function burn(address from, uint256 amount) public {
        _brutalizeMemory();
        _burn(_brutalized(from), amount);
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

    function findOwnedIds(address owner, uint256 begin, uint256 end)
        public
        view
        returns (uint256[] memory)
    {
        return _findOwnedIds(owner, begin, end);
    }

    function findOwnedIds(address owner) public view returns (uint256[] memory) {
        return _findOwnedIds(owner, 0, type(uint256).max);
    }

    function ownedCount(address owner) public view returns (uint256) {
        return _getDN420Storage().addressData[owner].ownedCount;
    }

    function maxOwnedTokenId(address owner, uint256 upTo) public view returns (uint256 result) {
        result = _findLastSet(_getDN420Storage().owned[owner], upTo);
    }

    function exists(uint256 id) public view returns (bool) {
        return _exists(id);
    }

    function safeBatchTransferFromNFTs(
        address by,
        address from,
        address to,
        uint256[] memory ids,
        bytes memory data
    ) public {
        _safeBatchTransferNFTs(by, _brutalized(from), _brutalized(to), ids, data);
    }

    function safeBatchTransferFromNFTs(address by, address from, address to, uint256[] memory ids)
        public
    {
        _safeBatchTransferNFTs(by, _brutalized(from), _brutalized(to), ids, "");
    }

    function safeTransferFromNFT(
        address by,
        address from,
        address to,
        uint256 id,
        bytes memory data
    ) public {
        _safeTransferNFT(by, _brutalized(from), _brutalized(to), id, data);
    }

    function safeTransferFromNFT(address by, address from, address to, uint256 id) public {
        _safeTransferNFT(by, _brutalized(from), _brutalized(to), id, "");
    }

    function safeTransferFromNFT(address from, address to, uint256 id, bytes memory data) public {
        _brutalizeMemory();
        _safeTransferNFT(msg.sender, _brutalized(from), _brutalized(to), id, data);
    }

    function safeTransferFromNFT(address from, address to, uint256 id) public {
        _brutalizeMemory();
        _safeTransferNFT(msg.sender, _brutalized(from), _brutalized(to), id, "");
    }

    function safeBatchTransferFromNFTs(
        address from,
        address to,
        uint256[] memory ids,
        bytes memory data
    ) public {
        _safeBatchTransferNFTs(msg.sender, from, to, ids, data);
    }

    function safeBatchTransferFromNFTs(address from, address to, uint256[] memory ids) public {
        _safeBatchTransferNFTs(msg.sender, from, to, ids, "");
    }

    function _transfer(address from, address to, uint256 amount, bytes memory data)
        internal
        virtual
        override
    {
        _brutalizeMemory();
        DN420._transfer(_brutalized(from), _brutalized(to), amount, data);
        _checkMemory(data);
    }

    function _safeBatchTransferNFTs(
        address by,
        address from,
        address to,
        uint256[] memory ids,
        bytes memory data
    ) internal virtual override {
        _brutalizeMemory();
        DN420._safeBatchTransferNFTs(_brutalized(by), _brutalized(from), _brutalized(to), ids, data);
        _checkMemory(data);
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
