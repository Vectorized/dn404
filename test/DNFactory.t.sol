// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {DNFactory} from "../src/DNFactory.sol";
import {DN404Cloneable} from "../src/example/DN404Cloneable.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";

contract DNFactoryTest is SoladyTest {
    DNFactory factory;
    address alice = address(111);
    address bob = address(42069);

    address[] addresses;
    uint256[] amounts;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 19227633);
        vm.prank(alice);
        factory = new DNFactory();
    }

    function testDeploy() public {
        for (uint256 i = 0; i < 10; i++) {
            addresses.push(address(uint160(10 + i)));
            amounts.push(uint256(keccak256(abi.encode(block.timestamp, i))) % type(uint64).max);
        }

        DNFactory.Allocations memory allocations =
            DNFactory.Allocations(100e18, 100e18, _sum(amounts));

        address dnAddress = factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation,
            60,
            addresses,
            amounts
        );

        DN404Cloneable dn = DN404Cloneable(payable(dnAddress));
        DN404Mirror dnMirror = DN404Mirror(payable(dn.mirrorERC721()));
        for (uint256 i = 0; i < addresses.length; i++) {
            assertEq(dn.balanceOf(addresses[i]), amounts[i]);
            assertEq(dnMirror.balanceOf(addresses[i]), amounts[i] / 10 ** 18);
        }
    }

    function testWithdrawLP() public {
        for (uint256 i = 0; i < 10; i++) {
            addresses.push(address(uint160(10 + i)));
            amounts.push(uint256(keccak256(abi.encode(block.timestamp, i))) % type(uint64).max);
        }

        DNFactory.Allocations memory allocations =
            DNFactory.Allocations(100e18, 100e18, _sum(amounts));

        address dnAddress = factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation,
            60,
            addresses,
            amounts
        );

        DN404Cloneable dn = DN404Cloneable(payable(dnAddress));

        uint256 currentTime = block.timestamp;
        vm.warp(currentTime + 60);

        vm.prank(dn.owner());
        dn.withdrawLP();
    }

    function testRevert_LiquidityLocked() public {
        for (uint256 i = 0; i < 10; i++) {
            addresses.push(address(uint160(10 + i)));
            amounts.push(uint256(keccak256(abi.encode(block.timestamp, i))) % type(uint64).max);
        }

        DNFactory.Allocations memory allocations =
            DNFactory.Allocations(100e18, 100e18, _sum(amounts));

        address dnAddress = factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation,
            60,
            addresses,
            amounts
        );

        DN404Cloneable dn = DN404Cloneable(payable(dnAddress));

        uint256 currentTime = block.timestamp;
        vm.warp(currentTime + 59);

        vm.prank(dn.owner());
        vm.expectRevert(DN404Cloneable.LiquidityLocked.selector);
        dn.withdrawLP();
    }

    function testRevert_InvalidAllocations() public {
        for (uint256 i = 0; i < 10; i++) {
            addresses.push(address(uint160(10 + i)));
            amounts.push(uint256(keccak256(abi.encode(block.timestamp, i))) % type(uint64).max);
        }

        DNFactory.Allocations memory allocations =
            DNFactory.Allocations(100e18, 100e18, _sum(amounts));

        // allocations too high
        vm.expectRevert(DNFactory.InvalidAllocations.selector);
        factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation + 1,
            60,
            addresses,
            amounts
        );

        // allocations too low
        vm.expectRevert(DNFactory.InvalidAllocations.selector);
        factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation - 1,
            60,
            addresses,
            amounts
        );
    }

    function testRevert_ArrayLengthMismatch() public {
        for (uint256 i = 0; i < 10; i++) {
            addresses.push(address(uint160(10 + i)));
            amounts.push(uint256(keccak256(abi.encode(block.timestamp, i))) % type(uint64).max);
        }

        addresses.push(address(42069));

        DNFactory.Allocations memory allocations =
            DNFactory.Allocations(100e18, 100e18, _sum(amounts));

        vm.expectRevert(DNFactory.ArrayLengthMismatch.selector);
        factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation,
            60,
            addresses,
            amounts
        );
    }

    function testRevert_InvalidAirdropConfig() public {
        // has a team allocation but addresses isn't populated
        DNFactory.Allocations memory allocations = DNFactory.Allocations(100e18, 100e18, 100e18);

        vm.expectRevert(DNFactory.InvalidAirdropConfig.selector);
        factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation,
            60,
            addresses,
            amounts
        );

        for (uint256 i = 0; i < 10; i++) {
            addresses.push(address(uint160(10 + i)));
            amounts.push(uint256(keccak256(abi.encode(block.timestamp, i))) % type(uint64).max);
        }

        // no team allocation but addresses is populated
        allocations = DNFactory.Allocations(100e18, 100e18 + _sum(amounts), 0);

        vm.expectRevert(DNFactory.InvalidAirdropConfig.selector);
        factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation,
            60,
            addresses,
            amounts
        );
    }

    function testRevert_InvalidLiquidityConfig() public {
        for (uint256 i = 0; i < 10; i++) {
            addresses.push(address(uint160(10 + i)));
            amounts.push(uint256(keccak256(abi.encode(block.timestamp, i))) % type(uint64).max);
        }

        DNFactory.Allocations memory allocations =
            DNFactory.Allocations(100e18, 100e18, _sum(amounts));

        // 0 value tx should revert because of liquidity allocation
        vm.expectRevert(DNFactory.InvalidLiquidityConfig.selector);
        factory.deployDN{value: 0 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation,
            60,
            addresses,
            amounts
        );

        allocations = DNFactory.Allocations(0, 200e18, _sum(amounts));

        // value tx should revert because of no liquidity allocation
        vm.expectRevert(DNFactory.InvalidLiquidityConfig.selector);
        factory.deployDN{value: 200 ether}(
            "DN404",
            "DN",
            allocations,
            allocations.airdropAllocation + allocations.liquidityAllocation
                + allocations.teamAllocation,
            60,
            addresses,
            amounts
        );
    }

    function _sum(uint256[] storage array) internal view returns (uint80 sum) {
        for (uint256 i = 0; i < array.length; i++) {
            sum += uint80(array[i]);
        }
    }
}
