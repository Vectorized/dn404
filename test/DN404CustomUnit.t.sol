// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {MockDN404CustomUnit} from "./utils/mocks/MockDN404CustomUnit.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";

contract DN404CustomUnitTest is SoladyTest {
    MockDN404CustomUnit dn;
    DN404Mirror mirror;

    function setUp() public {
        dn = new MockDN404CustomUnit();
        mirror = new DN404Mirror(address(this));
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

    function _totalSupplyOverflows(uint256 amount, uint256 unit) private pure returns (bool) {
        return (amount > type(uint96).max) || (amount / unit > type(uint32).max - 1);
    }
}
