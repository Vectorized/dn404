// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import "../src/DailyOutflowCounterLib.sol";

contract DailyOutflowCounterTest is SoladyTest {
    using DailyOutflowCounterLib for *;

    uint256 internal constant _WAD = 10 ** 18;

    function testDailyOutflowCounter() public {
        uint88 packed;
        uint256 multiple;
        (packed, multiple) = packed.update(2 * _WAD);
        assertEq(multiple, 2);
        (packed, multiple) = packed.update(1 * _WAD);
        assertEq(multiple, 3);

        vm.warp(block.timestamp + 86400 * 2);

        (packed, multiple) = packed.update(2 * _WAD);
        assertEq(multiple, 2);
        (packed, multiple) = packed.update(1 * _WAD);
        assertEq(multiple, 3);
    }

    function testWhitelistIsSustained(uint88 packed) public {
        packed = packed & (2 ** 87 - 1);
        assertEq(packed.isWhitelisted(), false);
        packed = packed.setWhitelisted(true);
        assertEq(packed.isWhitelisted(), true);
        packed = packed.setWhitelisted(false);
        assertEq(packed.isWhitelisted(), false);
    }
}
