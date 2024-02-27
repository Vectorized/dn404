// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {DN420, MockDN420} from "./utils/mocks/MockDN420.sol";
// import {DN404Mirror} from "../src/DN404Mirror.sol";
// import {LibClone} from "solady/utils/LibClone.sol";
import {LibSort} from "solady/utils/LibSort.sol";

contract DN420Test is SoladyTest {
    uint256 internal constant _WAD = 10 ** 18;

    MockDN420 dn;

    function setUp() public {
        dn = new MockDN420();
    }

    function testFindOwnedIds() public {
        dn.initializeDN420(0, address(this));
        address alice = address(111);
        address bob = address(2);
        assertEq(dn.findOwnedIds(alice, 0, 0), new uint256[](0));
        assertEq(dn.findOwnedIds(alice, 0, 1), new uint256[](0));
        assertEq(dn.findOwnedIds(alice, 0, 10), new uint256[](0));

        dn.mint(alice, 1 * _WAD);
        dn.mint(bob, 1 * _WAD);
        dn.mint(alice, 1 * _WAD);
        dn.mint(bob, 1 * _WAD);

        assertEq(dn.findOwnedIds(alice, 0, 0), new uint256[](0));
        uint256[] memory expectedIds;
        expectedIds = new uint256[](2);
        expectedIds[0] = 1;
        expectedIds[1] = 3;
        assertEq(dn.findOwnedIds(alice, 0, 10), expectedIds);

        expectedIds = new uint256[](1);
        expectedIds[0] = 3;
        assertEq(dn.findOwnedIds(alice, 3, 4), expectedIds);
        assertEq(dn.findOwnedIds(alice, 3, 3), new uint256[](0));
        assertEq(dn.findOwnedIds(alice, 4, 4), new uint256[](0));

        assertEq(dn.exists(0), false);
        assertEq(dn.exists(1), true);
        assertEq(dn.exists(2), true);
        assertEq(dn.exists(3), true);
        assertEq(dn.exists(4), true);
        assertEq(dn.exists(5), false);
    }

    function testMixed(uint256) public {
        uint256 n = _bound(_random(), 0, 16);
        dn.initializeDN420(n * _WAD, address(1111));

        address[] memory addresses = new address[](3);
        addresses[0] = address(111);
        addresses[1] = address(222);
        addresses[2] = address(1111);

        do {
            if (_random() % 4 == 0) {
                dn.setUseDirectTransfersIfPossible(_random() % 2 == 0);
            }

            if (_random() % 16 > 0) {
                address from = addresses[_random() % 3];
                address to = addresses[_random() % 3];

                uint256 amount = _bound(_random(), 0, dn.balanceOf(from));
                vm.prank(from);
                dn.transfer(to, amount);
            }

            if (_random() % 4 == 0) {
                dn.setUseDirectTransfersIfPossible(_random() % 2 == 0);
            }

            if (_random() % 4 == 0) {
                address from = addresses[_random() % 3];
                address to = addresses[_random() % 3];

                uint256 amount = _bound(_random(), 0, dn.balanceOf(from));
                dn.burn(from, amount);
                dn.mint(to, amount);
            }

            if (_random() % 4 == 0) {
                vm.prank(addresses[_random() % 3]);
                dn.setSkipNFT(_random() & 1 == 0);
            }

            if (_random() % 4 == 0) {
                address from = addresses[_random() % 3];
                address to = addresses[_random() % 3];

                uint256[] memory fromIds = dn.findOwnedIds(from);
                if (fromIds.length != 0) {
                    uint256 id = fromIds[_random() % fromIds.length];
                    vm.prank(from);
                    dn.transferFromNFT(from, to, id);
                }
            }

            if (_random() % 8 == 0) {
                uint256 nftBalanceSum;
                unchecked {
                    uint256 balanceSum;
                    for (uint256 i; i != 3; ++i) {
                        address a = addresses[i];
                        uint256 balance = dn.balanceOf(a);
                        balanceSum += balance;
                        uint256 nftBalance = dn.ownedCount(a);
                        assertLe(nftBalance, balance / _WAD);
                        nftBalanceSum += nftBalance;
                    }
                    assertEq(balanceSum, dn.totalSupply());
                    assertLe(nftBalanceSum, balanceSum / _WAD);
                }    
            }
        } while (_random() % 8 > 0);

        if (_random() % 8 == 0) {
            uint256[] memory allTokenIds;
            for (uint256 i; i < 3; ++i) {
                address a = addresses[i];
                uint256[] memory tokens = dn.findOwnedIds(a);
                // Might not be sorted.
                LibSort.insertionSort(tokens);
                allTokenIds = LibSort.union(allTokenIds, tokens);
                assertLe(tokens.length, dn.balanceOf(a) / _WAD);
            }
            for (uint256 i; i < allTokenIds.length; ++i) {
                assertEq(dn.exists(allTokenIds[i]), true);
            }
            uint256 numExists;
            for (uint256 i; i <= n; ++i) {
                if (dn.exists(i)) ++numExists;
            }
            assertEq(allTokenIds.length, numExists);
            assertLe(allTokenIds.length, dn.totalSupply() / _WAD);
        }

        if (_random() % 4 == 0) {
            uint256 end = n + 1 + n;
            for (uint256 i = n + 1; i <= end; ++i) {
                assertEq(dn.exists(i), false);
            }
        }

        if (_random() % 4 == 0) {
            for (uint256 i; i != 3; ++i) {
                address a = addresses[i];
                vm.prank(a);
                dn.setSkipNFT(false);
                uint256 amount = dn.balanceOf(a);
                vm.prank(a);
                dn.transfer(a, amount);
                assertEq(dn.ownedCount(a), dn.balanceOf(a) / _WAD);
            }
        }

        if (_random() % 32 == 0) {
            for (uint256 i; i != 3; ++i) {
                address a = addresses[i];
                vm.prank(a);
                dn.setSkipNFT(true);
                uint256 amount = dn.balanceOf(a);
                vm.prank(a);
                dn.transfer(a, amount);
                assertEq(dn.ownedCount(a), 0);
            }
        }
    }

}
