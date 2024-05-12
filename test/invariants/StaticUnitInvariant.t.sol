// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "../utils/forge-std/Test.sol";
import {StdInvariant} from "../utils/forge-std/StdInvariant.sol";
import {DN404} from "../../src/DN404.sol";
import {DN404Mirror} from "../../src/DN404Mirror.sol";
import {MockDN404CustomUnit} from "../utils/mocks/MockDN404CustomUnit.sol";
import {DN404Handler} from "./handlers/DN404Handler.sol";
import {BaseInvariantTest} from "./BaseInvariant.t.sol";

// forgefmt: disable-start
/**************************************************************************************************************************************/
/*** Invariant Tests                                                                                                                ***/
/***************************************************************************************************************************************

    * NFT total supply * unit must always be less than or equal to the ERC20 total supply
    * NFT balance of a user * unit must be less than or equal to the ERC20 balance of that user

/**************************************************************************************************************************************/
/*** Common invariant test setup for invariants that do not modify the unit post-initialization.                                    ***/
/**************************************************************************************************************************************/
// forgefmt: disable-end
abstract contract StaticUnitInvariant is BaseInvariantTest {
    function setUp() public virtual override {
        BaseInvariantTest.setUp();

        // Selectors to target.
        // Currently excluding `setUnit`.
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = DN404Handler.approve.selector;
        selectors[1] = DN404Handler.transfer.selector;
        selectors[2] = DN404Handler.transferFrom.selector;
        selectors[3] = DN404Handler.mint.selector;
        selectors[4] = DN404Handler.burn.selector;
        selectors[5] = DN404Handler.setSkipNFT.selector;
        selectors[6] = DN404Handler.approveNFT.selector;
        selectors[7] = DN404Handler.setApprovalForAll.selector;
        selectors[8] = DN404Handler.transferFromNFT.selector;
        selectors[9] = DN404Handler.setUseDirectTransfersIfPossible.selector;
        selectors[10] = DN404Handler.setAddToBurnedPool.selector;
        selectors[11] = DN404Handler.setAux.selector;
        selectors[12] = DN404Handler.mintNext.selector;
        targetSelector(FuzzSelector({addr: address(dn404Handler), selectors: selectors}));
    }

    function invariantTotalReflectionIsValid() external {
        assertLe(
            dn404Mirror.totalSupply() * _unit(),
            dn404.totalSupply(),
            "NFT total supply * unit is greater than ERC20 total supply"
        );
    }

    function invariantUserReflectionIsValid() external {
        assertLe(
            dn404Mirror.balanceOf(user0) * _unit(),
            dn404.balanceOf(user0),
            "NFT balanceOf user 0 * unit is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user1) * _unit(),
            dn404.balanceOf(user1),
            "NFT balanceOf user 1 * unit is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user2) * _unit(),
            dn404.balanceOf(user2),
            "NFT balanceOf user 2 * unit is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user3) * _unit(),
            dn404.balanceOf(user3),
            "NFT balanceOf user 3 * unit is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user4) * _unit(),
            dn404.balanceOf(user4),
            "NFT balanceOf user 4 * unit is greater its ERC20 balanceOf"
        );
        assertLe(
            dn404Mirror.balanceOf(user5) * _unit(),
            dn404.balanceOf(user5),
            "NFT balanceOf user 5 * unit is greater its ERC20 balanceOf"
        );
    }
}
