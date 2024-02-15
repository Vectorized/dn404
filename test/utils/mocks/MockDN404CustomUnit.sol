// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./MockDN404.sol";

contract MockDN404CustomUnit is MockDN404 {
    uint256 public unit;

    function _unit() internal view virtual override returns (uint256) {
        return unit;
    }

    function setUnit(uint256 value) public {
        unit = value;
    }
}
