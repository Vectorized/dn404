// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test, console2} from "forge-std/Test.sol";
import {MockDN404} from "../../utils/mocks/MockDN404.sol";
import {DN404Mirror} from "../../../src/DN404Mirror.sol";

contract DN404Handler is Test {
    uint256 private constant _WAD = 1000000000000000000;
    uint256 private constant START_SLOT =
        0x0000000000000000000000000000000000000000000000a20d6e21d0e5255308;
    uint8 internal constant _ADDRESS_DATA_SKIP_NFT_FLAG = 1 << 1;

    MockDN404 dn404;
    DN404Mirror mirror;

    uint256 public sum;

    address user0 = vm.addr(uint256(keccak256("OWNER")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));

    address[6] actors;

    mapping(address => uint256[]) public owned;
    mapping(uint256 => address) public ownerOf;

    function balanceOf(address a) external view returns (uint256) {
        return owned[a].length;
    }

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    constructor(MockDN404 _dn404) {
        dn404 = _dn404;
        mirror = DN404Mirror(payable(dn404.mirrorERC721()));

        actors[0] = user0;
        actors[1] = user1;
        actors[2] = user2;
        actors[3] = user3;
        actors[4] = user4;
        actors[5] = user5;

        vm.prank(user0);
        dn404.approve(user0, type(uint256).max);

        vm.prank(user1);
        dn404.approve(user1, type(uint256).max);

        vm.prank(user2);
        dn404.approve(user2, type(uint256).max);

        vm.prank(user3);
        dn404.approve(user3, type(uint256).max);

        vm.prank(user4);
        dn404.approve(user4, type(uint256).max);

        vm.prank(user5);
        dn404.approve(user5, type(uint256).max);
    }

    function randomAddress(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function approve(uint256 ownerIndexSeed, uint256 spenderIndexSeed, uint256 amount) external {
        address owner = randomAddress(ownerIndexSeed);
        address spender = randomAddress(spenderIndexSeed);

        if (owner == spender) return;

        vm.startPrank(owner);
        dn404.approve(spender, amount);
    }

    struct TransferCache {
        uint256 fromInitialTokenBalance;
        uint256 toInitialTokenBalance;
        uint256 initialToNFTBalance;
        uint256 initialFromNFTBalance;
        uint256 toAfterBalance;
        uint256 fromAfterBalance;
    }

    function transfer(uint256 fromIndexSeed, uint256 toIndexSeed, uint256 amount) external {
        address from = randomAddress(fromIndexSeed);
        address to = randomAddress(toIndexSeed);
        vm.startPrank(from);

        amount = bound(amount, 0, dn404.balanceOf(from));

        TransferCache memory transferCache;
        transferCache.toAfterBalance = dn404.balanceOf(to) + amount;
        transferCache.fromAfterBalance = dn404.balanceOf(from) - amount;

        uint256 max = dn404.totalSupply() / _WAD;
        uint256 nextId = dn404.getNextTokenId();

        transferCache.fromInitialTokenBalance = dn404.balanceOf(from);
        transferCache.toInitialTokenBalance = dn404.balanceOf(to);

        transferCache.initialToNFTBalance = mirror.balanceOf(to);
        transferCache.initialFromNFTBalance = mirror.balanceOf(from);

        unchecked {
            uint256 fromNftAmount =
                _zeroFloorSub(owned[from].length, transferCache.fromAfterBalance / _WAD);
            uint256 n = owned[from].length;
            for (uint256 i; i < fromNftAmount; ++i) {
                uint256 id = owned[from][--n];
                vm.expectEmit(true, true, true, false, address(mirror));
                emit Transfer(from, address(0), id);
                owned[from].pop();
                ownerOf[id] = address(0);
            }
        }

        uint256 toNftAmount;
        if (!dn404.getSkipNFT(to)) {
            toNftAmount = to != from
                ? (transferCache.toAfterBalance / _WAD) - owned[to].length
                : (transferCache.toInitialTokenBalance / _WAD) - owned[to].length;
        }

        unchecked {
            for (uint256 i; i < toNftAmount; ++i) {
                while (ownerOf[nextId] != address(0)) {
                    nextId = _wrapNFTId(nextId + 1, max);
                }
                vm.expectEmit(true, true, true, false, address(mirror));
                emit Transfer(address(0), to, nextId);
                owned[to].push(nextId);
                ownerOf[nextId] = to;
                nextId = _wrapNFTId(nextId + 1, max);
            }
        }

        vm.expectEmit(true, true, false, true, address(dn404));
        assembly {
            // log erc20 transfer using assembly because nft transfer is already defined
            mstore(0x00, amount)
            log3(
                0x00,
                0x20,
                0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
                from,
                to
            )
        }

        dn404.transfer(to, amount);

        if (to != from) {
            assertEq(mirror.balanceOf(from), owned[from].length);
            assertEq(mirror.balanceOf(to), owned[to].length);
            assertEq(dn404.balanceOf(from), transferCache.fromInitialTokenBalance - amount);
            assertEq(dn404.balanceOf(to), transferCache.toInitialTokenBalance + amount);
        } else {
            assertEq(mirror.balanceOf(from), owned[from].length);
            assertEq(dn404.balanceOf(from), transferCache.fromInitialTokenBalance);
        }
    }

    function transferFrom(
        uint256 senderIndexSeed,
        uint256 fromIndexSeed,
        uint256 toIndexSeed,
        uint256 amount
    ) external {
        address sender = randomAddress(senderIndexSeed);
        address from = randomAddress(fromIndexSeed);
        address to = randomAddress(toIndexSeed);
        vm.startPrank(sender);

        amount = bound(amount, 0, dn404.balanceOf(from));
        if (dn404.allowance(from, sender) < amount) {
            sender = from;
            vm.startPrank(sender);
        }

        TransferCache memory transferCache;

        transferCache.toAfterBalance = dn404.balanceOf(to) + amount;
        transferCache.fromAfterBalance = dn404.balanceOf(from) - amount;

        uint256 max = dn404.totalSupply() / _WAD;
        uint256 nextId = dn404.getNextTokenId();

        transferCache.fromInitialTokenBalance = dn404.balanceOf(from);
        transferCache.toInitialTokenBalance = dn404.balanceOf(to);

        transferCache.initialToNFTBalance = mirror.balanceOf(to);
        transferCache.initialFromNFTBalance = mirror.balanceOf(from);

        unchecked {
            uint256 fromNftAmount =
                _zeroFloorSub(owned[from].length, transferCache.fromAfterBalance / _WAD);
            uint256 n = owned[from].length;
            for (uint256 i; i < fromNftAmount; ++i) {
                uint256 id = owned[from][--n];
                vm.expectEmit(true, true, true, false, address(mirror));
                emit Transfer(from, address(0), id);
                owned[from].pop();
                ownerOf[id] = address(0);
            }
        }

        uint256 toNftAmount;
        if (!dn404.getSkipNFT(to)) {
            toNftAmount = to != from
                ? (transferCache.toAfterBalance / _WAD) - owned[to].length
                : (transferCache.toInitialTokenBalance / _WAD) - owned[to].length;
        }

        unchecked {
            for (uint256 i; i < toNftAmount; ++i) {
                while (ownerOf[nextId] != address(0)) {
                    nextId = _wrapNFTId(nextId + 1, max);
                }
                vm.expectEmit(true, true, true, false, address(mirror));
                emit Transfer(address(0), to, nextId);
                owned[to].push(nextId);
                ownerOf[nextId] = to;
                nextId = _wrapNFTId(nextId + 1, max);
            }
        }

        vm.expectEmit(true, true, false, true, address(dn404));
        assembly {
            // log erc20 transfer using assembly because nft transfer is already defined
            mstore(0x00, amount)
            log3(
                0x00,
                0x20,
                0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
                from,
                to
            )
        }

        dn404.transferFrom(from, to, amount);

        if (to != from) {
            assertEq(mirror.balanceOf(from), owned[from].length);
            assertEq(mirror.balanceOf(to), owned[to].length);
            assertEq(dn404.balanceOf(from), transferCache.fromInitialTokenBalance - amount);
            assertEq(dn404.balanceOf(to), transferCache.toInitialTokenBalance + amount);
        } else {
            assertEq(mirror.balanceOf(from), owned[from].length);
            assertEq(dn404.balanceOf(from), transferCache.fromInitialTokenBalance);
        }
    }

    function mint(uint256 toIndexSeed, uint256 amount) external {
        address to = randomAddress(toIndexSeed);
        amount = bound(amount, 0, 100e18);
        uint256 toInitialTokenBalance = dn404.balanceOf(to);

        uint256 nftAmount;
        if (!dn404.getSkipNFT(to)) {
            nftAmount = ((dn404.balanceOf(to) + amount) / _WAD) - owned[to].length;
        }

        unchecked {
            uint256 max = (dn404.totalSupply() + amount) / _WAD;
            uint256 nextId = dn404.getNextTokenId();
            for (uint256 i; i < nftAmount; ++i) {
                while (ownerOf[nextId] != address(0)) {
                    nextId = _wrapNFTId(nextId + 1, max);
                }
                vm.expectEmit(true, true, true, false, address(mirror));
                emit Transfer(address(0), to, nextId);
                owned[to].push(nextId);
                ownerOf[nextId] = to;
                nextId = _wrapNFTId(nextId + 1, max);
            }
        }

        vm.expectEmit(true, true, false, true, address(dn404));
        assembly {
            // log erc20 transfer using assembly because nft transfer is already defined
            mstore(0x00, amount)
            log3(
                0x00,
                0x20,
                0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
                0x00,
                to
            )
        }

        dn404.mint(to, amount);

        assertEq(mirror.balanceOf(to), owned[to].length);
        assertEq(dn404.balanceOf(to), toInitialTokenBalance + amount);

        sum += amount;
    }

    function burn(uint256 fromIndexSeed, uint256 amount) external {
        address from = randomAddress(fromIndexSeed);
        vm.startPrank(from);
        amount = bound(amount, 0, dn404.balanceOf(from));
        uint256 fromInitialTokenBalance = dn404.balanceOf(from);

        unchecked {
            uint256 nftAmount =
                _zeroFloorSub(owned[from].length, (dn404.balanceOf(from) - amount) / _WAD);
            uint256 n = owned[from].length;
            for (uint256 i; i < nftAmount; ++i) {
                uint256 id = owned[from][--n];
                vm.expectEmit(true, true, true, false, address(mirror));
                emit Transfer(from, address(0), id);
                owned[from].pop();
                ownerOf[id] = address(0);
            }
        }

        vm.expectEmit(true, true, false, true, address(dn404));
        assembly {
            // log erc20 transfer using assembly because nft transfer is already defined
            mstore(0x00, amount)
            log3(
                0x00,
                0x20,
                0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
                from,
                0x00
            )
        }

        dn404.burn(from, amount);

        assertEq(mirror.balanceOf(from), owned[from].length);
        assertEq(dn404.balanceOf(from), fromInitialTokenBalance - amount);

        sum -= amount;
    }

    function setSkipNFT(uint256 actorIndexSeed, bool status) external {
        vm.startPrank(randomAddress(actorIndexSeed));
        dn404.setSkipNFT(status);
    }

    function _zeroFloorSub(uint256 x, uint256 y) private pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    function _wrapNFTId(uint256 id, uint256 maxNFTId) private pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := gt(id, maxNFTId)
            result := or(result, mul(iszero(result), id))
        }
    }
}
