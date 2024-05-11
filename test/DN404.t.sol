// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {LibSort} from "solady/utils/LibSort.sol";

library DN404MirrorTransferEmitter {
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    function emitTransfer(address from, address to, uint256 id) internal {
        emit Transfer(from, to, id);
    }
}

contract DN404Test is SoladyTest {
    uint256 private constant _WAD = 1000000000000000000;

    address private constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    MockDN404 dn;
    DN404Mirror mirror;

    event SkipNFTSet(address indexed target, bool status);

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
        string memory expected = string(abi.encodePacked(baseURI, id));
        assertEq(DN404Mirror(payable(address(dn))).tokenURI(id), expected);
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
            if (mirror.ownerAt(i) == initialSupplyOwner) ++count;
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
            if (mirror.ownerAt(i) == initialSupplyOwner) ++count;
        }
        assertEq(count, 2);
    }

    function testSetAndGetSkipNFT() public {
        for (uint256 t; t != 10; ++t) {
            address a = address(uint160(t << 128));
            if (t & 1 == 0) a = LibClone.clone(a);
            // Contracts skip NFTs by default.
            assertEq(dn.getSkipNFT(a), t & 1 == 0);
            assertEq(dn.getAddressDataSkipNFTInitialized(a), false);
            _testSetAndGetSkipNFT(a, true);
            _testSetAndGetSkipNFT(a, false);
            _testSetAndGetSkipNFT(a, true);
        }
    }

    function _testSetAndGetSkipNFT(address target, bool status) internal {
        vm.prank(target);
        vm.expectEmit(true, true, true, true);
        emit SkipNFTSet(target, status);
        dn.setSkipNFT(status);
        assertEq(dn.getSkipNFT(target), status);
        assertEq(dn.getAddressDataSkipNFTInitialized(target), true);
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
            assertEq(mirror.ownerAt(i), alice);
        }
        for (uint256 i = 6; i <= 10; ++i) {
            assertEq(mirror.ownerAt(i), bob);
        }

        vm.prank(alice);
        dn.transfer(initialSupplyOwner, 5 * _WAD);

        for (uint256 i = 1; i <= 5; ++i) {
            assertEq(mirror.ownerAt(i), address(0));
        }
        for (uint256 i = 6; i <= 10; ++i) {
            assertEq(mirror.ownerAt(i), bob);
        }

        vm.prank(initialSupplyOwner);
        dn.transfer(alice, 1 * _WAD);
        assertEq(mirror.ownerAt(1), alice);
    }

    function testTransferWithMirrorEvent() public {
        address initialSupplyOwner = address(1111);
        address alice = address(111);
        address bob = address(222);

        dn.initializeDN404(10 * _WAD, initialSupplyOwner, address(mirror));

        vm.prank(initialSupplyOwner);
        dn.transfer(alice, 10 * _WAD);

        vm.expectEmit(true, true, true, true, address(mirror));
        DN404MirrorTransferEmitter.emitTransfer(alice, bob, 3);
        vm.prank(alice);
        dn.initiateTransferFromNFT(alice, bob, 3);

        assertEq(mirror.ownerAt(3), bob);
    }

    function _checkBurnPoolInvariant(address[] memory addresses) internal {
        unchecked {
            uint256[] memory allTokenIds;
            for (uint256 i; i != addresses.length; ++i) {
                address a = addresses[i];
                uint256[] memory tokens = dn.tokensOf(a);
                // Might not be sorted.
                LibSort.sort(tokens);
                allTokenIds = LibSort.union(allTokenIds, tokens);
                assertLe(tokens.length, dn.balanceOf(a) / _WAD);
            }
            assertEq(allTokenIds.length, mirror.totalSupply());
            uint256[] memory burnedPool = dn.burnedPool();
            LibSort.sort(burnedPool);
            assertEq(LibSort.intersection(burnedPool, allTokenIds).length, 0);
        }
    }

    struct _BalanceSumInvariantTemps {
        address a;
        uint256 nftBalance;
        uint256 nftBalanceSum;
        uint256 balance;
        uint256 balanceSum;
        uint256 tokenIdCeil;
        uint256 numOwned;
    }

    function _checkBalanceSumInvariant(address[] memory addresses) internal {
        _BalanceSumInvariantTemps memory t;
        unchecked {
            for (uint256 i; i != addresses.length; ++i) {
                t.a = addresses[i];
                t.balance = dn.balanceOf(t.a);
                t.balanceSum += t.balance;
                t.nftBalance = mirror.balanceOf(t.a);
                assertLe(t.nftBalance, t.balance / _WAD);
                t.nftBalanceSum += t.nftBalance;
                uint256[] memory tokens = dn.tokensOf(t.a);
                for (uint256 j; j != tokens.length; ++j) {
                    t.tokenIdCeil |= tokens[j];
                }
                if (_random() % 4 == 0) {
                    for (uint256 j; j != tokens.length; ++j) {
                        assertEq(mirror.ownerOf(tokens[j]), t.a);
                    }
                }
                assertEq(tokens.length, t.nftBalance);
            }
            assertEq(t.balanceSum, dn.totalSupply());
            assertEq(t.nftBalanceSum, mirror.totalSupply());
            assertLe(t.nftBalanceSum, t.balanceSum / _WAD);
            for (uint256 i; i <= t.tokenIdCeil; ++i) {
                if (mirror.ownerAt(i) != address(0)) t.numOwned++;
            }
            assertEq(t.numOwned, t.nftBalanceSum);
            assertEq(mirror.ownerAt(0), address(0));
            assertEq(mirror.ownerAt(t.tokenIdCeil + 1), address(0));
        }
    }

    function _maybeCheckInvariants(address[] memory addresses) internal {
        if (_random() % 16 == 0) _checkBurnPoolInvariant(addresses);
        if (_random() % 16 == 0) _checkBalanceSumInvariant(addresses);
    }

    function _doRandomDNTransfer(address[] memory addresses)
        internal
        checkERC721EventsWithBurnedPool
    {
        address from = addresses[_random() % addresses.length];
        uint256 amount = _bound(_random(), 0, dn.balanceOf(from));
        vm.prank(from);
        dn.transfer(addresses[_random() % addresses.length], amount);
    }

    function _doRandomMirrorTransfer(address[] memory addresses)
        internal
        checkERC721EventsWithBurnedPool
    {
        address from = addresses[_random() % addresses.length];
        unchecked {
            for (uint256 id = 1; id != 256; ++id) {
                address owner = mirror.ownerAt(id);
                if (owner == address(0)) {
                    if (_random() % 32 == 0) break;
                }
                if (owner == from && _random() % 2 == 0) {
                    vm.prank(from);
                    mirror.transferFrom(from, addresses[_random() % addresses.length], id);
                    break;
                }
            }
        }
    }

    function _doRandomTransfer(address[] memory addresses) internal {
        if (_random() % 4 == 0) {
            _doRandomMirrorTransfer(addresses);
        } else {
            _doRandomDNTransfer(addresses);
        }
    }

    function _randomizeConfigurations(address[] memory addresses) internal {
        if (_random() % 2 == 0) dn.setAddToBurnedPool(_random() % 2 == 0);
        if (_random() % 4 == 0) dn.setUseDirectTransfersIfPossible(_random() % 2 == 0);
        if (_random() % 8 == 0) {
            vm.prank(addresses[_random() % addresses.length]);
            dn.setSkipNFT(_random() & 1 == 0);
        }
    }

    modifier checkERC721EventsWithBurnedPool() {
        bool r = _random() % 8 == 0;
        if (r) vm.recordLogs();
        _;
        if (r) __checkERC721EventsWithBurnedPool();
    }

    function __checkERC721EventsWithBurnedPool() private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256[] memory burnedPool = dn.burnedPool();
        unchecked {
            for (uint256 i; i != logs.length; i++) {
                if (logs[i].topics.length != 4) continue;
                if (logs[i].topics[2] == bytes32(0)) continue;
                if (logs[i].topics[0] != keccak256("Transfer(address,address,uint256)")) continue;
                uint256 id = uint256(logs[i].topics[3]);
                for (uint256 j; j != burnedPool.length; j++) {
                    if (burnedPool[j] == id) {
                        revert("Token ID with non-zero address owner is still in burned pool.");
                    }
                }
            }
        }
    }

    function _mintNext(address to, uint256 amount) internal checkERC721EventsWithBurnedPool {
        dn.mintNext(to, amount);
    }

    function _mint(address to, uint256 amount) internal checkERC721EventsWithBurnedPool {
        dn.mint(to, amount);
    }

    function testMixed(bytes32) public {
        dn.setUseExistsLookup(_random() % 2 == 0);

        address[] memory addresses = new address[](3);
        addresses[0] = address(111);
        addresses[1] = address(222);
        addresses[2] = address(333);

        dn.initializeDN404(_bound(_random(), 0, 16) * _WAD, addresses[2], address(mirror));

        do {
            if (_random() % 2 == 0) _testMixed(addresses);
            if (_random() % 2 == 0) _testMixed2(addresses);
            if (_random() % 2 == 0) _testMixed3(addresses);
        } while (_random() % 4 == 0);

        _maybeCheckInvariants(addresses);

        if (_random() % 4 == 0) {
            for (uint256 i; i != addresses.length; ++i) {
                address a = addresses[i];
                vm.prank(a);
                dn.setSkipNFT(false);
                uint256 amount = dn.balanceOf(a);
                vm.prank(a);
                dn.transfer(a, amount);
                assertEq(mirror.balanceOf(a), dn.balanceOf(a) / _WAD);
            }
        }

        if (_random() % 32 == 0) {
            for (uint256 i; i != addresses.length; ++i) {
                address a = addresses[i];
                vm.prank(a);
                dn.setSkipNFT(true);
                uint256 amount = dn.balanceOf(a);
                vm.prank(a);
                dn.transfer(a, amount);
                assertEq(mirror.balanceOf(a), 0);
            }
        }
    }

    function _testMixed(address[] memory addresses) internal {
        do {
            _randomizeConfigurations(addresses);
            if (_random() % 16 != 0) _doRandomTransfer(addresses);
            _maybeCheckInvariants(addresses);
            _randomizeConfigurations(addresses);
            if (_random() % 4 == 0) {
                address from = addresses[_random() % addresses.length];
                address to = addresses[_random() % addresses.length];
                uint256 amount = _bound(_random(), 0, dn.balanceOf(from));
                dn.burn(from, amount);
                _maybeCheckInvariants(addresses);
                _mint(to, amount);
            }
            _randomizeConfigurations(addresses);
            if (_random() % 4 == 0) _doRandomTransfer(addresses);
            _maybeCheckInvariants(addresses);
        } while (_random() % 4 == 0);
    }

    function _testMixed2(address[] memory addresses) internal {
        do {
            _randomizeConfigurations(addresses);
            if (_random() % 2 == 0) _doRandomTransfer(addresses);
            _maybeCheckInvariants(addresses);
            _randomizeConfigurations(addresses);
            if (_random() % 2 == 0) {
                address from = addresses[_random() % addresses.length];
                address to = addresses[_random() % addresses.length];
                uint256 amount = _bound(_random(), 0, dn.balanceOf(from));
                dn.burn(from, amount);
                _maybeCheckInvariants(addresses);
                if (_random() % 2 == 0) amount = _bound(_random(), 0, 16 * _WAD);
                _randomizeConfigurations(addresses);
                if (_random() % 2 == 0) {
                    _mint(to, amount);
                } else {
                    _mintNext(to, amount);
                }
                _maybeCheckInvariants(addresses);
            }

            if (_random() % 8 == 0) {
                address to = addresses[_random() % addresses.length];
                uint256 amount = _bound(_random(), 0, 8 * _WAD);
                if (_random() % 2 == 0) dn.burn(to, _bound(_random(), 0, dn.balanceOf(to)));
                _maybeCheckInvariants(addresses);
                if (_random() % 2 == 0) {
                    _mintNext(to, amount);
                    _maybeCheckInvariants(addresses);
                    dn.burn(to, amount);
                } else {
                    _mintNext(to, amount);
                }
                _maybeCheckInvariants(addresses);
                if (_random() % 2 == 0) dn.burn(to, _bound(_random(), 0, dn.balanceOf(to)));
                _maybeCheckInvariants(addresses);
            }
            _randomizeConfigurations(addresses);
            if (_random() % 4 == 0) _doRandomTransfer(addresses);
            _maybeCheckInvariants(addresses);
        } while (_random() % 4 == 0);
    }

    function _testMixed3(address[] memory addresses) internal {
        do {
            _randomizeConfigurations(addresses);
            if (_random() % 2 == 0) _doRandomTransfer(addresses);
            _maybeCheckInvariants(addresses);
            _randomizeConfigurations(addresses);

            if (_random() % 2 == 0) {
                address to = addresses[_random() % addresses.length];
                uint256 amount = _bound(_random(), 0, 16 * _WAD);
                if (_random() % 2 == 0) {
                    _mint(to, amount);
                } else {
                    _mintNext(to, amount);
                }
                _maybeCheckInvariants(addresses);
            }

            if (_random() % 8 == 0) {
                address to = addresses[_random() % addresses.length];
                uint256 amount = _bound(_random(), 0, 8 * _WAD);
                _maybeCheckInvariants(addresses);
                _mintNext(to, amount);
                _maybeCheckInvariants(addresses);
            }

            _randomizeConfigurations(addresses);
            _doRandomTransfer(addresses);
            _maybeCheckInvariants(addresses);
        } while (_random() % 4 == 0);
    }

    function testBatchNFTLog() external {
        uint32 totalNFTSupply = 10;
        address initialSupplyOwner = address(1111);
        dn.initializeDN404(totalNFTSupply * _WAD, initialSupplyOwner, address(mirror));

        vm.startPrank(initialSupplyOwner);
        dn.transfer(address(2222), 10e18);

        vm.startPrank(address(2222));
        dn.transfer(address(1111), 10e18);
    }

    function testNumAliasesOverflowReverts() public {
        dn.setNumAliases(type(uint32).max);
        vm.expectRevert();
        dn.registerAndResolveAlias(address(this));
    }

    function testOwnedIds() public {
        dn.initializeDN404(5 * _WAD, address(this), address(mirror));

        address alice = address(111);
        dn.transfer(alice, 5 * _WAD);
        assertEq(mirror.balanceOf(alice), 5);

        assertEq(dn.ownedIds(alice, 0, type(uint256).max), _range(1, 6));

        for (uint256 j; j <= 5; ++j) {
            assertEq(dn.ownedIds(alice, 0, j), _range(1, 1 + j));
        }
        for (uint256 j = 6; j <= 10; ++j) {
            assertEq(dn.ownedIds(alice, 0, j), _range(1, 1 + 5));
        }
        for (uint256 j; j <= 5; ++j) {
            assertEq(dn.ownedIds(alice, j, 5), _range(1 + j, 1 + 5));
        }
        for (uint256 j; j <= 5; ++j) {
            assertEq(dn.ownedIds(alice, j, 10), _range(1 + j, 6));
        }
    }

    function testOwnedIds(uint256) public {
        uint256 totalNFTSupply = _random() % 10;
        dn.initializeDN404(totalNFTSupply * _WAD, address(this), address(mirror));

        address alice = address(111);
        dn.transfer(alice, totalNFTSupply * _WAD);
        assertEq(mirror.balanceOf(alice), totalNFTSupply);

        uint256 begin = _random() % (totalNFTSupply + 2);
        uint256 end = _random() % (totalNFTSupply + 2);
        uint256 numExpected;
        unchecked {
            uint256 n = totalNFTSupply + 5;
            for (uint256 i; i < n; ++i) {
                if (begin <= i && i < end && i < totalNFTSupply) ++numExpected;
            }
        }
        uint256[] memory expected = new uint256[](numExpected);
        unchecked {
            uint256 j;
            uint256 k = begin + 1; // Plus 1 as token IDs start at 1.
            for (uint256 i; i < numExpected; ++i) {
                expected[j++] = k++;
            }
        }
        assertEq(dn.ownedIds(alice, begin, end), expected);
    }

    function _range(uint256 start, uint256 end) internal pure returns (uint256[] memory a) {
        unchecked {
            if (start <= end) {
                uint256 n = end - start;
                a = new uint256[](n);
                for (uint256 i; i < n; ++i) {
                    a[i] = start + i;
                }
            }
        }
    }

    function testPermit2() public {
        address initialSupplyOwner = address(1111);
        address alice = address(111);
        address bob = address(222);

        assertEq(dn.allowance(alice, _PERMIT2), 0);
        dn.setGivePermit2DefaultInfiniteAllowance(true);
        assertEq(dn.allowance(alice, _PERMIT2), type(uint256).max);

        dn.initializeDN404(5 * _WAD, initialSupplyOwner, address(mirror));
        vm.prank(initialSupplyOwner);
        dn.transfer(alice, 5 * _WAD);

        dn.setGivePermit2DefaultInfiniteAllowance(false);
        assertEq(dn.allowance(alice, _PERMIT2), 0);

        vm.prank(_PERMIT2);
        vm.expectRevert(DN404.InsufficientAllowance.selector);
        dn.transferFrom(alice, bob, 1 * _WAD);

        dn.setGivePermit2DefaultInfiniteAllowance(true);
        assertEq(dn.allowance(alice, _PERMIT2), type(uint256).max);

        vm.prank(_PERMIT2);
        dn.transferFrom(alice, bob, 1 * _WAD);

        vm.prank(alice);
        dn.approve(_PERMIT2, 1 * _WAD - 1);
        assertEq(dn.allowance(alice, _PERMIT2), 1 * _WAD - 1);

        vm.startPrank(_PERMIT2);
        vm.expectRevert(DN404.InsufficientAllowance.selector);
        dn.transferFrom(alice, bob, 1 * _WAD);
        dn.transferFrom(alice, bob, 1 * _WAD - 2);
        assertEq(dn.allowance(alice, _PERMIT2), 1);
        dn.transferFrom(alice, bob, 1);
        assertEq(dn.allowance(alice, _PERMIT2), 0);
        vm.expectRevert(DN404.InsufficientAllowance.selector);
        dn.transferFrom(alice, bob, 1);
        vm.stopPrank();

        vm.prank(alice);
        dn.approve(_PERMIT2, 1);
        assertEq(dn.allowance(alice, _PERMIT2), 1);
    }

    function testFnSelectorNotRecognized() public {
        (bool success, bytes memory result) =
            address(dn).call(abi.encodeWithSignature("nonSupportedFunction123()"));
        assertFalse(success);
        assertEq(result, abi.encodePacked(DN404.FnSelectorNotRecognized.selector));
    }

    function testMintNext() public {
        address alice = address(111);
        address bob = address(222);

        dn.initializeDN404(10 * _WAD, address(this), address(mirror));
        dn.mintNext(alice, 10 * _WAD);
        for (uint256 i = 11; i <= 20; ++i) {
            assertEq(mirror.ownerAt(i), alice);
        }

        vm.prank(alice);
        dn.transfer(bob, 10 * _WAD);

        dn.mintNext(alice, 10 * _WAD);
        for (uint256 i = 21; i <= 30; ++i) {
            assertEq(mirror.ownerAt(i), alice);
        }
    }

    function testMintNextContiguous(uint256) public {
        address[] memory addresses = new address[](3);
        addresses[0] = address(111);
        addresses[1] = address(222);
        addresses[2] = address(this);
        uint256[] memory balances = new uint256[](2);
        uint256 totalMinted = (_random() % 4) * _WAD;

        dn.initializeDN404(totalMinted, address(this), address(mirror));

        do {
            if (_random() % 2 == 0) {
                dn.setAddToBurnedPool(_random() % 2 == 0);
            }

            do {
                uint256 i = _random() % 2;
                uint256 amount = (_random() % 4) * _WAD;
                balances[i] += amount;
                _mintNext(addresses[i], amount);
                totalMinted += amount;
            } while (_random() % 2 != 0);

            for (uint256 i; i != 2; ++i) {
                uint256 b = mirror.balanceOf(addresses[i]);
                if (b != 0) {
                    uint256 amount = (_random() % b) * _WAD;
                    dn.burn(addresses[i], amount);
                    balances[i] -= amount;
                }
            }

            do {
                uint256 i = _random() % 2;
                uint256 amount = (_random() % 4) * _WAD;
                balances[i] += amount;
                _mintNext(addresses[i], amount);
                totalMinted += amount;
            } while (_random() % 2 != 0);
        } while (_random() % 2 != 0);

        _maybeCheckInvariants(addresses);

        uint256[] memory expectedNFTBalances = new uint256[](2);
        {
            uint256[] memory allTokens;
            uint256 balancesSum;
            for (uint256 i; i != 2; ++i) {
                uint256[] memory tokens = dn.tokensOf(addresses[i]);
                assertEq(tokens.length, balances[i] / _WAD);
                LibSort.sort(tokens);
                LibSort.uniquifySorted(tokens);
                allTokens = LibSort.union(allTokens, tokens);
                balancesSum += balances[i];
                expectedNFTBalances[i] += tokens.length;
            }
            assertEq(allTokens.length, balancesSum / _WAD);
        }

        {
            uint256[] memory nftBalances = new uint256[](2);
            uint256 n = totalMinted / _WAD + 1;
            for (uint256 i; i != n; ++i) {
                address owner = mirror.ownerAt(i);
                for (uint256 j; j != 2; ++j) {
                    if (owner == addresses[j]) nftBalances[j]++;
                }
            }
            for (uint256 j; j != 2; ++j) {
                assertEq(nftBalances[j], expectedNFTBalances[j]);
            }
        }
    }

    function testZZZ() public {
        address alice = address(111);
        address bob = address(222);

        dn.initializeDN404(0, address(this), address(mirror));
        dn.mint(alice, 10 * _WAD);
        assertEq(dn.tokensOf(alice).length, mirror.balanceOf(alice));
        assertEq(mirror.balanceOf(alice), 10);
        assertEq(dn.tokensOf(bob).length, mirror.balanceOf(bob));
        assertEq(mirror.balanceOf(bob), 0);

        vm.prank(alice);
        dn.transfer(bob, 9 * _WAD);
        assertEq(dn.tokensOf(alice).length, mirror.balanceOf(alice));
        assertEq(mirror.balanceOf(alice), 1);
        assertEq(dn.tokensOf(bob).length, mirror.balanceOf(bob));
        assertEq(mirror.balanceOf(bob), 9);

        vm.prank(alice);
        dn.setSkipNFT(true);

        vm.prank(bob);
        dn.transfer(alice, 9 * _WAD);
        assertEq(dn.tokensOf(alice).length, mirror.balanceOf(alice));
        assertEq(mirror.balanceOf(alice), 1);
        assertEq(dn.tokensOf(bob).length, mirror.balanceOf(bob));
        assertEq(mirror.balanceOf(bob), 0);

        dn.mint(alice, 3 * _WAD);
        assertEq(dn.tokensOf(alice).length, mirror.balanceOf(alice));
        assertEq(mirror.balanceOf(alice), 1);
        assertEq(dn.tokensOf(bob).length, mirror.balanceOf(bob));
        assertEq(mirror.balanceOf(bob), 0);

        assertEq(dn.totalSupply(), 13 * _WAD);
        assertEq(dn.balanceOf(alice), 13 * _WAD);
    }
}
