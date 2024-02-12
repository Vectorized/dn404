// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library DailyOutflowCounterLib {
    uint256 internal constant WAD_TRUNCATED = 10 ** 18 >> 40;

    uint256 internal constant OUTFLOW_TRUNCATED_MASK = 0xffffffffffffff;

    uint256 internal constant DAY_BITPOS = 56;

    uint256 internal constant DAY_MASK = 0x7fffffff;

    uint256 internal constant OUTFLOW_TRUNCATE_SHR = 40;

    uint256 internal constant WHITELISTED_BITPOS = 87;

    function update(uint88 packed, uint256 outflow)
        internal
        view
        returns (uint88 updated, uint256 multiple)
    {
        unchecked {
            if (isWhitelisted(packed)) {
                return (packed, 0);
            }

            uint256 currentDay = (block.timestamp / 86400) & DAY_MASK;
            uint256 packedDay = (uint256(packed) >> DAY_BITPOS) & DAY_MASK;
            uint256 totalOutflowTruncated = uint256(packed) & OUTFLOW_TRUNCATED_MASK;

            if (packedDay != currentDay) {
                totalOutflowTruncated = 0;
                packedDay = currentDay;
            }

            uint256 result = packedDay << DAY_BITPOS;
            uint256 todaysOutflowTruncated =
                totalOutflowTruncated + ((outflow >> OUTFLOW_TRUNCATE_SHR) & OUTFLOW_TRUNCATED_MASK);
            result |= todaysOutflowTruncated & OUTFLOW_TRUNCATED_MASK;
            updated = uint88(result);
            multiple = todaysOutflowTruncated / WAD_TRUNCATED;
        }
    }

    function isWhitelisted(uint88 packed) internal pure returns (bool) {
        return packed >> WHITELISTED_BITPOS != 0;
    }

    function setWhitelisted(uint88 packed, bool status) internal pure returns (uint88) {
        if (isWhitelisted(packed) != status) {
            packed ^= uint88(1 << WHITELISTED_BITPOS);
        }
        return packed;
    }
}
