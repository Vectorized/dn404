// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "../utils/forge-std/Test.sol";
import {StdInvariant} from "../utils/forge-std/StdInvariant.sol";
import {DN404} from "../../src/DN404.sol";
import {DN404Mirror} from "../../src/DN404Mirror.sol";
import {MockDN404CustomUnit} from "../utils/mocks/MockDN404CustomUnit.sol";
import {DN404Handler} from "./handlers/DN404Handler.sol";
import {StaticUnitInvariant} from "./StaticUnitInvariant.t.sol";

/// @dev Invariant tests with a unit that is not a multiple of token decimals.
contract NonMultipleUnitInvariant is StaticUnitInvariant {
    function setUp() public virtual override {
        StaticUnitInvariant.setUp();
    }

    function _unit() internal pure override returns (uint256) {
        return 1e18 + 999999999999999999;
    }
}
