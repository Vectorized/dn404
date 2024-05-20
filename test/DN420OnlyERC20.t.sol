// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";

import {DN420, MockDN420OnlyERC20} from "./utils/mocks/MockDN420OnlyERC20.sol";

contract DN420OnlyERC20Test is SoladyTest {
    MockDN420OnlyERC20 token;

    uint256 private constant _WAD = 10 ** 18;

    uint256 private constant _MAX_TOKEN_ID = 0xffffffff;

    uint256 private constant _MAX_SUPPLY = 10 ** 18 * 0xffffffff - 1;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        token = new MockDN420OnlyERC20();
    }

    function testMaxSupplyTrick(uint256 amount) public {
        bool expected = amount / _WAD > _MAX_TOKEN_ID - 1;
        bool computed = amount > _MAX_SUPPLY;
        assertEq(computed, expected);
    }

    function testMetadata() public {
        assertEq(token.name(), "name");
        assertEq(token.symbol(), "SYMBOL");
        assertEq(token.decimals(), 18);
    }

    function testMint() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(0xBEEF), 1e18);
        token.mint(address(0xBEEF), 1e18);

        assertEq(token.totalSupply(), 1e18);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testBurn() public {
        token.mint(address(0xBEEF), 1e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0xBEEF), address(0), 0.9e18);
        token.burn(address(0xBEEF), 0.9e18);

        assertEq(token.totalSupply(), 1e18 - 0.9e18);
        assertEq(token.balanceOf(address(0xBEEF)), 0.1e18);
    }

    function testApprove() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(address(this), address(0xBEEF), 1e18);
        assertTrue(token.approve(address(0xBEEF), 1e18));

        assertEq(token.allowance(address(this), address(0xBEEF)), 1e18);
    }

    function testTransfer() public {
        token.mint(address(this), 1e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), address(0xBEEF), 1e18);
        assertTrue(token.transfer(address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        vm.prank(from);
        token.approve(address(this), 1e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, address(0xBEEF), 1e18);
        assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.allowance(from, address(this)), 0);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testInfiniteApproveTransferFrom() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        vm.prank(from);
        token.approve(address(this), type(uint256).max);

        assertTrue(token.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(token.totalSupply(), 1e18);

        assertEq(token.allowance(from, address(this)), type(uint256).max);

        assertEq(token.balanceOf(from), 0);
        assertEq(token.balanceOf(address(0xBEEF)), 1e18);
    }

    function testMintOverMaxLimitReverts() public {
        token.mint(address(this), _MAX_SUPPLY);
        vm.expectRevert(DN420.TotalSupplyOverflow.selector);
        token.mint(address(this), 1);
    }

    function testTransferInsufficientBalanceReverts() public {
        token.mint(address(this), 0.9e18);
        vm.expectRevert(DN420.InsufficientBalance.selector);
        token.transfer(address(0xBEEF), 1e18);
    }

    function testTransferFromInsufficientAllowanceReverts() public {
        address from = address(0xABCD);

        token.mint(from, 1e18);

        vm.prank(from);
        token.approve(address(this), 0.9e18);

        vm.expectRevert(DN420.InsufficientAllowance.selector);
        token.transferFrom(from, address(0xBEEF), 1e18);
    }

    function testTransferFromInsufficientBalanceReverts() public {
        address from = address(0xABCD);

        token.mint(from, 0.9e18);

        vm.prank(from);
        token.approve(address(this), 1e18);

        vm.expectRevert(DN420.InsufficientBalance.selector);
        token.transferFrom(from, address(0xBEEF), 1e18);
    }

    function testMintz(address to, uint256 amount) public {
        if (to == address(0)) to = _randomNonZeroAddress();

        amount = _bound(amount, 0, _MAX_SUPPLY);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), to, amount);
        token.mint(to, amount);

        assertEq(token.totalSupply(), amount);
        assertEq(token.balanceOf(to), amount);
    }

    function testBurn(address from, uint256 mintAmount, uint256 burnAmount) public {
        if (from == address(0)) from = _randomNonZeroAddress();

        burnAmount = _bound(burnAmount, 0, _MAX_SUPPLY);
        mintAmount = _bound(mintAmount, 0, _MAX_SUPPLY);
        burnAmount = _bound(burnAmount, 0, mintAmount);

        token.mint(from, mintAmount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(from, address(0), burnAmount);
        token.burn(from, burnAmount);

        assertEq(token.totalSupply(), mintAmount - burnAmount);
        assertEq(token.balanceOf(from), mintAmount - burnAmount);
    }

    function testApprove(address to, uint256 amount) public {
        assertTrue(token.approve(to, amount));

        assertEq(token.allowance(address(this), to), amount);
    }

    function testTransfer(address to, uint256 amount) public {
        if (to == address(0)) to = _randomNonZeroAddress();

        amount = _bound(amount, 0, _MAX_SUPPLY);
        token.mint(address(this), amount);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), to, amount);
        assertTrue(token.transfer(to, amount));
        assertEq(token.totalSupply(), amount);

        if (address(this) == to) {
            assertEq(token.balanceOf(address(this)), amount);
        } else {
            assertEq(token.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(to), amount);
        }
    }

    function testTransferFrom(
        address spender,
        address from,
        address to,
        uint256 approval,
        uint256 amount
    ) public {
        if (to == address(0)) to = _randomNonZeroAddress();
        if (from == address(0)) from = _randomNonZeroAddress();
        if (spender == address(0)) spender = _randomNonZeroAddress();

        approval = _bound(approval, 0, _MAX_SUPPLY);
        amount = _bound(amount, 0, _MAX_SUPPLY);

        amount = _bound(amount, 0, approval);

        token.mint(from, amount);
        assertEq(token.balanceOf(from), amount);

        vm.prank(from);
        token.approve(spender, approval);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.totalSupply(), amount);

        if (approval == type(uint256).max) {
            assertEq(token.allowance(from, spender), approval);
        } else {
            assertEq(token.allowance(from, spender), approval - amount);
        }

        if (from == to) {
            assertEq(token.balanceOf(from), amount);
        } else {
            assertEq(token.balanceOf(from), 0);
            assertEq(token.balanceOf(to), amount);
        }
    }

    function testBurnInsufficientBalanceReverts(address to, uint256 mintAmount, uint256 burnAmount)
        public
    {
        if (to == address(0)) to = _randomNonZeroAddress();

        mintAmount = _bound(mintAmount, 0, _MAX_SUPPLY);

        if (mintAmount == _MAX_SUPPLY) mintAmount--;
        burnAmount = _bound(burnAmount, mintAmount + 1, _MAX_SUPPLY);

        token.mint(to, mintAmount);
        vm.expectRevert(DN420.InsufficientBalance.selector);
        token.burn(to, burnAmount);
    }

    function testTransferInsufficientBalanceReverts(
        address to,
        uint256 mintAmount,
        uint256 sendAmount
    ) public {
        if (to == address(0)) to = _randomNonZeroAddress();

        mintAmount = _bound(mintAmount, 0, _MAX_SUPPLY);
        sendAmount = _bound(sendAmount, 0, _MAX_SUPPLY);

        if (mintAmount == _MAX_SUPPLY) mintAmount--;
        sendAmount = _bound(sendAmount, mintAmount + 1, _MAX_SUPPLY);

        token.mint(address(this), mintAmount);
        vm.expectRevert(DN420.InsufficientBalance.selector);
        token.transfer(to, sendAmount);
    }

    function testTransferFromInsufficientAllowanceReverts(
        address to,
        uint256 approval,
        uint256 amount
    ) public {
        if (to == address(0)) to = _randomNonZeroAddress();

        approval = _bound(approval, 0, _MAX_SUPPLY);
        amount = _bound(amount, 0, _MAX_SUPPLY);

        if (approval == _MAX_SUPPLY) approval--;
        amount = _bound(amount, approval + 1, _MAX_SUPPLY);

        address from = address(0xABCD);

        token.mint(from, amount);

        vm.prank(from);
        token.approve(address(this), approval);

        vm.expectRevert(DN420.InsufficientAllowance.selector);
        token.transferFrom(from, to, amount);
    }

    function testTransferFromInsufficientBalanceReverts(
        address to,
        uint256 mintAmount,
        uint256 sendAmount
    ) public {
        if (to == address(0)) to = _randomNonZeroAddress();
        mintAmount = _bound(mintAmount, 0, _MAX_SUPPLY);
        sendAmount = _bound(sendAmount, 0, _MAX_SUPPLY);

        if (mintAmount == _MAX_SUPPLY) mintAmount--;
        sendAmount = _bound(sendAmount, mintAmount + 1, _MAX_SUPPLY);

        address from = address(0xABCD);

        token.mint(from, mintAmount);

        vm.prank(from);
        token.approve(address(this), sendAmount);

        vm.expectRevert(DN420.InsufficientBalance.selector);
        token.transferFrom(from, to, sendAmount);
    }
}
