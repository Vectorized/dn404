// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {LibClone} from "solady/utils/LibClone.sol";
import {DN404Cloneable} from "./example/DN404Cloneable.sol";

contract DNFactory {
    error FailedToInitialize();
    error ArrayLengthMismatch();
    error InvalidLiquidityConfig();
    error InvalidAllocations();
    error EtherProvidedForZeroLiquidity();
    error InvalidAirdropConfig();

    address public immutable implementation;

    struct Allocations {
        uint80 liquidityAllocation;
        uint80 teamAllocation;
        uint80 airdropAllocation;
    }

    constructor() {
        DN404Cloneable dn = new DN404Cloneable();
        implementation = address(dn);
    }

    function deployDN(
        string calldata name,
        string calldata sym,
        Allocations calldata allocations,
        uint96 totalSupply,
        uint256 liquidityLockPeriodInSeconds,
        address[] calldata addresses,
        uint256[] calldata amounts
    ) external payable returns (address tokenAddress) {
        if (
            allocations.liquidityAllocation + allocations.teamAllocation
                + allocations.airdropAllocation != totalSupply
        ) {
            revert InvalidAllocations();
        }
        if (addresses.length != amounts.length) revert ArrayLengthMismatch();
        if (
            (addresses.length == 0 && allocations.airdropAllocation > 0)
                || (addresses.length != 0 && allocations.airdropAllocation == 0)
        ) revert InvalidAirdropConfig();
        if (
            (allocations.liquidityAllocation != 0 && msg.value == 0)
                || (allocations.liquidityAllocation == 0 && msg.value > 0)
        ) {
            revert InvalidLiquidityConfig();
        }

        tokenAddress =
            LibClone.cloneDeterministic(implementation, keccak256(abi.encodePacked(name)));
        (bool success,) = tokenAddress.call{value: msg.value}(
            abi.encodeWithSelector(
                DN404Cloneable.initialize.selector,
                name,
                sym,
                allocations,
                totalSupply,
                liquidityLockPeriodInSeconds,
                addresses,
                amounts
            )
        );

        if (!success) revert FailedToInitialize();
    }
}
