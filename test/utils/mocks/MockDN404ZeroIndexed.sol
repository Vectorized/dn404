// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../../src/DN404.sol";
import "./MockDN404.sol";

contract MockDN404ZeroIndexed is MockDN404 {
    function _useOneIndexed() internal pure override returns (bool) {
        return false;
    }
}
