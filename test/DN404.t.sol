// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";

contract DN404Test is SoladyTest {
	MockDN404 dn;

	function setUp() public {
		dn = new MockDN404();

	}

    function testRegisterAndResolveAlias() public {

    }


}
