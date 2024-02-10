// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
import {DN404NonFungibleShadow} from "../src/DN404NonFungibleShadow.sol";

contract DN404Test is SoladyTest {
    uint256 private constant _WAD = 1000000000000000000;

    MockDN404 dn;
    DN404NonFungibleShadow shadow;

    function setUp() public {
        dn = new MockDN404();
        shadow = new DN404NonFungibleShadow();
    }

    function testNameAndSymbol(string memory name, string memory symbol) public {
        dn.initializeDN404(1000, address(this), address(shadow));
        dn.setNameAndSymbol(name, symbol);
        assertEq(shadow.name(), name);
        assertEq(shadow.symbol(), symbol);
    }

    function testTokenURI(string memory baseURI, uint256 id) public {
        dn.initializeDN404(1000, address(this), address(shadow));
        dn.setBaseURI(baseURI);
        assertEq(shadow.tokenURI(id), string(abi.encodePacked(baseURI, id)));
    }

    function testRegisterAndResolveAlias(address a0, address a1) public {
        assertEq(dn.registerAndResolveAlias(a0), 1);
        if (a1 == a0) {
            assertEq(dn.registerAndResolveAlias(a1), 1);
        } else {
            assertEq(dn.registerAndResolveAlias(a1), 2);
            assertEq(dn.registerAndResolveAlias(a0), 1);
        }
    }

    function testInitialize(uint32 totalNFTSupply, address initialSupplyOwner) public {
        if (totalNFTSupply == 0 || uint256(totalNFTSupply) + 1 > type(uint32).max) {
            vm.expectRevert(DN404.InvalidTotalNFTSupply.selector);
            dn.initializeDN404(totalNFTSupply, initialSupplyOwner, address(shadow));
        } else if (initialSupplyOwner == address(0)) {
            vm.expectRevert(DN404.TransferToZeroAddress.selector);
            dn.initializeDN404(totalNFTSupply, initialSupplyOwner, address(shadow));
        } else {
            dn.initializeDN404(totalNFTSupply, initialSupplyOwner, address(shadow));
            assertEq(dn.totalSupply(), uint256(totalNFTSupply) * 10 ** 18);
            assertEq(dn.balanceOf(initialSupplyOwner), uint256(totalNFTSupply) * 10 ** 18);
            assertEq(shadow.totalSupply(), totalNFTSupply);
            assertEq(shadow.balanceOf(initialSupplyOwner), totalNFTSupply);
        }
    }

    function testSetAndGetOperatorApprovals(address owner, address operator, bool approved)
        public
    {
        dn.initializeDN404(1000, address(this), address(shadow));
        assertEq(shadow.isApprovedForAll(owner, operator), false);
        vm.prank(owner);
        shadow.setApprovalForAll(operator, approved);
        assertEq(shadow.isApprovedForAll(owner, operator), approved);
    }

    function testMintOnTransfer(
        uint32 totalNFTSupply,
        address initialSupplyOwner,
        address recipient
    ) public {
        vm.assume(
            totalNFTSupply != 0 && uint256(totalNFTSupply) + 1 <= type(uint32).max
                && initialSupplyOwner != address(0)
        );
        vm.assume(initialSupplyOwner != recipient && recipient != address(0));

        dn.initializeDN404(totalNFTSupply, initialSupplyOwner, address(shadow));

        vm.expectRevert(DN404NonFungibleShadow.TokenDoesNotExist.selector);
        shadow.getApproved(1);

        vm.prank(initialSupplyOwner);
        dn.transfer(recipient, _WAD);

        assertEq(shadow.balanceOf(recipient), 1);
        assertEq(shadow.ownerOf(1), recipient);

        assertEq(shadow.getApproved(1), address(0));
        vm.prank(recipient);
        shadow.approve(address(this), 1);
        assertEq(shadow.getApproved(1), address(this));
    }

    function testBurnOnTransfer(
        uint32 totalNFTSupply,
        address initialSupplyOwner,
        address recipient
    ) public {
        testMintOnTransfer(totalNFTSupply, initialSupplyOwner, recipient);

        vm.prank(recipient);
        dn.transfer(address(42069), totalNFTSupply + 1);

        shadow = DN404NonFungibleShadow(payable(dn.sisterERC721()));

        vm.expectRevert(DN404NonFungibleShadow.TokenDoesNotExist.selector);
        shadow.ownerOf(1);
    }
}
