// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";

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

    function _brutalized(address a) internal pure returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(0xf348aeebbad597df99cf9f4f0000000000000000000000000000000000000000, a)
        }
    }
}
