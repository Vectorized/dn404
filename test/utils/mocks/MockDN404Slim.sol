// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN404.sol";

contract MockDN404Slim is DN404 {
    function name() public view virtual override returns (string memory) {
        return "name";
    }

    function symbol() public view virtual override returns (string memory) {
        return "symbol";
    }

    function tokenURI(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function initializeDN404(
        uint256 initialTokenSupply,
        address initialSupplyOwner,
        address mirrorNFTContract
    ) public {
        _initializeDN404(initialTokenSupply, initialSupplyOwner, mirrorNFTContract);
    }

    function _addToBurnedPool(uint256, uint256) internal view virtual override returns (bool) {
        return false;
    }

    function _useDirectTransfersIfPossible() internal view virtual override returns (bool) {
        return true;
    }

    function _useExistsLookup() internal view virtual override returns (bool) {
        return false;
    }
}
