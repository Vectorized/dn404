// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract MockBrutalizer {
    /// @dev Brutalizes the upper 96 bits of `a`.
    function _brutalized(address a) internal view returns (address result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, gas())
            result := or(shl(160, keccak256(0x00, 0x20)), a)
        }
    }

    /// @dev Fills the memory with junk, for more robust testing of inline assembly
    /// which reads/write to the memory.
    function _brutalizeMemory() internal view {
        // To prevent a solidity 0.8.13 bug.
        // See: https://blog.soliditylang.org/2022/06/15/inline-assembly-memory-side-effects-bug
        // Basically, we need to access a solidity variable from the assembly to
        // tell the compiler that this assembly block is not in isolation.
        uint256 zero;
        /// @solidity memory-safe-assembly
        assembly {
            let offset := mload(0x40) // Start the offset at the free memory pointer.
            calldatacopy(offset, zero, calldatasize())

            // Fill the 64 bytes of scratch space with garbage.
            mstore(zero, add(caller(), gas()))
            mstore(0x20, keccak256(offset, calldatasize()))
            mstore(zero, keccak256(zero, 0x40))

            let r0 := mload(zero)
            let r1 := mload(0x20)

            let cSize := add(codesize(), iszero(codesize()))
            if iszero(lt(cSize, 32)) { cSize := sub(cSize, and(mload(0x02), 0x1f)) }
            let start := mod(mload(0x10), cSize)
            let size := mul(sub(cSize, start), gt(cSize, start))
            let times := div(0x7ffff, cSize)
            if iszero(lt(times, 128)) { times := 128 }

            // Occasionally offset the offset by a pseudorandom large amount.
            // Can't be too large, or we will easily get out-of-gas errors.
            offset := add(offset, mul(iszero(and(r1, 0xf)), and(r0, 0xfffff)))

            // Fill the free memory with garbage.
            // prettier-ignore
            for { let w := not(0) } 1 {} {
                mstore(offset, r0)
                mstore(add(offset, 0x20), r1)
                offset := add(offset, 0x40)
                // We use codecopy instead of the identity precompile
                // to avoid polluting the `forge test -vvvv` output with tons of junk.
                codecopy(offset, start, size)
                codecopy(add(offset, size), 0, start)
                offset := add(offset, cSize)
                times := add(times, w) // `sub(times, 1)`.
                if iszero(times) { break }
            }
        }
    }

    /// @dev Check if the free memory pointer and the zero slot are not contaminated.
    /// Useful for cases where these slots are used for temporary storage.
    function _checkMemory() internal pure {
        bool zeroSlotIsNotZero;
        bool freeMemoryPointerOverflowed;
        /// @solidity memory-safe-assembly
        assembly {
            // Write ones to the free memory, to make subsequent checks fail if
            // insufficient memory is allocated.
            mstore(mload(0x40), not(0))
            // Test at a lower, but reasonable limit for more safety room.
            if gt(mload(0x40), 0xffffffff) { freeMemoryPointerOverflowed := 1 }
            // Check the value of the zero slot.
            zeroSlotIsNotZero := mload(0x60)
        }
        if (freeMemoryPointerOverflowed) revert("`0x40` overflowed!");
        if (zeroSlotIsNotZero) revert("`0x60` is not zero!");
    }

    /// @dev Check if `s`:
    /// - Has sufficient memory allocated.
    /// - Is zero right padded (cuz some frontends like Etherscan has issues
    ///   with decoding non-zero-right-padded strings).
    function _checkMemory(bytes memory s) internal pure {
        bool notZeroRightPadded;
        bool insufficientMalloc;
        /// @solidity memory-safe-assembly
        assembly {
            // Write ones to the free memory, to make subsequent checks fail if
            // insufficient memory is allocated.
            mstore(mload(0x40), not(0))
            let length := mload(s)
            let lastWord := mload(add(add(s, 0x20), and(length, not(0x1f))))
            let remainder := and(length, 0x1f)
            if remainder { if shl(mul(8, remainder), lastWord) { notZeroRightPadded := 1 } }
            // Check if the memory allocated is sufficient.
            if length { if gt(add(add(s, 0x20), length), mload(0x40)) { insufficientMalloc := 1 } }
        }
        if (notZeroRightPadded) revert("Not zero right padded!");
        if (insufficientMalloc) revert("Insufficient memory allocation!");
        _checkMemory();
    }
}
