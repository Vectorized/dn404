// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {CustomWADDN404} from "../src/example/CustomWADDN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";

contract CustomWADDN404Test is SoladyTest {
    CustomWADDN404 dn;
    address alice = address(111);

    function setUp() public {
        vm.prank(alice);
        dn = new CustomWADDN404("DN404", "DN", 1000, address(this));
    }

    function testMint() public {
        DN404Mirror dnMirror = DN404Mirror(payable(dn.mirrorERC721()));
        vm.prank(dn.owner());
        dn.mint(alice, 100);
        assertEq(dn.totalSupply(), 1100);
        assertEq(dnMirror.balanceOf(alice), 0);
    }

    function testNFTMint() public {
        DN404Mirror dnMirror = DN404Mirror(payable(dn.mirrorERC721()));
        vm.prank(dn.owner());
        dn.mint(alice, 10 ** 25);
        assertEq(dn.totalSupply(), 10 ** 25 + 1000);
        assertEq(dn.balanceOf(alice), 10 ** 25);
        assertEq(dnMirror.balanceOf(alice), 1);
    }
}
