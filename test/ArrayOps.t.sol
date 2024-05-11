// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";

contract ArrayOpsTest is SoladyTest {
    using LibPRNG for *;

    /// @dev Returns an array of zero addresses.
    function _zeroAddresses(uint256 n) private pure returns (address[] memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(0x40, add(add(result, 0x20), shl(5, n)))
            mstore(result, n)
            codecopy(add(result, 0x20), codesize(), shl(5, n))
        }
    }

    /// @dev Returns an array each set to `value`.
    function _filled(uint256 n, uint256 value) private pure returns (uint256[] memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let o := add(result, 0x20)
            let end := add(o, shl(5, n))
            mstore(0x40, end)
            mstore(result, n)
            for {} iszero(eq(o, end)) { o := add(o, 0x20) } { mstore(o, value) }
        }
    }

    /// @dev Returns an array each set to `value`.
    function _filled(uint256 n, address value) private pure returns (address[] memory result) {
        result = _toAddresses(_filled(n, uint160(value)));
    }

    /// @dev Concatenates the arrays.
    function _concat(uint256[] memory a, uint256[] memory b)
        private
        view
        returns (uint256[] memory result)
    {
        uint256 aN = a.length;
        uint256 bN = b.length;
        if (aN == uint256(0)) return b;
        if (bN == uint256(0)) return a;
        /// @solidity memory-safe-assembly
        assembly {
            let n := add(aN, bN)
            if n {
                result := mload(0x40)
                mstore(result, n)
                let o := add(result, 0x20)
                mstore(0x40, add(o, shl(5, n)))
                let aL := shl(5, aN)
                pop(staticcall(gas(), 4, add(a, 0x20), aL, o, aL))
                pop(staticcall(gas(), 4, add(b, 0x20), shl(5, bN), add(o, aL), shl(5, bN)))
            }
        }
    }

    /// @dev Concatenates the arrays.
    function _concat(address[] memory a, address[] memory b)
        private
        view
        returns (address[] memory result)
    {
        result = _toAddresses(_concat(_toUints(a), _toUints(b)));
    }

    /// @dev Reinterpret cast to an uint array.
    function _toUints(address[] memory a) private pure returns (uint256[] memory casted) {
        /// @solidity memory-safe-assembly
        assembly {
            casted := a
        }
    }

    /// @dev Reinterpret cast to an address array.
    function _toAddresses(uint256[] memory a) private pure returns (address[] memory casted) {
        /// @solidity memory-safe-assembly
        assembly {
            casted := a
        }
    }

    function testZeroAddresses(uint256) public {
        uint256 n = _bound(_random(), 0, 32);
        unchecked {
            if (_random() % 16 == 0) _brutalizeMemory();
            address[] memory a = _zeroAddresses(n);
            if (_random() % 16 == 0) _brutalizeMemory();
            _checkMemory();
            for (uint256 i; i != n; ++i) {
                assertEq(a[i], address(0));
            }
            assertEq(a.length, n);
        }
    }

    function testFilled(uint256) public {
        uint256 n = _bound(_random(), 0, 32);
        unchecked {
            if (_random() % 16 == 0) _brutalizeMemory();
            uint256 value = _random();
            uint256[] memory a = _filled(n, value);
            if (_random() % 16 == 0) _brutalizeMemory();
            _checkMemory();
            for (uint256 i; i != n; ++i) {
                assertEq(a[i], value);
            }
            assertEq(a.length, n);
        }
        unchecked {
            if (_random() % 16 == 0) _brutalizeMemory();
            uint256 value = _random();
            address addressValue;
            /// @solidity memory-safe-assembly
            assembly {
                addressValue := value
            }
            address[] memory a = _filled(n, addressValue);
            if (_random() % 16 == 0) _brutalizeMemory();
            _checkMemory();
            for (uint256 i; i != n; ++i) {
                assertEq(a[i], addressValue);
            }
            assertEq(a.length, n);
        }
    }

    struct _TestConcatTemps {
        uint256[] a;
        uint256[] b;
        uint256[] c;
        uint256[] combined;
        uint256 n;
    }

    function testConcat(uint256 seed) public {
        _TestConcatTemps memory t;
        t.a = new uint256[](_bound(_random(), 0, 32));
        if (_random() % 16 == 0) _brutalizeMemory();
        t.b = new uint256[](_bound(_random(), 0, 32));
        if (_random() % 16 == 0) _brutalizeMemory();
        t.c = new uint256[](_bound(_random(), 0, 32));
        t.n = t.a.length + t.b.length + t.c.length;
        t.combined = new uint256[](t.n);
        if (_random() % 16 == 0) _brutalizeMemory();
        unchecked {
            LibPRNG.PRNG memory prng;
            prng.state = seed;
            for (uint256 i; i != t.n; ++i) {
                t.combined[i] = prng.next();
            }
        }
        if (_random() % 16 == 0) _brutalizeMemory();
        unchecked {
            LibPRNG.PRNG memory prng;
            prng.state = seed;
            for (uint256 i; i != t.a.length; ++i) {
                t.a[i] = prng.next();
            }
            for (uint256 i; i != t.b.length; ++i) {
                t.b[i] = prng.next();
            }
            for (uint256 i; i != t.c.length; ++i) {
                t.c[i] = prng.next();
            }
            if (_random() % 16 == 0) _brutalizeMemory();
            uint256[] memory concatenated = _concat(t.a, _concat(t.b, t.c));
            if (_random() % 16 == 0) _brutalizeMemory();
            _checkMemory();
            assertEq(concatenated, t.combined);
        }
    }
}
