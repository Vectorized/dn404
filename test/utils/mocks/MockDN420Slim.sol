// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN420.sol";

contract MockDN420Slim is DN420 {
    function name() public view virtual override returns (string memory) {
        return "name";
    }

    function symbol() public view virtual override returns (string memory) {
        return "symbol";
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function initializeDN420(uint256 initialTokenSupply, address initialSupplyOwner) public {
        _initializeDN420(initialTokenSupply, initialSupplyOwner);
    }

    function _useDirectTransfersIfPossible() internal view virtual override returns (bool) {
        return true;
    }
}
