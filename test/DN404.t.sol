// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/SoladyTest.sol";
import {DN404, MockDN404, DN404NonFungibleShadow} from "./utils/mocks/MockDN404.sol";

contract DN404Test is SoladyTest {
	MockDN404 dn;
	DN404NonFungibleShadow shadow;

	function setUp() public {
		dn = new MockDN404();
	}

    function testRegisterAndResolveAlias(address a0, address a1) public {
    	assertEq(dn.registerAndResolveAlias(a0), 1);
    	if (a1 == a0) {
    		assertEq(dn.registerAndResolveAlias(a1), 1);	
    	} else {
    		assertEq(dn.registerAndResolveAlias(a1), 2);
    		assertEq(dn.registerAndResolveAlias(a0), 1);
    	}
    }

    function testInitialize(uint32 totalNFTSupply, address initialSupplyOwner) public {
    	if (totalNFTSupply == 0 || uint256(totalNFTSupply) + 1 > type(uint32).max) {
			vm.expectRevert(DN404.InvalidTotalNFTSupply.selector);
			dn.initializeDN404(totalNFTSupply, initialSupplyOwner, address(0));
    	} else if (initialSupplyOwner == address(0)) {
    		vm.expectRevert(DN404.TransferToZeroAddress.selector);
    		dn.initializeDN404(totalNFTSupply, initialSupplyOwner, address(0));
    	} else {
    		dn.initializeDN404(totalNFTSupply, initialSupplyOwner, address(0));
    		assertEq(dn.totalSupply(), uint256(totalNFTSupply) * 10 ** 18);
    		assertEq(dn.balanceOf(initialSupplyOwner), uint256(totalNFTSupply) * 10 ** 18);
    	}
    }

    function testMintOnTransfer(uint32 totalNFTSupply, address initialSupplyOwner, address recipient) public {
        vm.assume(totalNFTSupply != 0 && uint256(totalNFTSupply) + 1 <= type(uint32).max && initialSupplyOwner != address(0));
		vm.assume(initialSupplyOwner != recipient && recipient != address(0));

		dn.initializeDN404(totalNFTSupply, initialSupplyOwner, address(0));

		vm.prank(initialSupplyOwner);
        dn.transfer(recipient, 1e18);

		shadow = DN404NonFungibleShadow(dn.sisterNftContract());

        assertEq(shadow.ownerOf(1), recipient);
    }

    function testBurnOnTransfer(uint32 totalNFTSupply, address initialSupplyOwner, address recipient) public {
        testMintOnTransfer(totalNFTSupply, initialSupplyOwner, recipient);

		vm.prank(recipient);
		dn.transfer(address(42069), totalNFTSupply + 1);

		shadow = DN404NonFungibleShadow(dn.sisterNftContract());

		vm.expectRevert(DN404NonFungibleShadow.TokenDoesNotExist.selector);
		shadow.ownerOf(1);
    }
}
