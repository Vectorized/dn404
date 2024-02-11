// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";

contract Invalid721Receiver {}

contract DN404MirrorTest is SoladyTest {
    uint256 private constant _WAD = 1000000000000000000;

    MockDN404 dn;
    DN404Mirror mirror;

    function setUp() public {
        dn = new MockDN404();
        mirror = new DN404Mirror();
    }

    function testNotLinked() public {
        vm.expectRevert(DN404Mirror.NotLinked.selector);
        mirror.name();
    }

    function testNameAndSymbol(string memory name, string memory symbol) public {
        dn.initializeDN404(1000, address(this), address(mirror));
        dn.setNameAndSymbol(name, symbol);
        assertEq(mirror.name(), name);
        assertEq(mirror.symbol(), symbol);
    }

    function testTokenURI(string memory baseURI, uint256 id) public {
        dn.initializeDN404(1000, address(this), address(mirror));
        dn.setBaseURI(baseURI);
        assertEq(mirror.tokenURI(id), string(abi.encodePacked(baseURI, id)));
    }

    function testSupportsInterface() public {
        assertEq(mirror.supportsInterface(0x01ffc9a7), true);
        assertEq(mirror.supportsInterface(0x80ac58cd), true);
        assertEq(mirror.supportsInterface(0x5b5e139f), true);
    }

    function testRootERC20() public {
        vm.expectRevert(DN404Mirror.NotLinked.selector);
        mirror.rootERC20();

        dn.initializeDN404(1000, address(this), address(mirror));
        assertEq(mirror.rootERC20(), address(dn));
    }

    function testTransferFrom(uint32 totalNFTSupply) public {
        totalNFTSupply = uint32(_bound(totalNFTSupply, 5, 1000000));
        address alice = address(111);
        address bob = address(222);

        dn.initializeDN404(totalNFTSupply, address(this), address(mirror));
        dn.transfer(alice, _WAD * uint256(5));
        assertEq(mirror.balanceOf(alice), 5);
        assertEq(mirror.balanceOf(bob), 0);

        vm.prank(alice);
        mirror.transferFrom(alice, bob, 1);
        assertEq(mirror.balanceOf(alice), 4);
        assertEq(mirror.balanceOf(bob), 1);
    }

    function testSafeTransferFrom(uint32 totalNFTSupply) public {
        totalNFTSupply = uint32(_bound(totalNFTSupply, 5, 1000000));
        address alice = address(111);
        address bob = address(222);
        address invalid = address(new Invalid721Receiver());

        dn.initializeDN404(totalNFTSupply, address(this), address(mirror));
        dn.transfer(alice, _WAD * uint256(5));
        assertEq(mirror.balanceOf(alice), 5);
        assertEq(mirror.balanceOf(bob), 0);

        vm.prank(alice);
        vm.expectRevert(DN404Mirror.TransferToNonERC721ReceiverImplementer.selector);
        mirror.safeTransferFrom(alice, invalid, 1);

        vm.prank(alice);
        mirror.safeTransferFrom(alice, bob, 1);
        assertEq(mirror.balanceOf(alice), 4);
        assertEq(mirror.balanceOf(bob), 1);
    }

    function testLinkMirrorContract() public {
        (bool success, bytes memory data) =
            address(mirror).call(abi.encodeWithSignature("linkMirrorContract(address)", address(1)));
        assertEq(data, abi.encodePacked(DN404Mirror.Unauthorized.selector));

        vm.prank(address(dn));
        (success, data) = address(mirror).call(
            abi.encodeWithSignature("linkMirrorContract(address)", address(this))
        );
        assertEq(success, true);
        assertEq(data, abi.encode(0x1));
    }

    function testLogTransfer() public {
        dn.initializeDN404(1000, address(this), address(mirror));

        uint256[] memory packedLogs = new uint256[](2);

        address to = address(111);
        address from = address(222);
        uint32 id = 88;
        packedLogs[0] = (uint256(uint160(to)) << 96) | (id << 8);
        packedLogs[1] = (uint256(uint160(from)) << 96) | (id << 8) | 1;

        vm.prank(address(dn));
        vm.expectEmit(true, true, true, true);
        emit DN404Mirror.Transfer(address(0), to, id);
        vm.expectEmit(true, true, true, true);
        emit DN404Mirror.Transfer(from, address(0), id);
        mirror.logTransfer(packedLogs);
    }
}
