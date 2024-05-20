// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404Slim} from "./utils/mocks/MockDN404Slim.sol";
import {DN420, MockDN420Slim} from "./utils/mocks/MockDN420Slim.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract BenchTest is SoladyTest {
    MockDN404Slim dn404;
    MockDN420Slim dn420;
    DN404Mirror mirror;

    function setUp() public {
        dn420 = new MockDN420Slim();
        dn404 = new MockDN404Slim();
        mirror = new DN404Mirror(address(this));

        dn404.initializeDN404(10000 * 10 ** 18, address(this), address(mirror));
        dn420.initializeDN420(10000 * 10 ** 18, address(this));
    }

    modifier mint(address a, uint256 amount) {
        unchecked {
            address alice = address(111);
            IERC20(a).transfer(alice, amount * 10 ** 18);
        }
        _;
    }

    function testMintDN404_01() public mint(address(dn404), 1) {}
    function testMintDN420_01() public mint(address(dn420), 1) {}
    function testMintDN404_02() public mint(address(dn404), 2) {}
    function testMintDN420_02() public mint(address(dn420), 2) {}
    function testMintDN404_03() public mint(address(dn404), 3) {}
    function testMintDN420_03() public mint(address(dn420), 3) {}
    function testMintDN404_04() public mint(address(dn404), 4) {}
    function testMintDN420_04() public mint(address(dn420), 4) {}
    function testMintDN404_05() public mint(address(dn404), 5) {}
    function testMintDN420_05() public mint(address(dn420), 5) {}
    function testMintDN404_06() public mint(address(dn404), 6) {}
    function testMintDN420_06() public mint(address(dn420), 6) {}
    function testMintDN404_07() public mint(address(dn404), 7) {}
    function testMintDN420_07() public mint(address(dn420), 7) {}
    function testMintDN404_08() public mint(address(dn404), 8) {}
    function testMintDN420_08() public mint(address(dn420), 8) {}
    function testMintDN404_09() public mint(address(dn404), 9) {}
    function testMintDN420_09() public mint(address(dn420), 9) {}
    function testMintDN404_10() public mint(address(dn404), 10) {}
    function testMintDN420_10() public mint(address(dn420), 10) {}
    function testMintDN404_11() public mint(address(dn404), 11) {}
    function testMintDN420_11() public mint(address(dn420), 11) {}
    function testMintDN404_12() public mint(address(dn404), 12) {}
    function testMintDN420_12() public mint(address(dn420), 12) {}
    function testMintDN404_13() public mint(address(dn404), 13) {}
    function testMintDN420_13() public mint(address(dn420), 13) {}
    function testMintDN404_14() public mint(address(dn404), 14) {}
    function testMintDN420_14() public mint(address(dn420), 14) {}
    function testMintDN404_15() public mint(address(dn404), 15) {}
    function testMintDN420_15() public mint(address(dn420), 15) {}
    function testMintDN404_16() public mint(address(dn404), 16) {}
    function testMintDN420_16() public mint(address(dn420), 16) {}

    modifier mintAndTransfer(address a, uint256 amount) {
        unchecked {
            address alice = address(111);
            address bob = address(222);
            IERC20(a).transfer(alice, amount * 10 ** 18);
            vm.prank(alice);
            IERC20(a).transfer(bob, amount * 10 ** 18);
        }
        _;
    }

    function testMintAndTransferDN404_01() public mintAndTransfer(address(dn404), 1) {}
    function testMintAndTransferDN420_01() public mintAndTransfer(address(dn420), 1) {}
    function testMintAndTransferDN404_02() public mintAndTransfer(address(dn404), 2) {}
    function testMintAndTransferDN420_02() public mintAndTransfer(address(dn420), 2) {}
    function testMintAndTransferDN404_03() public mintAndTransfer(address(dn404), 3) {}
    function testMintAndTransferDN420_03() public mintAndTransfer(address(dn420), 3) {}
    function testMintAndTransferDN404_04() public mintAndTransfer(address(dn404), 4) {}
    function testMintAndTransferDN420_04() public mintAndTransfer(address(dn420), 4) {}
    function testMintAndTransferDN404_05() public mintAndTransfer(address(dn404), 5) {}
    function testMintAndTransferDN420_05() public mintAndTransfer(address(dn420), 5) {}
    function testMintAndTransferDN404_06() public mintAndTransfer(address(dn404), 6) {}
    function testMintAndTransferDN420_06() public mintAndTransfer(address(dn420), 6) {}
    function testMintAndTransferDN404_07() public mintAndTransfer(address(dn404), 7) {}
    function testMintAndTransferDN420_07() public mintAndTransfer(address(dn420), 7) {}
    function testMintAndTransferDN404_08() public mintAndTransfer(address(dn404), 8) {}
    function testMintAndTransferDN420_08() public mintAndTransfer(address(dn420), 8) {}
    function testMintAndTransferDN404_09() public mintAndTransfer(address(dn404), 9) {}
    function testMintAndTransferDN420_09() public mintAndTransfer(address(dn420), 9) {}
    function testMintAndTransferDN404_10() public mintAndTransfer(address(dn404), 10) {}
    function testMintAndTransferDN420_10() public mintAndTransfer(address(dn420), 10) {}
    function testMintAndTransferDN404_11() public mintAndTransfer(address(dn404), 11) {}
    function testMintAndTransferDN420_11() public mintAndTransfer(address(dn420), 11) {}
    function testMintAndTransferDN404_12() public mintAndTransfer(address(dn404), 12) {}
    function testMintAndTransferDN420_12() public mintAndTransfer(address(dn420), 12) {}
    function testMintAndTransferDN404_13() public mintAndTransfer(address(dn404), 13) {}
    function testMintAndTransferDN420_13() public mintAndTransfer(address(dn420), 13) {}
    function testMintAndTransferDN404_14() public mintAndTransfer(address(dn404), 14) {}
    function testMintAndTransferDN420_14() public mintAndTransfer(address(dn420), 14) {}
    function testMintAndTransferDN404_15() public mintAndTransfer(address(dn404), 15) {}
    function testMintAndTransferDN420_15() public mintAndTransfer(address(dn420), 15) {}
    function testMintAndTransferDN404_16() public mintAndTransfer(address(dn404), 16) {}
    function testMintAndTransferDN420_16() public mintAndTransfer(address(dn420), 16) {}
}
