// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {MockDN404A} from "./utils/mocks/MockDN404A.sol";

/// @author philogy <https://github.com/philogy>
contract DN404ATest is Test {
    MockDN404A nft = new MockDN404A();

    error TokenDoesNotExist();

    function test_mint5() public {
        address user = makeAddr("user");
        nft.mintTokens(user, 5);

        for (uint256 id = 1; id <= 5; id++) {
            assertEq(nft.ownerOf(id), user);
        }

        vm.expectRevert(TokenDoesNotExist.selector);
        nft.ownerOf(0);

        vm.expectRevert(TokenDoesNotExist.selector);
        nft.ownerOf(6);
    }

    function test_mintToTwoUsers() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        nft.mintTokens(user1, 5);
        nft.mintTokens(user2, 3);
        nft.mintTokens(user1, 2);

        for (uint256 id = 1; id <= 5; id++) {
            assertEq(nft.ownerOf(id), user1);
        }

        for (uint256 id = 6; id <= 8; id++) {
            assertEq(nft.ownerOf(id), user2);
        }

        for (uint256 id = 9; id <= 10; id++) {
            assertEq(nft.ownerOf(id), user1);
        }
    }

    function test_transferSingleLot() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        nft.mintTokens(user1, 5);

        nft.transferTokens(user1, user2, 3);

        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user1);
        assertEq(nft.ownerOf(3), user2);
        assertEq(nft.ownerOf(4), user2);
        assertEq(nft.ownerOf(5), user2);
    }

    function test_transferEntireLot() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        nft.mintTokens(user1, 5);

        nft.transferTokens(user1, user2, 5);

        assertEq(nft.ownerOf(1), user2);
        assertEq(nft.ownerOf(2), user2);
        assertEq(nft.ownerOf(3), user2);
        assertEq(nft.ownerOf(4), user2);
        assertEq(nft.ownerOf(5), user2);
    }

    function test_transferMultipleLots() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        nft.mintTokens(user1, 5);
        nft.mintTokens(user2, 2);
        nft.mintTokens(user1, 2);

        nft.transferTokens(user1, user3, 4);

        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(2), user1);
        assertEq(nft.ownerOf(3), user1);
        assertEq(nft.ownerOf(4), user3);
        assertEq(nft.ownerOf(5), user3);
        assertEq(nft.ownerOf(6), user2);
        assertEq(nft.ownerOf(7), user2);
        assertEq(nft.ownerOf(8), user3);
        assertEq(nft.ownerOf(9), user3);
    }
}
