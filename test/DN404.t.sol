// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";

contract DN404Test is SoladyTest {
    uint256 private constant _WAD = 1000000000000000000;

    MockDN404 dn;
    DN404Mirror mirror;

    function setUp() public {
        dn = new MockDN404();
        mirror = new DN404Mirror(address(this));
    }

    function testNameAndSymbol(string memory name, string memory symbol) public {
        dn.initializeDN404(1000 * _WAD, address(this), address(mirror));
        dn.setNameAndSymbol(name, symbol);
        assertEq(mirror.name(), name);
        assertEq(mirror.symbol(), symbol);
    }

    function testTokenURI(string memory baseURI, uint256 id) public {
        dn.initializeDN404(1000 * _WAD, address(this), address(mirror));
        dn.setBaseURI(baseURI);
        assertEq(mirror.tokenURI(id), string(abi.encodePacked(baseURI, id)));
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
        if (totalNFTSupply > 0 && initialSupplyOwner == address(0)) {
            vm.expectRevert(DN404.TransferToZeroAddress.selector);
            dn.initializeDN404(totalNFTSupply * _WAD, initialSupplyOwner, address(mirror));
        } else if (uint256(totalNFTSupply) + 1 > type(uint32).max) {
            vm.expectRevert(DN404.TotalSupplyOverflow.selector);
            dn.initializeDN404(totalNFTSupply * _WAD, initialSupplyOwner, address(mirror));
        } else {
            dn.initializeDN404(totalNFTSupply * _WAD, initialSupplyOwner, address(mirror));
            assertEq(dn.totalSupply(), uint256(totalNFTSupply) * _WAD);
            assertEq(dn.balanceOf(initialSupplyOwner), uint256(totalNFTSupply) * _WAD);
            assertEq(mirror.totalSupply(), 0);
            assertEq(mirror.balanceOf(initialSupplyOwner), 0);
        }
    }

    function testWrapAround(uint32 totalNFTSupply, uint256 r) public {
        address alice = address(111);
        address bob = address(222);
        totalNFTSupply = uint32(_bound(totalNFTSupply, 1, 5));
        dn.initializeDN404(totalNFTSupply * _WAD, address(this), address(mirror));
        dn.transfer(alice, _WAD * uint256(totalNFTSupply));
        for (uint256 t; t != 1; ++t) {
            uint256 id = _bound(r, 1, totalNFTSupply);
            vm.prank(alice);
            mirror.transferFrom(alice, bob, id);
            vm.prank(bob);
            mirror.transferFrom(bob, alice, id);
            vm.prank(alice);
            dn.transfer(bob, _WAD);
            vm.prank(bob);
            dn.transfer(alice, _WAD);
        }
    }

    function testSetAndGetOperatorApprovals(address owner, address operator, bool approved)
        public
    {
        dn.initializeDN404(1000 * _WAD, address(this), address(mirror));
        assertEq(mirror.isApprovedForAll(owner, operator), false);
        vm.prank(owner);
        mirror.setApprovalForAll(operator, approved);
        assertEq(mirror.isApprovedForAll(owner, operator), approved);
    }

    function testMintOnTransfer(uint32 totalNFTSupply, address recipient) public {
        vm.assume(totalNFTSupply != 0 && uint256(totalNFTSupply) + 1 <= type(uint32).max);
        vm.assume(recipient.code.length == 0);
        vm.assume(recipient != address(0));

        dn.initializeDN404(totalNFTSupply * _WAD, address(this), address(mirror));

        assertEq(dn.totalSupply(), totalNFTSupply * _WAD);
        assertEq(mirror.totalSupply(), 0);

        vm.expectRevert(DN404.TokenDoesNotExist.selector);
        mirror.getApproved(1);

        dn.transfer(recipient, _WAD);

        assertEq(mirror.balanceOf(recipient), 1);
        assertEq(mirror.ownerOf(1), recipient);
        assertEq(mirror.totalSupply(), 1);

        assertEq(mirror.getApproved(1), address(0));
        vm.prank(recipient);
        mirror.approve(address(this), 1);
        assertEq(mirror.getApproved(1), address(this));
    }

    function testBurnOnTransfer(uint32 totalNFTSupply, address recipient) public {
        testMintOnTransfer(totalNFTSupply, recipient);

        vm.prank(recipient);
        dn.transfer(address(42069), totalNFTSupply + 1);

        mirror = DN404Mirror(payable(dn.mirrorERC721()));

        vm.expectRevert(DN404.TokenDoesNotExist.selector);
        mirror.ownerOf(1);
    }

    function testMintAndBurn() public {
        address initialSupplyOwner = address(1111);

        dn.initializeDN404(0, initialSupplyOwner, address(mirror));
        assertEq(dn.getSkipNFT(initialSupplyOwner), false);
        assertEq(dn.getSkipNFT(address(this)), true);

        vm.prank(initialSupplyOwner);
        dn.setSkipNFT(false);

        dn.mint(initialSupplyOwner, 4 * _WAD);
        assertEq(mirror.balanceOf(initialSupplyOwner), 4);

        dn.burn(initialSupplyOwner, 2 * _WAD);
        assertEq(mirror.balanceOf(initialSupplyOwner), 2);

        dn.mint(initialSupplyOwner, 3 * _WAD);
        assertEq(mirror.balanceOf(initialSupplyOwner), 5);

        for (uint256 i = 1; i <= 5; ++i) {
            assertEq(mirror.ownerOf(i), initialSupplyOwner);
        }

        uint256 count;
        for (uint256 i = 0; i < 10; ++i) {
            if (dn.ownerAt(i) == initialSupplyOwner) ++count;
        }
        assertEq(count, 5);

        dn.mint(initialSupplyOwner, 3 * _WAD);
        assertEq(mirror.balanceOf(initialSupplyOwner), 8);
    }

    function testMintAndBurn2() public {
        address initialSupplyOwner = address(1111);

        dn.initializeDN404(0, initialSupplyOwner, address(mirror));
        assertEq(dn.getSkipNFT(initialSupplyOwner), false);
        assertEq(dn.getSkipNFT(address(this)), true);

        vm.prank(initialSupplyOwner);
        dn.setSkipNFT(false);

        dn.mint(initialSupplyOwner, 1 * _WAD - 1);
        assertEq(mirror.balanceOf(initialSupplyOwner), 0);

        dn.burn(initialSupplyOwner, 1);
        assertEq(mirror.balanceOf(initialSupplyOwner), 0);

        dn.mint(initialSupplyOwner, 1 * _WAD + 2);
        assertEq(mirror.balanceOf(initialSupplyOwner), 2);

        dn.burn(initialSupplyOwner, 1);
        assertEq(mirror.balanceOf(initialSupplyOwner), 1);

        dn.mint(initialSupplyOwner, 1);
        assertEq(mirror.balanceOf(initialSupplyOwner), 2);

        for (uint256 i = 1; i <= 2; ++i) {
            assertEq(mirror.ownerOf(i), initialSupplyOwner);
        }

        uint256 count;
        for (uint256 i = 0; i < 10; ++i) {
            if (dn.ownerAt(i) == initialSupplyOwner) ++count;
        }
        assertEq(count, 2);
    }

    function testSetAndGetSkipNFT() public {
        assertEq(dn.getAddressDataInitialized(address(111)), false);
        vm.startPrank(address(111));
        dn.setSkipNFT(false);
        assertEq(dn.getSkipNFT(address(111)), false);
        assertEq(dn.getAddressDataInitialized(address(111)), true);
        dn.setSkipNFT(true);
        assertEq(dn.getSkipNFT(address(111)), true);
        assertEq(dn.getAddressDataInitialized(address(111)), true);
        dn.setSkipNFT(false);
        assertEq(dn.getSkipNFT(address(111)), false);
        assertEq(dn.getAddressDataInitialized(address(111)), true);
        vm.stopPrank();

        assertEq(dn.getAddressDataInitialized(address(this)), false);
        dn.setSkipNFT(false);
        assertEq(dn.getSkipNFT(address(this)), false);
        assertEq(dn.getAddressDataInitialized(address(this)), true);
        dn.setSkipNFT(true);
        assertEq(dn.getSkipNFT(address(this)), true);
        assertEq(dn.getAddressDataInitialized(address(this)), true);
        dn.setSkipNFT(false);
        assertEq(dn.getSkipNFT(address(this)), false);
        assertEq(dn.getAddressDataInitialized(address(this)), true);
    }

    function testSetAndGetAux(address a, uint88 aux) public {
        assertEq(dn.getAux(a), 0);
        dn.setAux(a, aux);
        assertEq(dn.getAux(a), aux);
        dn.setAux(a, 0);
        assertEq(dn.getAux(a), 0);
    }

    function testTransfersAndBurns() public {
        address initialSupplyOwner = address(1111);
        address alice = address(111);
        address bob = address(222);

        dn.initializeDN404(10 * _WAD, initialSupplyOwner, address(mirror));
        assertEq(dn.getSkipNFT(initialSupplyOwner), true);
        assertEq(dn.getSkipNFT(alice), false);
        assertEq(dn.getSkipNFT(bob), false);

        vm.prank(initialSupplyOwner);
        dn.transfer(alice, 5 * _WAD);

        vm.prank(initialSupplyOwner);
        dn.transfer(bob, 5 * _WAD);

        for (uint256 i = 1; i <= 5; ++i) {
            assertEq(dn.ownerAt(i), alice);
        }
        for (uint256 i = 6; i <= 10; ++i) {
            assertEq(dn.ownerAt(i), bob);
        }

        vm.prank(alice);
        dn.transfer(initialSupplyOwner, 5 * _WAD);

        for (uint256 i = 1; i <= 5; ++i) {
            assertEq(dn.ownerAt(i), address(0));
        }
        for (uint256 i = 6; i <= 10; ++i) {
            assertEq(dn.ownerAt(i), bob);
        }

        vm.prank(initialSupplyOwner);
        dn.transfer(alice, 1 * _WAD);
        assertEq(dn.ownerAt(1), alice);
    }

    // for viewing gas
    function testBatchNFTLog() external {
        uint32 totalNFTSupply = 10;
        address initialSupplyOwner = address(1111);
        dn.initializeDN404(totalNFTSupply * _WAD, initialSupplyOwner, address(mirror));

        vm.startPrank(initialSupplyOwner);
        dn.transfer(address(2222), 10e18);

        vm.startPrank(address(2222));
        dn.transfer(address(1111), 10e18);
    }
}
