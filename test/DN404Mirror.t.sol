// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
import {MockDN404Ownable} from "./utils/mocks/MockDN404Ownable.sol";
import {DN404Mirror, MockDN404Mirror} from "./utils/mocks/MockDN404Mirror.sol";
import {LibSort} from "solady/utils/LibSort.sol";

contract InvalidERC721Receiver {}

contract ERC721Receiver {
    bytes32 public lastReceivedHash;

    function onERC721Received(address by, address from, uint256 id, bytes calldata data)
        public
        returns (bytes4)
    {
        lastReceivedHash = keccak256(abi.encode(by, from, id, keccak256(data)));
        return msg.sig;
    }
}

contract DN404MirrorTest is SoladyTest {
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed account, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool isApproved);

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    uint256 private constant _WAD = 1000000000000000000;

    MockDN404 dn;
    MockDN404Mirror mirror;

    function setUp() public {
        dn = new MockDN404();
        mirror = new MockDN404Mirror(address(this));
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
        id = _bound(id, 1, 5);
        dn.initializeDN404(0, address(this), address(mirror));
        dn.setBaseURI(baseURI);
        address alice = address(111);
        dn.mint(alice, _WAD * uint256(id));
        assertEq(mirror.tokenURI(id), string(abi.encodePacked(baseURI, id)));
        vm.expectRevert(DN404.TokenDoesNotExist.selector);
        mirror.tokenURI(id + 1);
    }

    function testSupportsInterface() public {
        assertEq(mirror.supportsInterface(0x01ffc9a7), true);
        assertEq(mirror.supportsInterface(0x80ac58cd), true);
        assertEq(mirror.supportsInterface(0x5b5e139f), true);
    }

    function testBaseERC20() public {
        vm.expectRevert(DN404Mirror.NotLinked.selector);
        mirror.baseERC20();

        dn.initializeDN404(1000, address(this), address(mirror));
        assertEq(mirror.baseERC20(), address(dn));
    }

    function testSetAndGetApproved() public {
        dn.initializeDN404(uint96(10 * _WAD), address(this), address(mirror));
        address alice = address(111);
        address bob = address(222);

        dn.transfer(alice, _WAD * uint256(1));

        assertEq(mirror.getApproved(1), address(0));

        vm.expectRevert(DN404.TransferCallerNotOwnerNorApproved.selector);
        vm.prank(bob);
        mirror.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 1);
        mirror.approve(bob, 1);
        assertEq(mirror.getApproved(1), bob);

        vm.prank(bob);
        mirror.transferFrom(alice, bob, 1);
        assertEq(mirror.getApproved(1), address(0));
    }

    function testSetAndGetApprovalForAll() public {
        dn.initializeDN404(uint96(10 * _WAD), address(this), address(mirror));
        address alice = address(111);
        address bob = address(222);

        dn.transfer(alice, _WAD * uint256(1));

        vm.expectRevert(DN404.TransferCallerNotOwnerNorApproved.selector);
        vm.prank(bob);
        mirror.transferFrom(alice, bob, 1);

        assertEq(mirror.isApprovedForAll(alice, bob), false);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(alice, bob, true);
        mirror.setApprovalForAll(bob, true);
        assertEq(mirror.isApprovedForAll(alice, bob), true);

        vm.prank(bob);
        mirror.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(alice, bob, false);
        mirror.setApprovalForAll(bob, false);
        assertEq(mirror.isApprovedForAll(alice, bob), false);
    }

    function testTransferFrom(uint32 totalNFTSupply) public {
        totalNFTSupply = uint32(_bound(totalNFTSupply, 5, 1000000));
        address alice = address(111);
        address bob = address(222);

        uint256 initialSupply = uint256(totalNFTSupply) * _WAD;
        dn.initializeDN404(initialSupply, address(this), address(mirror));
        dn.transfer(alice, _WAD * uint256(5));
        assertEq(mirror.balanceOf(alice), 5);
        assertEq(mirror.balanceOf(bob), 0);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 1);
        mirror.transferFrom(alice, bob, 1);
        assertEq(mirror.balanceOf(alice), 4);
        assertEq(mirror.balanceOf(bob), 1);
        assertEq(dn.totalSupply(), initialSupply);
        assertEq(mirror.totalSupply(), 5);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(bob, bob, 1);
        mirror.transferFrom(bob, bob, 1);
        assertEq(mirror.balanceOf(alice), 4);
        assertEq(mirror.balanceOf(bob), 1);
        assertEq(dn.totalSupply(), initialSupply);
        assertEq(mirror.totalSupply(), 5);
        assertEq(dn.balanceOf(alice), 4 * _WAD);
        assertEq(dn.balanceOf(bob), 1 * _WAD);
    }

    function testTransferFromMixed(uint256) public {
        uint256 maxNFTId = _bound(_random(), 50, 100);
        dn.initializeDN404(maxNFTId * _WAD, address(this), address(mirror));

        uint256 n = _bound(_random(), 1, 5);
        address[] memory addresses = new address[](n);
        for (uint256 i; i < n; ++i) {
            addresses[i] = _randomNonZeroAddress();
        }
        LibSort.insertionSort(addresses);
        LibSort.uniquifySorted(addresses);

        n = addresses.length;

        do {
            uint256 amount = _bound(_random(), 0, 2) * _WAD;
            if (dn.balanceOf(address(this)) >= amount) {
                dn.transfer(addresses[_random() % n], amount);
            }
        } while (_random() % 16 > 0);

        uint256 totalNFTSupply = mirror.totalSupply();
        do {
            address to = addresses[_random() % n];
            address from = addresses[_random() % n];
            if (mirror.balanceOf(from) > 0) {
                uint256 randomTokenId = dn.randomTokenOf(from, _random());
                vm.prank(from);
                mirror.transferFrom(from, to, randomTokenId);
            }
        } while (_random() % 4 > 0);

        uint256[] memory allTokenIds;
        for (uint256 i; i < n; ++i) {
            uint256[] memory tokens = dn.tokensOf(addresses[i]);
            // Might not be sorted.
            LibSort.insertionSort(tokens);
            allTokenIds = LibSort.union(allTokenIds, tokens);
            assertLe(tokens.length, dn.balanceOf(addresses[i]) / _WAD);
        }
        assertTrue(LibSort.isSorted(allTokenIds));
        assertEq(allTokenIds.length, totalNFTSupply);
        if (allTokenIds.length != 0) {
            assertLe(allTokenIds[allTokenIds.length - 1], maxNFTId);
        }

        if (_random() % 4 == 0) {
            assertEq(mirror.ownerAt(0), address(0));
            uint256 totalOwned;
            for (uint256 i = 1; i <= maxNFTId; ++i) {
                if (mirror.ownerAt(i) != address(0)) totalOwned++;
            }
            assertEq(totalOwned, totalNFTSupply);
        }
    }

    function testSafeTransferFrom(uint32 totalNFTSupply, bytes memory randomBytes) public {
        totalNFTSupply = uint32(_bound(totalNFTSupply, 5, 1000000));
        address alice = address(111);
        address bob = address(222);

        dn.initializeDN404(uint96(uint256(totalNFTSupply) * _WAD), address(this), address(mirror));
        dn.transfer(alice, _WAD * uint256(5));
        assertEq(mirror.balanceOf(alice), 5);
        assertEq(mirror.balanceOf(bob), 0);

        if (_random() % 2 == 0) {
            address to = address(new InvalidERC721Receiver());

            vm.prank(alice);
            vm.expectRevert(DN404Mirror.TransferToNonERC721ReceiverImplementer.selector);
            mirror.safeTransferFrom(alice, to, 1);

            vm.prank(alice);
            mirror.safeTransferFrom(alice, bob, 1);
            assertEq(mirror.balanceOf(alice), 4);
            assertEq(mirror.balanceOf(bob), 1);
        } else {
            address to = address(new ERC721Receiver());
            address operator = _randomNonZeroAddress();
            vm.prank(alice);
            mirror.setApprovalForAll(operator, true);

            if (randomBytes.length == 0 && _random() % 2 == 0) {
                vm.prank(operator);
                mirror.safeTransferFrom(alice, to, 1);
            } else {
                vm.prank(operator);
                mirror.safeTransferFrom(alice, to, 1, randomBytes);
            }

            bytes32 h = keccak256(abi.encode(operator, alice, 1, keccak256(randomBytes)));
            assertEq(ERC721Receiver(to).lastReceivedHash(), h);
        }
    }

    function testLinkMirrorContract() public {
        (bool success, bytes memory data) =
            address(mirror).call(abi.encodeWithSignature("linkMirrorContract(address)", address(1)));
        assertEq(data, abi.encodePacked(DN404Mirror.SenderNotDeployer.selector));

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
        emit Transfer(address(0), to, id);
        vm.expectEmit(true, true, true, true);
        emit Transfer(from, address(0), id);
        (bool success,) =
            address(mirror).call(abi.encodeWithSignature("logTransfer(uint256[])", packedLogs));
        assertTrue(success);
    }

    function testLogDirectTransfers() public {
        dn.initializeDN404(5 * _WAD, address(this), address(mirror));
        dn.setUseDirectTransfersIfPossible(true);
        address alice = address(111);
        address bob = address(222);

        dn.transfer(alice, 5 * _WAD);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        for (uint256 i = 5; i != 0; --i) {
            emit Transfer(alice, bob, i);
        }
        dn.transfer(bob, 5 * _WAD);

        vm.prank(address(dn));
        uint256[] memory directLogs = new uint256[](0);
        (bool success,) = address(mirror).call(
            abi.encodeWithSignature(
                "logDirectTransfer(address,address,uint256[])", alice, bob, directLogs
            )
        );
        assertTrue(success);
    }

    function testPullOwner() public {
        dn.initializeDN404(1000, address(this), address(mirror));
        assertEq(mirror.owner(), address(0));
        mirror.pullOwner();
        assertEq(mirror.owner(), address(0));
    }

    function testAutomaticPullOwnerWithOwnable() public {
        MockDN404Ownable dnOwnable = new MockDN404Ownable(address(0));
        dnOwnable.initializeDN404(1000, address(this), address(mirror));
        assertEq(mirror.owner(), address(0));
        mirror.pullOwner();
        assertEq(mirror.owner(), address(0));

        dnOwnable.initializeOwner(address(this));
        assertEq(mirror.owner(), address(0));
        mirror.pullOwner();
        assertEq(mirror.owner(), address(this));

        address newOwner = address(123);
        dnOwnable.transferOwnership(newOwner);

        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(this), newOwner);
        mirror.pullOwner();
        assertEq(mirror.owner(), newOwner);
    }

    function testAutomaticPullOwnerWithOwnable2() public {
        MockDN404Ownable dnOwnable = new MockDN404Ownable(address(this));
        assertEq(mirror.owner(), address(0));
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(address(0), address(this));
        dnOwnable.initializeDN404(1000, address(this), address(mirror));
        assertEq(mirror.owner(), address(this));
    }

    function testFnSelectorNotRecognized() public {
        (bool success, bytes memory result) =
            address(dn).call(abi.encodeWithSignature("nonSupportedFunction123()"));
        assertFalse(success);
        assertEq(result, abi.encodePacked(DN404.FnSelectorNotRecognized.selector));
    }
}
