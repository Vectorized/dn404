// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";

contract DN404MirrorTest is SoladyTest {
    MockDN404 dn;
    DN404Mirror mirror;

    function setUp() public {
        dn = new MockDN404();
        mirror = new DN404Mirror();
    }

    function testNotLinked() public {
        vm.expectRevert(DN404Mirror.NotLinked.selector);
        mirror.name();
    }

    function testNameAndSymbol() public {
        dn.setNameAndSymbol("Test", "T");
        assertEq(mirror.name(), "ff");
    }
}
