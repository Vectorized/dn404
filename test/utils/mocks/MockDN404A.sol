// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {DN404A} from "../../../src/DN404A.sol";

/// @author philogy <https://github.com/philogy>
contract MockDN404A is DN404A {
    constructor() {
        _initializeDN404();
    }

    function nftSupply() public view returns (uint256) {
        return numMinted() - numBurned();
    }

    function numBurned() public view returns (uint256) {
        DN404Storage storage $ = _getDN404Storage();
        return $.numMinted;
    }

    function numMinted() public view returns (uint256) {
        DN404Storage storage $ = _getDN404Storage();
        return $.numMinted;
    }

    function transferTokens(address from, address to, uint32 amount) public {
        _transferTokens(from, to, amount);
    }

    function mintTokens(address to, uint256 amount) public {
        _mintTokens(to, amount);
    }
}
