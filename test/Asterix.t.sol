// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";
import {Asterix} from "../src/Asterix.sol";
import {AsterixMirror} from "../src/AsterixMirror.sol";

contract MockAsterix is Asterix {
    constructor() {
        _construct(msg.sender);
    }
}

contract MockAsterixMirror is DN404Mirror {
    constructor() DN404Mirror(msg.sender) {}
}

contract AsterixTest is SoladyTest {
    MockAsterix asterix;
    MockAsterixMirror asterixMirror;

    uint256 private constant _WAD = 10 ** 18;

    function setUp() public {
        asterix = new MockAsterix();
        asterixMirror = new MockAsterixMirror();
        asterix.initialize(address(asterixMirror));
    }

    function testWhitelist(address a, bool status) public {
        vm.assume(a != address(this));
        assertEq(asterix.isWhitelisted(a), false);
        asterix.setWhitelist(a, status);
        assertEq(asterix.isWhitelisted(a), status);
    }

    function testWhitelistOnWhitelisted() public {
        assertEq(asterix.isWhitelisted(address(this)), true);
        address alice = address(111);
        asterix.transfer(alice, 10 * _WAD);
    }

    function testWhitelistOnNonWhitelisted() public {
        asterix.setWhitelist(address(this), false);
        assertEq(asterix.isWhitelisted(address(this)), false);
        address alice = address(111);
        asterix.transfer(alice, 10 * _WAD);
    }

    function testWhitelistOnNonWhitelisted2() public {
        asterix.setWhitelist(address(this), false);
        assertEq(asterix.isWhitelisted(address(this)), false);
        address alice = address(111);
        asterix.transfer(alice, 5 * _WAD);
        asterix.transfer(alice, 5 * _WAD);
    }

    function testWhitelistOnNonWhitelisted3() public {
        asterix.setWhitelist(address(this), false);
        assertEq(asterix.isWhitelisted(address(this)), false);
        address alice = address(111);
        asterix.transfer(alice, 5 * _WAD);
        vm.warp(block.timestamp + 86400);
        asterix.transfer(alice, 5 * _WAD);
    }

    function testMaxBalanceLimit() public {
        address alice = address(111);
        assertEq(asterix.isWhitelisted(alice), false);

        uint256 maxBalanceLimit = asterix.maxBalanceLimit();

        vm.expectRevert(Asterix.MaxBalanceLimitReached.selector);
        asterix.transfer(alice, maxBalanceLimit * _WAD + 1);

        asterix.setWhitelist(alice, true);
        assertEq(asterix.isWhitelisted(alice), true);

        asterix.transfer(alice, maxBalanceLimit * _WAD + 1);
    }

    function testMaxBalanceLimit2() public {
        address alice = address(111);
        assertEq(asterix.isWhitelisted(alice), false);

        uint256 maxBalanceLimit = asterix.maxBalanceLimit();

        vm.expectRevert(Asterix.MaxBalanceLimitReached.selector);
        asterix.transfer(alice, maxBalanceLimit * _WAD + 1);

        asterix.setMaxBalanceLimit(0);

        asterix.transfer(alice, maxBalanceLimit * _WAD + 1);
    }

    function testOwnableRoles() public {
        address admin = address(888);
        asterix.grantRoles(admin, asterix.ADMIN_ROLE());
    }

    function testTokenURI() public {
        address alice = address(111);
        asterix.transfer(alice, 10 * _WAD);
        assertEq(asterixMirror.balanceOf(alice), 10);

        assertEq(asterix.tokenURI(1), "");

        asterix.setBaseURI("https://abcdefg.com/{id}.json");

        assertEq(asterixMirror.tokenURI(1), "https://abcdefg.com/1.json");
        assertEq(asterixMirror.tokenURI(10), "https://abcdefg.com/10.json");
    }
}
