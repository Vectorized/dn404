// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN404Mirror.sol";

contract MockDN404Mirror is DN404Mirror {
    constructor(address deployer) DN404Mirror(deployer) {}

    function name() public view virtual override brutalizeMemory returns (string memory result) {
        result = DN404Mirror.name();
    }

    function symbol() public view virtual override brutalizeMemory returns (string memory result) {
        result = DN404Mirror.symbol();
    }

    function tokenURI(uint256 id)
        public
        view
        virtual
        override
        brutalizeMemory
        returns (string memory result)
    {
        result = DN404Mirror.tokenURI(id);
    }

    function totalSupply() public view virtual override brutalizeMemory returns (uint256 result) {
        result = DN404Mirror.totalSupply();
    }

    function balanceOf(address owner)
        public
        view
        virtual
        override
        brutalizeMemory
        returns (uint256 result)
    {
        result = DN404Mirror.balanceOf(_brutalized(owner));
    }

    function ownerOf(uint256 id)
        public
        view
        virtual
        override
        brutalizeMemory
        returns (address result)
    {
        result = DN404Mirror.ownerOf(id);
    }

    function approve(address spender, uint256 id) public virtual override brutalizeMemory {
        DN404Mirror.approve(_brutalized(spender), id);
    }

    function getApproved(uint256 id)
        public
        view
        virtual
        override
        brutalizeMemory
        returns (address result)
    {
        result = DN404Mirror.getApproved(id);
    }

    function setApprovalForAll(address operator, bool approved)
        public
        virtual
        override
        brutalizeMemory
    {
        DN404Mirror.setApprovalForAll(_brutalized(operator), approved);
    }

    function isApprovedForAll(address owner, address operator)
        public
        view
        virtual
        override
        brutalizeMemory
        returns (bool result)
    {
        result = DN404Mirror.isApprovedForAll(owner, operator);
    }

    function transferFrom(address from, address to, uint256 id)
        public
        virtual
        override
        brutalizeMemory
    {
        DN404Mirror.transferFrom(_brutalized(from), _brutalized(to), id);
    }

    function _brutalized(address a) internal pure returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(0xf348aeebbad597df99cf9f4f0000000000000000000000000000000000000000, a)
        }
    }

    modifier brutalizeMemory() {
        uint256 r = gasleft();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, r)
            r := keccak256(0x00, 0x20)
            mstore(0x00, r)
            mstore(0x20, r)
            let m := mload(0x40)
            mstore(add(m, 0x00), r)
            mstore(add(m, 0x20), r)
            mstore(add(m, 0x40), r)
            mstore(add(m, 0x60), r)
            mstore(add(m, 0x80), r)
            mstore(add(m, 0xa0), r)
        }
        _;
    }
}
