// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {LibClone} from "../lib/solady/src/utils/LibClone.sol";
import {DN404Cloneable} from "../src/example/DN404Cloneable.sol";

contract DN404CloneableTest is SoladyTest {
    address immutable dnImpl = address(new DN404Cloneable());

    DN404Cloneable dn;
    address alice = address(111);

    function setUp() public {
        dn = DN404Cloneable(payable(LibClone.clone(dnImpl)));

        vm.prank(alice);
        dn.initialize(alice, "DN404", "DN", "", address(this), 1000, 2000);
    }

    function testMint() public {
        vm.prank(dn.owner());
        dn.mint(alice, 100);
        assertEq(dn.totalSupply(), 1100);

        vm.prank(dn.owner());
        vm.expectRevert();
        dn.mint(alice, 1000);
    }

    function testName() public {
        assertEq(dn.name(), "DN404");
    }

    function testSymbol() public {
        assertEq(dn.symbol(), "DN");
    }

    function testSetBaseURI() public {
        vm.prank(alice);
        dn.setBaseURI("https://example.com/");
        assertEq(dn.tokenURI(1), "https://example.com/1");
    }
}
