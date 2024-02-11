// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/SoladyTest.sol";
import {SimpleDN404} from "../src/example/SimpleDN404.sol";

contract SimpleDN404Test is SoladyTest {
    SimpleDN404 dn;
    address alice = address(111);

    function setUp() public {
        dn = new SimpleDN404("DN404", "DN", 1000, address(this));
    }

    function testMint() public {
        dn.mint(alice, 100);
        assertEq(dn.totalSupply(), 1100);
    }

    function testSetBaseURI() public {
        dn.setBaseURI("https://example.com/");
        assertEq(dn.tokenURI(1), "https://example.com/1");
    }
}
