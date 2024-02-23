// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {DN404} from "../../src/DN404.sol";
import {DN404Mirror} from "../../src/DN404Mirror.sol";
import {MockDN404} from "../utils/mocks/MockDN404.sol";
import {DN404Handler} from "./handlers/DN404Handler.sol";

// forgefmt: disable-start
/**************************************************************************************************************************************/
/*** Invariant Tests                                                                                                                ***/
/***************************************************************************************************************************************

    * NFT total supply * WAD must always be less than or equal to the ERC20 total supply
    * NFT balance of a user * WAD must be less than or equal to the ERC20 balance of that user
    * NFT balance of all users summed up must be equal to the NFT total supply
    * ERC20 balance of all users summed up must be equal to the ERC20 total supply
    * Mirror contract known to the base and the base contract known to the mirror never change after initialization

/**************************************************************************************************************************************/
/*** Vault Invariants                                                                                                               ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end
contract BaseInvariantTest is Test {
    address user0 = vm.addr(uint256(keccak256("User0")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));
    uint256 private constant _WAD = 1000000000000000000;

    MockDN404 dn404;
    DN404Mirror dn404Mirror;
    DN404Handler dn404Handler;

    function setUp() external virtual {
        dn404 = new MockDN404();
        dn404Mirror = new DN404Mirror(address(this));
        dn404.initializeDN404(0, address(0), address(dn404Mirror));

        dn404Handler = new DN404Handler(dn404);

        vm.label(address(dn404), "dn404");
        vm.label(address(dn404Mirror), "dn404Mirror");
        vm.label(address(dn404Handler), "dn404Handler");

        // target handlers
        targetContract(address(dn404Handler));
    }

    function invariantTotalReflectionIsValid() external {
        assertLe(
            dn404Mirror.totalSupply() * _WAD,
            dn404.totalSupply(),
            "NFT total supply * wad is greater than ERC20 total supply"
        );
    }

    function invariantUserReflectionIsValid() external {
        assertLe(
            dn404Mirror.balanceOf(user0) * _WAD,
            dn404.balanceOf(user0),
            "NFT balanceOf user 0 * wad is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user1) * _WAD,
            dn404.balanceOf(user1),
            "NFT balanceOf user 1 * wad is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user2) * _WAD,
            dn404.balanceOf(user2),
            "NFT balanceOf user 2 * wad is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user3) * _WAD,
            dn404.balanceOf(user3),
            "NFT balanceOf user 3 * wad is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user4) * _WAD,
            dn404.balanceOf(user4),
            "NFT balanceOf user 4 * wad is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user5) * _WAD,
            dn404.balanceOf(user5),
            "NFT balanceOf user 5 * wad is greater its ERC20 balanceOf"
        );
    }

    function invariantMirror721BalanceSum() external {
        uint256 total = dn404Handler.nftsOwned(user0) + dn404Handler.nftsOwned(user1)
            + dn404Handler.nftsOwned(user2) + dn404Handler.nftsOwned(user3)
            + dn404Handler.nftsOwned(user4) + dn404Handler.nftsOwned(user5);
        assertEq(total, dn404Mirror.totalSupply(), "all users nfts owned exceed nft total supply");
    }

    function invariantDN404BalanceSum() external {
        uint256 total = dn404.balanceOf(user0) + dn404.balanceOf(user1) + dn404.balanceOf(user2)
            + dn404.balanceOf(user3) + dn404.balanceOf(user4) + dn404.balanceOf(user5);
        assertEq(dn404.totalSupply(), total, "all users erc20 balance exceed erc20 total supply");
    }

    function invariantMirrorAndBaseRemainImmutable() external {
        assertEq(
            dn404.mirrorERC721(), address(dn404Mirror), "mirror 721 changed after initialization"
        );
        assertEq(dn404Mirror.baseERC20(), address(dn404), "base erc20 changed after initialization");
    }
}
