// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/SoladyTest.sol";
import {ERC20, MockERC20} from "lib/solady/test/utils/mocks/MockERC20.sol";
import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";
import {InvariantTest} from "./utils/InvariantTest.sol";

contract DN404Test is SoladyTest {
    uint256 private constant _WAD = 1000000000000000000;

    MockDN404 dn;
    DN404Mirror mirror;

    function setUp() public {
        dn = new MockDN404();
        mirror = new DN404Mirror(address(this));
    }

    function testNameAndSymbol(string memory name, string memory symbol) public {
        dn.initializeDN404(uint96(1000 * _WAD), address(this), address(mirror));
        dn.setNameAndSymbol(name, symbol);
        assertEq(mirror.name(), name);
        assertEq(mirror.symbol(), symbol);
    }

    function testTokenURI(string memory baseURI, uint256 id) public {
        dn.initializeDN404(uint96(1000 * _WAD), address(this), address(mirror));
        dn.setBaseURI(baseURI);
        assertEq(mirror.tokenURI(id), string(abi.encodePacked(baseURI, id)));
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
        if (totalNFTSupply > 0 && initialSupplyOwner == address(0)) {
            vm.expectRevert(DN404.TransferToZeroAddress.selector);
            dn.initializeDN404(uint96(totalNFTSupply * _WAD), initialSupplyOwner, address(mirror));
        } else if (uint256(totalNFTSupply) + 1 > type(uint32).max) {
            vm.expectRevert(DN404.InvalidTotalNFTSupply.selector);
            dn.initializeDN404(uint96(totalNFTSupply * _WAD), initialSupplyOwner, address(mirror));
        } else {
            dn.initializeDN404(uint96(totalNFTSupply * _WAD), initialSupplyOwner, address(mirror));
            assertEq(dn.totalSupply(), uint256(totalNFTSupply) * _WAD);
            assertEq(dn.balanceOf(initialSupplyOwner), uint256(totalNFTSupply) * _WAD);
            assertEq(mirror.totalSupply(), 0);
            assertEq(mirror.balanceOf(initialSupplyOwner), 0);
        }
    }

    function testWrapAround(uint32 totalNFTSupply, uint256 r) public {
        address alice = address(111);
        address bob = address(222);
        totalNFTSupply = uint32(_bound(totalNFTSupply, 1, 5));
        dn.initializeDN404(uint96(totalNFTSupply * _WAD), address(this), address(mirror));
        dn.transfer(alice, _WAD * uint256(totalNFTSupply));
        for (uint256 t; t != 1; ++t) {
            uint256 id = _bound(r, 1, totalNFTSupply);
            vm.prank(alice);
            mirror.transferFrom(alice, bob, id);
            vm.prank(bob);
            mirror.transferFrom(bob, alice, id);
            vm.prank(alice);
            dn.transfer(bob, _WAD);
            vm.prank(bob);
            dn.transfer(alice, _WAD);
        }
    }

    function testSetAndGetOperatorApprovals(address owner, address operator, bool approved)
        public
    {
        dn.initializeDN404(uint96(1000 * _WAD), address(this), address(mirror));
        assertEq(mirror.isApprovedForAll(owner, operator), false);
        vm.prank(owner);
        mirror.setApprovalForAll(operator, approved);
        assertEq(mirror.isApprovedForAll(owner, operator), approved);
    }

    function testMintOnTransfer(uint32 totalNFTSupply, address recipient) public {
        vm.assume(totalNFTSupply != 0 && uint256(totalNFTSupply) + 1 <= type(uint32).max);
        vm.assume(recipient.code.length == 0);
        vm.assume(recipient != address(0));

        dn.initializeDN404(uint96(totalNFTSupply * _WAD), address(this), address(mirror));

        assertEq(dn.totalSupply(), uint96(totalNFTSupply * _WAD));
        assertEq(mirror.totalSupply(), 0);

        vm.expectRevert(DN404.TokenDoesNotExist.selector);
        mirror.getApproved(1);

        dn.transfer(recipient, _WAD);

        assertEq(mirror.balanceOf(recipient), 1);
        assertEq(mirror.ownerOf(1), recipient);
        assertEq(mirror.totalSupply(), 1);

        assertEq(mirror.getApproved(1), address(0));
        vm.prank(recipient);
        mirror.approve(address(this), 1);
        assertEq(mirror.getApproved(1), address(this));
    }

    function testBurnOnTransfer(uint32 totalNFTSupply, address recipient) public {
        testMintOnTransfer(totalNFTSupply, recipient);

        vm.prank(recipient);
        dn.transfer(address(42069), totalNFTSupply + 1);

        mirror = DN404Mirror(payable(dn.mirrorERC721()));

        vm.expectRevert(DN404.TokenDoesNotExist.selector);
        mirror.ownerOf(1);
    }

    function testMintAndBurn() public {
        address initialSupplyOwner = address(1111);

        dn.initializeDN404(0, initialSupplyOwner, address(mirror));
        assertEq(dn.getSkipNFT(initialSupplyOwner), false);
        assertEq(dn.getSkipNFT(address(this)), true);

        vm.prank(initialSupplyOwner);
        dn.setSkipNFT(false);

        dn.mint(initialSupplyOwner, 4 * _WAD);
        assertEq(mirror.balanceOf(initialSupplyOwner), 4);

        dn.burn(initialSupplyOwner, 2 * _WAD);
        assertEq(mirror.balanceOf(initialSupplyOwner), 2);

        dn.mint(initialSupplyOwner, 3 * _WAD);
        assertEq(mirror.balanceOf(initialSupplyOwner), 5);

        for (uint256 i = 1; i <= 5; ++i) {
            assertEq(mirror.ownerOf(i), initialSupplyOwner);
        }

        uint256 count;
        for (uint256 i = 0; i < 10; ++i) {
            if (dn.ownerAt(i) == initialSupplyOwner) ++count;
        }
        assertEq(count, 5);

        dn.mint(initialSupplyOwner, 3 * _WAD);
        assertEq(mirror.balanceOf(initialSupplyOwner), 8);
    }

    function testMintAndBurn2() public {
        address initialSupplyOwner = address(1111);

        dn.initializeDN404(0, initialSupplyOwner, address(mirror));
        assertEq(dn.getSkipNFT(initialSupplyOwner), false);
        assertEq(dn.getSkipNFT(address(this)), true);

        vm.prank(initialSupplyOwner);
        dn.setSkipNFT(false);

        dn.mint(initialSupplyOwner, 1 * _WAD - 1);
        assertEq(mirror.balanceOf(initialSupplyOwner), 0);

        dn.burn(initialSupplyOwner, 1);
        assertEq(mirror.balanceOf(initialSupplyOwner), 0);

        dn.mint(initialSupplyOwner, 1 * _WAD + 2);
        assertEq(mirror.balanceOf(initialSupplyOwner), 2);

        dn.burn(initialSupplyOwner, 1);
        assertEq(mirror.balanceOf(initialSupplyOwner), 1);

        dn.mint(initialSupplyOwner, 1);
        assertEq(mirror.balanceOf(initialSupplyOwner), 2);

        for (uint256 i = 1; i <= 2; ++i) {
            assertEq(mirror.ownerOf(i), initialSupplyOwner);
        }

        uint256 count;
        for (uint256 i = 0; i < 10; ++i) {
            if (dn.ownerAt(i) == initialSupplyOwner) ++count;
        }
        assertEq(count, 2);
    }

    function testSetAndGetSkipNFT() public {
        assertEq(dn.getAddressDataInitialized(address(111)), false);
        vm.startPrank(address(111));
        dn.setSkipNFT(false);
        assertEq(dn.getSkipNFT(address(111)), false);
        assertEq(dn.getAddressDataInitialized(address(111)), true);
        dn.setSkipNFT(true);
        assertEq(dn.getSkipNFT(address(111)), true);
        assertEq(dn.getAddressDataInitialized(address(111)), true);
        dn.setSkipNFT(false);
        assertEq(dn.getSkipNFT(address(111)), false);
        assertEq(dn.getAddressDataInitialized(address(111)), true);
        vm.stopPrank();

        assertEq(dn.getAddressDataInitialized(address(this)), false);
        dn.setSkipNFT(false);
        assertEq(dn.getSkipNFT(address(this)), false);
        assertEq(dn.getAddressDataInitialized(address(this)), true);
        dn.setSkipNFT(true);
        assertEq(dn.getSkipNFT(address(this)), true);
        assertEq(dn.getAddressDataInitialized(address(this)), true);
        dn.setSkipNFT(false);
        assertEq(dn.getSkipNFT(address(this)), false);
        assertEq(dn.getAddressDataInitialized(address(this)), true);
    }

    function testSetAndGetAux(address a, uint88 aux) public {
        assertEq(dn.getAux(a), 0);
        dn.setAux(a, aux);
        assertEq(dn.getAux(a), aux);
        dn.setAux(a, 0);
        assertEq(dn.getAux(a), 0);
    }

    function testTransfersAndBurns() public {
        address initialSupplyOwner = address(1111);
        address alice = address(111);
        address bob = address(222);

        dn.initializeDN404(uint96(10 * _WAD), initialSupplyOwner, address(mirror));
        assertEq(dn.getSkipNFT(initialSupplyOwner), true);
        assertEq(dn.getSkipNFT(alice), false);
        assertEq(dn.getSkipNFT(bob), false);

        vm.prank(initialSupplyOwner);
        dn.transfer(alice, 5 * _WAD);

        vm.prank(initialSupplyOwner);
        dn.transfer(bob, 5 * _WAD);

        for (uint256 i = 1; i <= 5; ++i) {
            assertEq(dn.ownerAt(i), alice);
        }
        for (uint256 i = 6; i <= 10; ++i) {
            assertEq(dn.ownerAt(i), bob);
        }

        vm.prank(alice);
        dn.transfer(initialSupplyOwner, 5 * _WAD);

        for (uint256 i = 1; i <= 5; ++i) {
            assertEq(dn.ownerAt(i), address(0));
        }
        for (uint256 i = 6; i <= 10; ++i) {
            assertEq(dn.ownerAt(i), bob);
        }

        vm.prank(initialSupplyOwner);
        dn.transfer(alice, 1 * _WAD);
        assertEq(dn.ownerAt(1), alice);
    }

    // for viewing gas
    function testBatchNFTLog() external {
        uint32 totalNFTSupply = 10;
        address initialSupplyOwner = address(1111);
        dn.initializeDN404(
            uint96(uint256(totalNFTSupply) * _WAD), initialSupplyOwner, address(mirror)
        );

        vm.startPrank(initialSupplyOwner);
        dn.transfer(address(2222), 10e18);

        vm.startPrank(address(2222));
        dn.transfer(address(1111), 10e18);
    }

    // ERC20 base tests
    MockERC20 token;

    bytes32 constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    struct _TestTemps {
        address owner;
        address to;
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 privateKey;
        uint256 nonce;
    }

    function _testTemps() internal returns (_TestTemps memory t) {
        (t.owner, t.privateKey) = _randomSigner();
        t.to = _randomNonZeroAddress();
        t.amount = _random();
        t.deadline = _random();
    }

    function testMint() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(0xBEEF), 1e18);
        dn.initializeDN404(1e18, address(0xBEEF), address(mirror));

        assertEq(dn.totalSupply(), 1e18);
        assertEq(dn.balanceOf(address(0xBEEF)), 1e18);
    }

    function testBurn() public {
        dn.initializeDN404(uint96(1e18), address(0xBEEF), address(mirror));

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0xBEEF), address(0), 0.9e18);
        dn.burn(address(0xBEEF), 0.9e18);

        assertEq(dn.totalSupply(), 1e18 - 0.9e18);
        assertEq(dn.balanceOf(address(0xBEEF)), 0.1e18);
    }

    function testApprove() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(address(this), address(0xBEEF), 1e18);
        assertTrue(dn.approve(address(0xBEEF), 1e18));

        assertEq(dn.allowance(address(this), address(0xBEEF)), 1e18);
    }

    function testTransfer() public {
        dn.initializeDN404(uint96(1e18), address(this), address(mirror));

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), address(0xBEEF), 1e18);
        assertTrue(dn.transfer(address(0xBEEF), 1e18));
        assertEq(dn.totalSupply(), 1e18);

        assertEq(dn.balanceOf(address(this)), 0);
        assertEq(dn.balanceOf(address(0xBEEF)), 1e18);
    }

    function testTransferFrom() public {
        address from = address(0xABCD);

        dn.initializeDN404(uint96(1e18), from, address(mirror));

        vm.prank(from);
        dn.approve(address(this), 1e18);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, address(0xBEEF), 1e18);
        assertTrue(dn.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(dn.totalSupply(), 1e18);

        assertEq(dn.allowance(from, address(this)), 0);

        assertEq(dn.balanceOf(from), 0);
        assertEq(dn.balanceOf(address(0xBEEF)), 1e18);
    }

    function testInfiniteApproveTransferFrom() public {
        address from = address(0xABCD);

        dn.initializeDN404(uint96(1e18), from, address(mirror));

        vm.prank(from);
        dn.approve(address(this), type(uint256).max);

        assertTrue(dn.transferFrom(from, address(0xBEEF), 1e18));
        assertEq(dn.totalSupply(), 1e18);

        assertEq(dn.allowance(from, address(this)), type(uint256).max);

        assertEq(dn.balanceOf(from), 0);
        assertEq(dn.balanceOf(address(0xBEEF)), 1e18);
    }

    function testMintOverMaxUintReverts() public {
        dn.initializeDN404(uint96(0xffffffff * _WAD - 1), address(this), address(mirror));
        vm.expectRevert(DN404.InvalidTotalNFTSupply.selector);
        dn.mint(address(this), 1 * _WAD);
    }

    function testTransferInsufficientBalanceReverts() public {
        dn.mint(address(this), 0.9e18);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        dn.transfer(address(0xBEEF), 1e18);
    }

    function testTransferFromInsufficientAllowanceReverts() public {
        address from = address(0xABCD);

        dn.initializeDN404(uint96(1e18), from, address(mirror));

        vm.prank(from);
        dn.approve(address(this), 0.9e18);

        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        dn.transferFrom(from, address(0xBEEF), 1e18);
    }

    function testTransferFromInsufficientBalanceReverts() public {
        address from = address(0xABCD);

        dn.initializeDN404(uint96(.9e18), from, address(mirror));

        vm.prank(from);
        dn.approve(address(this), 1e18);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        dn.transferFrom(from, address(0xBEEF), 1e18);
    }

    function testMint(address to, uint256 amount) public {
        vm.assume(amount < 0xffffffff * _WAD);
        vm.assume(to != address(0));

        if (amount > 0) {
            vm.expectEmit(true, true, true, true);
            emit Transfer(address(0), to, amount);
            dn.initializeDN404(uint96(amount), to, address(mirror));
        }

        assertEq(dn.totalSupply(), amount);
        assertEq(dn.balanceOf(to), amount);
    }

    function testBurn(address from, uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount < 0xffffffff);
        vm.assume(from != address(0));
        dn.initializeDN404(uint96(mintAmount), from, address(mirror));
        burnAmount = _bound(burnAmount, 0, mintAmount);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, address(0), burnAmount);
        dn.burn(from, burnAmount);

        assertEq(dn.totalSupply(), mintAmount - burnAmount);
        assertEq(dn.balanceOf(from), mintAmount - burnAmount);
    }

    function testApprove(address to, uint256 amount) public {
        assertTrue(dn.approve(to, amount));

        assertEq(dn.allowance(address(this), to), amount);
    }

    function testTransferWorks(address to, uint256 amount) public {
        vm.assume(amount < 8313000000000000000000);
        vm.assume(to != address(0));

        dn.initializeDN404(uint96(amount), address(this), address(mirror));

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), to, amount);
        assertTrue(dn.transfer(to, amount));
        assertEq(dn.totalSupply(), amount);

        if (address(this) == to) {
            assertEq(dn.balanceOf(address(this)), amount);
        } else {
            assertEq(dn.balanceOf(address(this)), 0);
            assertEq(dn.balanceOf(to), amount);
        }
    }

    function testTransferBroken(address to, uint256 amount) public {
        vm.assume(amount >= 8313000000000000000000);
        vm.assume(to != address(0));

        dn.initializeDN404(uint96(amount), address(this), address(mirror));

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), to, amount);
        assertTrue(dn.transfer(to, amount));
        assertEq(dn.totalSupply(), amount);

        if (address(this) == to) {
            assertEq(dn.balanceOf(address(this)), amount);
        } else {
            assertEq(dn.balanceOf(address(this)), 0);
            assertEq(dn.balanceOf(to), amount);
        }
    }

    function testTransferFrom(
        address spender,
        address from,
        address to,
        uint256 approval,
        uint256 amount
    ) public {
        vm.assume(amount < 0xffffffff * _WAD);
        vm.assume(from != address(0) && to != address(0));
        amount = _bound(amount, 0, approval);

        dn.initializeDN404(uint96(amount), from, address(mirror));
        assertEq(dn.balanceOf(from), amount);

        vm.prank(from);
        dn.approve(spender, approval);

        vm.expectEmit(true, true, true, true);
        emit Transfer(from, to, amount);
        vm.prank(spender);
        assertTrue(dn.transferFrom(from, to, amount));
        assertEq(dn.totalSupply(), amount);

        if (approval == type(uint256).max) {
            assertEq(dn.allowance(from, spender), approval);
        } else {
            assertEq(dn.allowance(from, spender), approval - amount);
        }

        if (from == to) {
            assertEq(dn.balanceOf(from), amount);
        } else {
            assertEq(dn.balanceOf(from), 0);
            assertEq(dn.balanceOf(to), amount);
        }
    }

    function _checkAllowanceAndNonce(_TestTemps memory t) internal {
        assertEq(dn.allowance(t.owner, t.to), t.amount);
    }

    function testBurnInsufficientBalanceReverts(address to, uint256 mintAmount, uint256 burnAmount)
        public
    {
        vm.assume(to != address(0));
        vm.assume(mintAmount < 0xffffffff);
        if (mintAmount == type(uint256).max) mintAmount--;
        burnAmount = _bound(burnAmount, mintAmount + 1, type(uint256).max);

        dn.initializeDN404(uint96(mintAmount), to, address(mirror));
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        dn.burn(to, burnAmount);
    }

    function testTransferInsufficientBalanceReverts(
        address to,
        uint256 mintAmount,
        uint256 sendAmount
    ) public {
        if (mintAmount == type(uint256).max) mintAmount--;
        sendAmount = _bound(sendAmount, mintAmount + 1, type(uint256).max);

        dn.initializeDN404(uint96(mintAmount), address(this), address(mirror));
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        dn.transfer(to, sendAmount);
    }

    function testTransferFromInsufficientAllowanceReverts(
        address to,
        uint256 approval,
        uint256 amount
    ) public {
        if (approval == type(uint256).max) approval--;
        amount = _bound(amount, approval + 1, type(uint256).max);

        address from = address(0xABCD);

        dn.initializeDN404(uint96(amount), from, address(mirror));

        vm.prank(from);
        dn.approve(address(this), approval);

        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        dn.transferFrom(from, to, amount);
    }

    function testTransferFromInsufficientBalanceReverts(
        address to,
        uint256 mintAmount,
        uint256 sendAmount
    ) public {
        if (mintAmount == type(uint256).max) mintAmount--;
        sendAmount = _bound(sendAmount, mintAmount + 1, type(uint256).max);

        address from = address(0xABCD);

        dn.initializeDN404(uint96(mintAmount), from, address(mirror));

        vm.prank(from);
        dn.approve(address(this), sendAmount);

        vm.expectRevert(ERC20.InsufficientBalance.selector);
        dn.transferFrom(from, to, sendAmount);
    }
}

contract ERC20Invariants is SoladyTest, InvariantTest {
    BalanceSum balanceSum;
    MockERC20 token;

    function setUp() public {
        token = new MockERC20("Token", "TKN", 18);
        balanceSum = new BalanceSum(token);
        _addTargetContract(address(balanceSum));
    }

    function invariantBalanceSum() public {
        assertEq(token.totalSupply(), balanceSum.sum());
    }
}

contract BalanceSum {
    MockERC20 token;
    uint256 public sum;

    constructor(MockERC20 _token) {
        token = _token;
    }

    function mint(address from, uint256 amount) public {
        token.mint(from, amount);
        sum += amount;
    }

    function burn(address from, uint256 amount) public {
        token.burn(from, amount);
        sum -= amount;
    }

    function approve(address to, uint256 amount) public {
        token.approve(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public {
        token.transferFrom(from, to, amount);
    }

    function transfer(address to, uint256 amount) public {
        token.transfer(to, amount);
    }
}
