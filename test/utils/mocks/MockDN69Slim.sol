// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN69.sol";

contract MockDN69Slim is DN69 {
    function name() public view virtual override returns (string memory) {
        return "name";
    }

    function symbol() public view virtual override returns (string memory) {
        return "symbol";
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function initializeDN69(
        uint256 initialTokenSupply,
        address initialSupplyOwner
    ) public {
        _initializeDN69(initialTokenSupply, initialSupplyOwner);
    }

    function _useDirectTransfersIfPossible() internal view virtual override returns (bool) {
        return true;
    }
}
