// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {SimpleDN404, DN404Mirror} from "../src/example/SimpleDN404.sol";

contract SimpleDN404Test is SoladyTest {
    SimpleDN404 dn;
    address alice = address(111);

    function setUp() public {
        vm.prank(alice);
        dn = new SimpleDN404("DN404", "DN", 1000, address(this));
    }

    function testMint() public {
        vm.prank(dn.owner());
        dn.mint(alice, 100);
        assertEq(dn.totalSupply(), 1100);
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
        assertEq(DN404Mirror(payable(dn.mirrorERC721())).tokenURI(1), "https://example.com/1");
    }

    function testWithdraw() public {
        vm.deal(address(dn), 1 ether);
        assertEq(address(dn).balance, 1 ether);
        vm.prank(alice);
        dn.withdraw();
        assertEq(address(dn).balance, 0);
        assertEq(alice.balance, 1 ether);
    }
}
