// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";
import {LibBit} from "solady/utils/LibBit.sol";

contract MappingsTest is SoladyTest {
    using LibPRNG for *;

    /// @dev A uint32 map in storage.
    struct Uint32Map {
        uint256 spacer;
    }

    /// @dev A bitmap in storage.
    struct Bitmap {
        uint256 spacer;
    }

    /// @dev A mapping of an address pair to a Uint256Ref.
    struct AddressPairToUint256RefMap {
        uint256 spacer;
    }

    /// @dev A struct to wrap a uint256 in storage.
    struct Uint256Ref {
        uint256 value;
    }

    /// @dev Returns a storage reference to the value at (`a0`, `a1`) in `map`.
    function _ref(AddressPairToUint256RefMap storage map, address a0, address a1)
        internal
        pure
        returns (Uint256Ref storage ref)
    {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x28, a1)
            mstore(0x14, a0)
            mstore(0x00, map.slot)
            ref.slot := keccak256(0x00, 0x48)
            // Clear the part of the free memory pointer that was overwritten.
            mstore(0x28, 0x00)
        }
    }

    /// @dev Returns `(i - 1) << 1`.
    function _ownershipIndex(uint256 i) internal pure returns (uint256) {
        unchecked {
            return (i - 1) << 1; // Minus 1 as token IDs start from 1.
        }
    }

    /// @dev Returns `((i - 1) << 1) + 1`.
    function _ownedIndex(uint256 i) internal pure returns (uint256) {
        unchecked {
            return ((i - 1) << 1) + 1; // Minus 1 as token IDs start from 1.
        }
    }

    /// @dev Returns the uint32 value at `index` in `map`.
    function _get(Uint32Map storage map, uint256 index) internal view returns (uint32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, map.slot), shr(3, index)) // Storage slot.
            result := and(0xffffffff, shr(shl(5, and(index, 7)), sload(s)))
        }
    }

    /// @dev Updates the uint32 value at `index` in `map`.
    function _set(Uint32Map storage map, uint256 index, uint32 value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, map.slot), shr(3, index)) // Storage slot.
            let o := shl(5, and(index, 7)) // Storage slot offset (bits).
            let v := sload(s) // Storage slot value.
            let m := 0xffffffff // Value mask.
            sstore(s, xor(v, shl(o, and(m, xor(shr(o, v), value)))))
        }
    }

    /// @dev Sets the owner alias and the owned index together.
    function _setOwnerAliasAndOwnedIndex(
        Uint32Map storage map,
        uint256 id,
        uint32 ownership,
        uint32 ownedIndex
    ) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let i := sub(id, 1) // Index of the uint64 combined value.
            let s := add(shl(96, map.slot), shr(2, i)) // Storage slot.
            let o := shl(6, and(i, 3)) // Storage slot offset (bits).
            let v := sload(s) // Storage slot value.
            let m := 0xffffffffffffffff // Value mask.
            let combined := or(shl(32, ownedIndex), and(0xffffffff, ownership))
            sstore(s, xor(v, shl(o, and(m, xor(shr(o, v), combined)))))
        }
    }

    /// @dev Returns the boolean value of the bit at `index` in `bitmap`.
    function _get(Bitmap storage bitmap, uint256 index) internal view returns (bool isSet) {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, bitmap.slot), shr(8, index))
            isSet := and(1, shr(and(0xff, index), sload(s)))
        }
    }

    /// @dev Updates the bit at `index` in `bitmap` to `value`.
    function _set(Bitmap storage bitmap, uint256 index, bool value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, bitmap.slot), shr(8, index)) // Storage slot.
            let o := and(0xff, index) // Storage slot offset (bits).
            sstore(s, or(and(sload(s), not(shl(o, 1))), shl(o, iszero(iszero(value)))))
        }
    }

    /// @dev Returns `id > type(uint32).max ? 0 : id`.
    function _restrictNFTId(uint256 id) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mul(id, lt(id, 0x100000000))
        }
    }

    /// @dev Returns the index of the least significant unset bit in `[begin..upTo]`.
    /// If no set bit is found, returns `type(uint256).max`.
    function _findFirstUnset(Bitmap storage bitmap, uint256 begin, uint256 upTo)
        internal
        view
        returns (uint256 unsetBitIndex)
    {
        /// @solidity memory-safe-assembly
        assembly {
            unsetBitIndex := not(0) // Initialize to `type(uint256).max`.
            let s := shl(96, bitmap.slot) // Storage offset of the bitmap.
            let bucket := add(s, shr(8, begin))
            let lastBucket := add(s, shr(8, upTo))
            let negBits := shl(and(0xff, begin), shr(and(0xff, begin), not(sload(bucket))))
            if iszero(negBits) {
                for {} 1 {} {
                    bucket := add(bucket, 1)
                    negBits := not(sload(bucket))
                    if or(negBits, gt(bucket, lastBucket)) { break }
                }
                if gt(bucket, lastBucket) {
                    negBits := shr(and(0xff, not(upTo)), shl(and(0xff, not(upTo)), negBits))
                }
            }
            if negBits {
                // Find-first-set routine.
                let b := and(negBits, add(not(negBits), 1)) // Isolate the least significant bit.
                let r := shl(7, lt(0xffffffffffffffffffffffffffffffff, b))
                r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, b))))
                r := or(r, shl(5, lt(0xffffffff, shr(r, b))))
                // For the remaining 32 bits, use a De Bruijn lookup.
                // forgefmt: disable-next-item
                r := or(r, byte(and(div(0xd76453e0, shr(r, b)), 0x1f),
                    0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
                r := or(shl(8, sub(bucket, s)), r)
                unsetBitIndex := or(r, sub(0, or(gt(r, upTo), lt(r, begin))))
            }
        }
    }

    function _fillBucket(Bitmap storage bitmap, uint256 i) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, bitmap.slot), i) // Storage slot.
            sstore(s, not(0))
        }
    }

    function testFindFirstUnset() public {
        assertEq(_findFirstUnset(bitmapA, 0, 1000), 0);
        _set(bitmapA, 1, true);
        assertEq(_findFirstUnset(bitmapA, 0, 1000), 0);
        _set(bitmapA, 0, true);
        assertEq(_findFirstUnset(bitmapA, 0, 1000), 2);
        _fillBucket(bitmapA, 0);
        assertEq(_findFirstUnset(bitmapA, 0, 1000), 256);
        _set(bitmapA, 256, true);
        assertEq(_findFirstUnset(bitmapA, 0, 1000), 257);

        assertEq(_findFirstUnset(bitmapB, 500, 1000), 500);
        _fillBucket(bitmapB, 1); // Set bits `[256..511]`.
        assertEq(_findFirstUnset(bitmapB, 500, 1000), 512);
        assertEq(_findFirstUnset(bitmapB, 500, 513), 512);
        assertEq(_findFirstUnset(bitmapB, 500, 512), 512);
        assertEq(_findFirstUnset(bitmapB, 500, 511), type(uint256).max);
        assertEq(_findFirstUnset(bitmapB, 256, 512), 512);
        assertEq(_findFirstUnset(bitmapB, 256, 511), type(uint256).max);
        assertEq(_findFirstUnset(bitmapB, 255, 512), 255);
        assertEq(_findFirstUnset(bitmapB, 255, 255), 255);
        assertEq(_findFirstUnset(bitmapB, 255, 254), type(uint256).max);
    }

    function testFindFirstUnset(uint256) public {
        uint256[] memory m = new uint256[](5);

        do {
            if (_random() % 4 > 0) {
                uint256 n = _random() % 32;
                for (uint256 t; t != n; ++t) {
                    uint256 r = _random() % 1024;
                    m[r >> 8] |= 1 << (r & 0xff);
                    _set(bitmapA, r, true);
                }
            }
            if (_random() % 4 > 0) {
                uint256 n = _random() % 8;
                for (uint256 t; t != n; ++t) {
                    uint256 o = _random() % 1024;
                    uint256 q = _random() % 64;
                    for (uint256 j; j != q; ++j) {
                        uint256 r = j + o;
                        if (r >= 1024) break;
                        m[r >> 8] |= 1 << (r & 0xff);
                        _set(bitmapA, r, true);
                    }
                }
            }
            for (uint256 j; j != 4; ++j) {
                if (_random() % 8 == 0) {
                    _fillBucket(bitmapA, j);
                    m[j] = type(uint256).max;
                }
            }
            do {
                uint256 begin = _random() % (1024 + 10);
                uint256 upTo = _random() % (1024 + 10);
                uint256 actual = _findFirstUnset(bitmapA, begin, upTo);
                uint256 expected = _findFirstUnset(m, begin, upTo);
                assertEq(actual, expected);
            } while (_random() % 16 > 0);
        } while (_random() % 2 == 0);
    }

    function _findFirstUnset(uint256[] memory m, uint256 begin, uint256 upTo)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i = begin; i <= upTo; ++i) {
            if ((m[i >> 8] >> (i & 0xff)) & 1 == 0) return i;
        }
        return type(uint256).max;
    }

    Bitmap bitmapA;
    Bitmap bitmapB;

    Uint32Map uint32MapA;
    Uint32Map uint32MapB;

    AddressPairToUint256RefMap addressPairMapA;
    AddressPairToUint256RefMap addressPairMapB;

    mapping(uint256 => bool) internal bitmapGroundTruthA;
    mapping(uint256 => bool) internal bitmapGroundTruthB;

    mapping(uint256 => uint32) internal uint32MapGroundTruthA;
    mapping(uint256 => uint32) internal uint32MapGroundTruthB;

    function testBitmapSetAndGet(uint256 i0, uint256 i1, bool b0, bool b1) public {
        i0 = _bound(i0, 0, type(uint96).max);
        i1 = _bound(i1, 0, type(uint96).max);
        assertEq(_get(bitmapA, i0), false);
        assertEq(_get(bitmapB, i1), false);
        _set(bitmapA, i0, b0);
        _set(bitmapB, i1, b1);
        assertEq(_get(bitmapA, i0), b0);
        assertEq(_get(bitmapB, i1), b1);
    }

    function testBitmapSetAndGet(uint256 seed) public {
        LibPRNG.PRNG memory prng;
        prng.state = seed;

        uint256 n = _random() % 32;
        for (uint256 t; t < n; ++t) {
            {
                uint256 r = prng.next();
                bool b = r & 1 == 0;
                uint256 i = _bound(r >> 8, 0, 512);
                _set(bitmapA, i, b);
                bitmapGroundTruthA[i] = b;
            }
            {
                uint256 r = prng.next();
                bool b = r & 1 == 0;
                uint256 i = _bound(r >> 8, 0, 512);
                _set(bitmapB, i, b);
                bitmapGroundTruthB[i] = b;
            }
        }

        prng.state = seed;
        for (uint256 t; t < n; ++t) {
            {
                uint256 r = prng.next();
                uint256 i = _bound(r >> 8, 0, 512);
                assertEq(_get(bitmapA, i), bitmapGroundTruthA[i]);
            }
            {
                uint256 r = prng.next();
                uint256 i = _bound(r >> 8, 0, 512);
                assertEq(_get(bitmapB, i), bitmapGroundTruthB[i]);
            }
        }
    }

    function testUint32MapSetAndGet(uint256 i0, uint256 i1, uint32 v0, uint32 v1) public {
        i0 = _bound(i0, 0, type(uint96).max);
        i1 = _bound(i1, 0, type(uint96).max);
        assertEq(_get(uint32MapA, i0), 0);
        assertEq(_get(uint32MapB, i1), 0);
        _set(uint32MapA, i0, v0);
        _set(uint32MapB, i1, v1);
        assertEq(_get(uint32MapA, i0), v0);
        assertEq(_get(uint32MapB, i1), v1);
    }

    function testUint32MapSetAndGet(uint256 seed) public {
        LibPRNG.PRNG memory prng;
        prng.state = seed;

        uint256 n = _random() % 32;
        for (uint256 t; t < n; ++t) {
            {
                uint256 r = prng.next();
                uint32 v = uint32(r & 0xffffffff);
                uint256 i = _bound(r >> 32, 0, 512);
                _set(uint32MapA, i, v);
                uint32MapGroundTruthA[i] = v;
            }
            {
                uint256 r = prng.next();
                uint32 v = uint32(r & 0xffffffff);
                uint256 i = _bound(r >> 32, 0, 512);
                _set(uint32MapB, i, v);
                uint32MapGroundTruthB[i] = v;
            }
        }

        prng.state = seed;
        for (uint256 t; t < n; ++t) {
            {
                uint256 r = prng.next();
                uint256 i = _bound(r >> 32, 0, 512);
                assertEq(_get(uint32MapA, i), uint32MapGroundTruthA[i]);
            }
            {
                uint256 r = prng.next();
                uint256 i = _bound(r >> 32, 0, 512);
                assertEq(_get(uint32MapB, i), uint32MapGroundTruthB[i]);
            }
        }
    }

    function testSetOwnerAliasAndOwnedIndex(uint256 id, uint32 ownership, uint32 ownedIndex)
        public
    {
        id = _bound(id, 1, type(uint32).max);
        _setOwnerAliasAndOwnedIndex(uint32MapA, id, ownership, ownedIndex);
        assertEq(_get(uint32MapA, _ownershipIndex(id)), ownership);
        assertEq(_get(uint32MapA, _ownedIndex(id)), ownedIndex);
    }

    function testAddressPairMapSetAndGet(
        address[2] memory a0,
        address[2] memory a1,
        uint256 v0,
        uint256 v1
    ) public {
        assertEq(_ref(addressPairMapA, _brutalized(a0[0]), _brutalized(a1[0])).value, 0);
        assertEq(_ref(addressPairMapB, _brutalized(a0[1]), _brutalized(a1[1])).value, 0);
        _ref(addressPairMapA, a0[0], a1[0]).value = v0;
        _ref(addressPairMapB, a0[1], a1[1]).value = v1;
        assertEq(_ref(addressPairMapA, _brutalized(a0[0]), _brutalized(a1[0])).value, v0);
        assertEq(_ref(addressPairMapB, _brutalized(a0[1]), _brutalized(a1[1])).value, v1);
        /// @solidity memory-safe-assembly
        assembly {
            if gt(mload(0x40), 0xffffffff) { revert(0x00, 0x00) }
        }
    }

    function testRestrictNFTId(uint256 id) public {
        assertEq(_restrictNFTId(id), id > type(uint32).max ? 0 : id);
    }

    function _totalSupplyOverflows(uint256 amount, uint256 unit)
        internal
        pure
        returns (bool result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(or(shr(96, amount), lt(0xfffffffe, div(amount, unit)))))
        }
    }

    function testWrapNFTIdWithOverflowCheck(uint256 id, uint256 totalSupply, uint256 unit) public {
        if (unit == 0) unit = 1;
        id = _bound(id, 0, type(uint32).max);

        if (!_totalSupplyOverflows(totalSupply, unit)) {
            uint256 maxId = totalSupply / unit;
            id = _wrapNFTId(id + 1, maxId);
            assertTrue(id != 0 && id <= 0xffffffff);
        }
    }

    function _wrapNFTId(uint256 id, uint256 maxId) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(mul(iszero(gt(id, maxId)), id), gt(id, maxId))
        }
    }

    function _brutalized(address a) internal pure returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(0xf348aeebbad597df99cf9f4f0000000000000000000000000000000000000000, a)
        }
    }

    function testStorageSlotsNoCollision(uint256 slot0, uint256 slot1, uint256 i0, uint256 i1)
        public
    {
        while (true) {
            slot0 = _bound(slot0, 1, type(uint96).max);
            slot1 = _bound(slot1, 1, type(uint96).max);
            if (slot0 != slot1) break;
            slot0 = _random();
            slot1 = _random();
        }

        i0 = _getRandomIndex(i0);
        i1 = _getRandomIndex(i1);

        uint256 shift0 = _bound(_random(), 1, 10);
        uint256 shift1 = _bound(_random(), 1, 10);

        /// @solidity memory-safe-assembly
        assembly {
            let finalSlot0 := add(shl(96, slot0), shr(shift0, i0))
            let finalSlot1 := add(shl(96, slot1), shr(shift1, i1))
            if eq(finalSlot1, finalSlot0) { revert(0x00, 0x00) }
        }
    }

    function _getRandomIndex(uint256 i) internal returns (uint256) {
        unchecked {
            uint256 r = _random();
            if ((r & 0xf) == 0) {
                return type(uint256).max - _random() % 8;
            }
            if (((r >> 16) & 0xf) == 0) {
                uint256 modulus = 1 << (_random() % 32 + 1);
                return type(uint256).max - _random() % modulus;
            }
            if (((r >> 24) & 0xf) == 0) {
                return _bound(i, 0, type(uint32).max);
            }
            return _bound(i, 0, type(uint40).max);
        }
    }
}
