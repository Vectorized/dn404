// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {DN404} from "../../src/DN404.sol";
import {DN404Mirror} from "../../src/DN404Mirror.sol";
import {MockDN404} from "../utils/mocks/MockDN404.sol";
import {DN404Handler} from "./handlers/DN404Handler.sol";
import {DN404MirrorHandler} from "./handlers/DN404MirrorHandler.sol";

// forgefmt: disable-start
/**************************************************************************************************************************************/
/*** Invariant Tests                                                                                                                ***/
/***************************************************************************************************************************************

    * 

/**************************************************************************************************************************************/
/*** Vault Invariants                                                                                                               ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end
contract BaseInvariantTest is Test {
    address user0 = vm.addr(uint256(keccak256("OWNER")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));
    uint256 private constant _WAD = 1000000000000000000;

    MockDN404 dn404;
    DN404Mirror dn404Mirror;
    DN404Handler dn404Handler;
    DN404MirrorHandler dn404MirrorHandler;

    function setUp() public virtual {
        dn404 = new MockDN404();
        dn404Mirror = new DN404Mirror(address(this));
        dn404.initializeDN404(0, address(0), address(dn404Mirror));

        dn404Handler = new DN404Handler(dn404);

        vm.label(address(dn404), "dn404");
        vm.label(address(dn404Mirror), "dn404Mirror");
        vm.label(address(dn404Handler), "dn404Handler");
        // vm.label(address(dn404MirrorHandler), "dn404MirrorHandler");

        // target handlers
        targetContract(address(dn404Handler));
        targetContract(address(dn404MirrorHandler));
    }

    function invariantMirror721BalanceSum() external {
        assertLe(
            dn404Mirror.totalSupply() * _WAD,
            dn404.totalSupply(),
            "total supply * wad is greater than token total supply"
        );

        uint256 total = dn404Handler.balanceOf(user0) + dn404Handler.balanceOf(user1)
            + dn404Handler.balanceOf(user2) + dn404Handler.balanceOf(user3)
            + dn404Handler.balanceOf(user4) + dn404Handler.balanceOf(user5);
        assertEq(total, dn404Mirror.totalSupply(), "all users nfts exceed total supply");
    }

    function invariantDN404BalanceSum() public {
        assertEq(dn404.totalSupply(), dn404Handler.sum());

        uint256 total = dn404.balanceOf(user0) + dn404.balanceOf(user1) + dn404.balanceOf(user2)
            + dn404.balanceOf(user3) + dn404.balanceOf(user4) + dn404.balanceOf(user5);
        assertEq(dn404.totalSupply(), total);
    }
}
