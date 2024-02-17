// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {NFTMintDN404} from "../src/example/NFTMintDN404.sol";
import {Merkle} from "murky/src/Merkle.sol";

contract NFTMintDN404Test is SoladyTest {
    uint256 internal constant _WAD = 10 ** 18;

    NFTMintDN404 dn;
    Merkle allowlistMerkle;

    address alice = address(111);
    address bob = address(222);

    bytes32 allowlistRoot;
    bytes32[] allowlistData = new bytes32[](2);

    uint96 publicPrice = 0.02 ether;
    uint96 allowlistPrice = 0.01 ether;

    function setUp() public {
        allowlistMerkle = new Merkle();
        allowlistData[0] = bytes32(keccak256(abi.encodePacked(alice)));
        allowlistRoot = allowlistMerkle.getRoot(allowlistData);

        dn = new NFTMintDN404(
            "DN404",
            "DN",
            allowlistRoot,
            publicPrice,
            allowlistPrice,
            uint96(1000 * _WAD),
            address(this)
        );
        dn.toggleLive();
        payable(bob).transfer(10 ether);
        payable(alice).transfer(10 ether);
    }

    function testMint() public {
        vm.startPrank(bob);

        vm.expectRevert(NFTMintDN404.InvalidPrice.selector);
        dn.mint{value: 1 ether}(1);

        dn.mint{value: 3 * publicPrice}(3);
        assertEq(dn.totalSupply(), 1003 * _WAD);
        assertEq(dn.balanceOf(bob), 3 * _WAD);

        dn.mint{value: 2 * publicPrice}(2);
        assertEq(dn.totalSupply(), 1005 * _WAD);
        assertEq(dn.balanceOf(bob), 5 * _WAD);

        vm.expectRevert(NFTMintDN404.InvalidMint.selector);
        dn.mint{value: publicPrice}(1);

        vm.stopPrank();
    }

    function testTotalSupplyReached() public {
        // Mint out whole supply
        for (uint160 i; i < 5000; ++i) {
            address a = address(i + 1000);
            payable(a).transfer(1 ether);
            vm.prank(a);
            dn.mint{value: publicPrice}(1);
        }

        vm.prank(alice);
        vm.expectRevert(NFTMintDN404.TotalSupplyReached.selector);
        dn.mint{value: publicPrice}(1);
    }

    function testAllowlistMint() public {
        vm.prank(bob);

        bytes32[] memory proof = allowlistMerkle.getProof(allowlistData, 0);
        vm.expectRevert(NFTMintDN404.InvalidProof.selector);
        dn.allowlistMint{value: 5 * allowlistPrice}(5, proof);

        vm.startPrank(alice);

        vm.expectRevert(NFTMintDN404.InvalidPrice.selector);
        dn.allowlistMint{value: 1 ether}(1, proof);

        dn.allowlistMint{value: 5 * allowlistPrice}(5, proof);
        assertEq(dn.totalSupply(), 1005 * _WAD);
        assertEq(dn.balanceOf(alice), 5 * _WAD);

        vm.expectRevert(NFTMintDN404.InvalidMint.selector);
        dn.allowlistMint{value: allowlistPrice}(1, proof);

        vm.stopPrank();
    }
}
