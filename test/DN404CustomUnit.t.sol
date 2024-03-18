// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {MockDN404CustomUnit} from "./utils/mocks/MockDN404CustomUnit.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";
import {DN404} from "../src/DN404.sol";

contract DN404CustomUnitTest is SoladyTest {
    MockDN404CustomUnit dn;
    DN404Mirror mirror;

    function setUp() public {
        dn = new MockDN404CustomUnit();
        mirror = new DN404Mirror(address(this));
    }

    function testInitializeWithZeroUnitReverts() public {
        dn.setUnit(0);
        vm.expectRevert(DN404.InvalidUnit.selector);
        dn.initializeDN404(1000, address(this), address(mirror));
    }

    function testInitializeCorrectUnitSuccess() public {
        dn.setUnit(2 ** 96 - 1);
        dn.initializeDN404(1000, address(this), address(mirror));
    }

    function testInitializeWithUnitTooLargeReverts() public {
        dn.setUnit(2 ** 96);
        vm.expectRevert(DN404.InvalidUnit.selector);
        dn.initializeDN404(1000, address(this), address(mirror));
    }

    function testUnitInvalidCheckTrick(uint256 unit) public {
        unchecked {
            bool expected = unit == 0 || unit > type(uint96).max;
            bool computed = unit - 1 >= 2 ** 96 - 1;
            assertEq(computed, expected);
            bool isValid = 0 < unit && unit < 2 ** 96;
            assertEq(computed, !isValid);
        }
    }

    function testMint() public {
        address alice = address(111);
        dn.setUnit(10 ** 25);
        dn.initializeDN404(1000, address(this), address(mirror));
        dn.mint(alice, 100);
        assertEq(dn.totalSupply(), 1100);
        assertEq(mirror.balanceOf(alice), 0);
    }

    function testNFTMint() public {
        address alice = address(111);
        uint256 unit = 404 * 10 ** 21;
        uint256 numNFTMints = 5000;
        dn.setUnit(unit);
        dn.initializeDN404(1000, address(this), address(mirror));
        dn.mint(alice, unit * numNFTMints);
        assertEq(dn.totalSupply(), unit * numNFTMints + 1000);
        assertEq(mirror.balanceOf(alice), numNFTMints);
    }

    function testNFTMintAndBurn(uint256 initial, uint256 unit, uint256 numNFTMints) public {
        address alice = address(111);
        numNFTMints = _bound(numNFTMints, 0, 10);
        initial = _bound(initial, 0, type(uint96).max - 1);
        unit = _bound(unit, initial + 1, type(uint96).max);

        dn.setUnit(unit);
        dn.initializeDN404(initial, address(this), address(mirror));

        if (initial + unit * numNFTMints > type(uint96).max) {
            vm.expectRevert(DN404.TotalSupplyOverflow.selector);
            dn.mint(alice, unit * numNFTMints);
        } else {
            uint256 expectedBalance = unit * numNFTMints;
            dn.mint(alice, expectedBalance);
            assertEq(dn.totalSupply(), expectedBalance + initial);
            assertEq(dn.balanceOf(address(this)), initial);
            assertEq(dn.balanceOf(alice), expectedBalance);
            assertEq(mirror.balanceOf(alice), numNFTMints);
            uint256 burnAmount = _bound(_random(), 0, dn.balanceOf(alice));
            dn.burn(alice, burnAmount);
            expectedBalance -= burnAmount;
            assertEq(dn.balanceOf(alice), expectedBalance);
            assertEq(mirror.balanceOf(alice), expectedBalance / unit);
        }
    }

    function testMintWithoutNFTs(uint256 initial, uint256 unit, uint256 numNFTMints) public {
        address alice = address(111);
        vm.prank(alice);
        dn.setSkipNFT(true);

        unit = _bound(unit, 1, type(uint96).max - 1);
        dn.setUnit(unit);

        initial = _bound(initial, 0, type(uint96).max - 1);
        if (initial / unit > type(uint32).max - 1) {
            vm.expectRevert(DN404.TotalSupplyOverflow.selector);
            dn.initializeDN404(initial, address(this), address(mirror));
        } else {
            dn.initializeDN404(initial, address(this), address(mirror));
            numNFTMints = _bound(numNFTMints, 0, type(uint32).max);
            uint256 expectedBalance = unit * numNFTMints;
            uint256 expectedTotalSupply = initial + expectedBalance;
            if (
                expectedTotalSupply / unit > type(uint32).max - 1
                    || expectedTotalSupply > type(uint96).max
            ) {
                vm.expectRevert(DN404.TotalSupplyOverflow.selector);
                dn.mint(alice, unit * numNFTMints);
            } else {
                dn.mint(alice, unit * numNFTMints);
                assertEq(dn.totalSupply(), expectedTotalSupply);
                assertEq(dn.balanceOf(alice), expectedBalance);
            }
        }
    }

    function testNFTMintViaTransfer(uint256 unit, uint256 numNFTMints, uint256 dust) public {
        address alice = address(111);
        unit = _bound(unit, 1, type(uint96).max);
        numNFTMints = _bound(numNFTMints, 0, 10);
        dust = _bound(dust, 0, unit - 1);
        dn.setUnit(unit);
        uint256 initial = unit * numNFTMints + dust;
        if (initial > type(uint96).max) {
            vm.expectRevert(DN404.TotalSupplyOverflow.selector);
            dn.initializeDN404(initial, address(this), address(mirror));
        } else {
            dn.initializeDN404(initial, address(this), address(mirror));
            dn.transfer(alice, initial);
            assertEq(mirror.balanceOf(alice), numNFTMints);
        }
    }

    function testTotalSupplyOverflowsTrick(uint256 totalSupply, uint256 amount, uint256 unit)
        public
    {
        if (unit == 0) unit = 1;

        totalSupply = _bound(totalSupply, 0, type(uint96).max);

        unchecked {
            uint256 sum = totalSupply + amount;
            bool t = _totalSupplyOverflows(sum, unit);
            bool expected = t || _totalSupplyOverflows(amount, unit);
            bool computed = t || sum < amount;
            assertEq(computed, expected);
        }
    }

    function testTotalSupplyOverflowsTrick(uint256 amount, uint256 unit) public {
        if (unit == 0) unit = 1;
        assertEq(_totalSupplyOverflows(amount, unit), _totalSupplyOverflowsOriginal(amount, unit));
    }

    function _totalSupplyOverflows(uint256 amount, uint256 unit)
        private
        pure
        returns (bool result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(or(shr(96, amount), lt(0xfffffffe, div(amount, unit)))))
        }
    }

    function _totalSupplyOverflowsOriginal(uint256 amount, uint256 unit)
        private
        pure
        returns (bool)
    {
        return (amount > type(uint96).max) || (amount / unit > type(uint32).max - 1);
    }
}
