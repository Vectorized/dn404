// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {SoladyTest} from "../../utils/SoladyTest.sol";
import {DN404, MockDN404} from "../../utils/mocks/MockDN404.sol";
import {DN404Mirror} from "../../../src/DN404Mirror.sol";

contract MintTests is SoladyTest {
    error TransferToZeroAddress();
    error TotalSupplyOverflow();

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    uint256 private constant _WAD = 1000000000000000000;
    uint256 private constant _MAX_SUPPLY = 10 ** 18 * 0xffffffff - 1;
    uint256 private constant START_SLOT =
        0x0000000000000000000000000000000000000000000000a20d6e21d0e5255308;

    MockDN404 dn;
    DN404Mirror mirror;

    function setUp() public {
        dn = new MockDN404();
        mirror = new DN404Mirror(address(this));
        dn.initializeDN404(0, address(0), address(mirror));
    }

    function test_WhenRecipientIsAddress0(uint256) external {
        // it should revert with custom error TransferToZeroAddress()
        vm.expectRevert(TransferToZeroAddress.selector);
        dn.mint(address(0), _random());
    }

    modifier whenRecipientIsNotAddress0() {
        _;
    }

    function test_WhenAmountIsGreaterThan_MAX_SUPPLYOrMintMakesNFTTotalSupplyExceed_MAX_SUPPLY(
        uint256
    ) external whenRecipientIsNotAddress0 {
        // setup
        address to = address(uint160(_random()));
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(_random())))));
        uint256 amount = _bound(_random(), _MAX_SUPPLY + 1, type(uint256).max);

        // it should revert with custom error TotalSupplyOverflow()
        vm.expectRevert(TotalSupplyOverflow.selector);
        dn.mint(to, amount);
    }

    modifier whenAmountIsNOTGreaterThan_MAX_SUPPLYAndMintDOESNOTMakeNFTTotalSupplyExceed_MAX_SUPPLY(
    ) {
        _;
    }

    function test_WhenRecipientAddressHasSkipNFTEnabled(uint256)
        external
        whenRecipientIsNotAddress0
        whenAmountIsNOTGreaterThan_MAX_SUPPLYAndMintDOESNOTMakeNFTTotalSupplyExceed_MAX_SUPPLY
    {
        // setup
        address to = address(uint160(_random()));
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(_random())))));
        uint256 amount = _bound(_random(), 0, _MAX_SUPPLY);
        vm.prank(to);
        dn.setSkipNFT(true);

        uint256 initialTokenTotalSupply = dn.totalSupply();
        uint256 initialRecipientTokenBalance = dn.balanceOf(to);
        uint256 initialNFTTotalSupply = mirror.totalSupply();
        uint256 initialRecipientNFTBalance = mirror.balanceOf(to);

        // it should emit ERC20 transfer event
        // vm.expectEmit(true, true, false, true, address(dn));
        // emitERC20TransferEvent(address(0), to, amount);

        dn.mint(to, amount);

        // it should increment token totalSupply by amount
        assertEq(dn.totalSupply(), initialTokenTotalSupply + amount);
        // it should increment recipient address balance by amount
        assertEq(dn.balanceOf(to), initialRecipientTokenBalance + amount);
        // it should NOT increment NFT totalSupply
        assertEq(mirror.totalSupply(), initialNFTTotalSupply);
        // it should NOT increment recipient NFT balance
        assertEq(mirror.balanceOf(to), initialRecipientNFTBalance);
    }

    modifier whenRecipientAddressHasSkipNFTDisabled() {
        _;
    }

    function test_WhenRecipientsBalanceDifferenceIsNotUpTo1e18(uint256)
        external
        whenRecipientIsNotAddress0
        whenAmountIsNOTGreaterThan_MAX_SUPPLYAndMintDOESNOTMakeNFTTotalSupplyExceed_MAX_SUPPLY
        whenRecipientAddressHasSkipNFTDisabled
    {
        // setup
        address to = address(uint160(_random()));
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(_random())))));
        uint256 amount = _bound(_random(), 0, 1e18 - 1);

        uint256 initialTokenTotalSupply = dn.totalSupply();
        uint256 initialRecipientTokenBalance = dn.balanceOf(to);
        uint256 initialNFTTotalSupply = mirror.totalSupply();
        uint256 initialRecipientNFTBalance = mirror.balanceOf(to);

        // it should emit ERC20 transfer event
        // vm.expectEmit(true, true, false, true, address(dn));
        // emitERC20TransferEvent(address(0), to, amount);

        dn.mint(to, amount);

        // it should increment token totalSupply by amount
        assertEq(dn.totalSupply(), initialTokenTotalSupply + amount);
        // it should increment recipient address balance by amount
        assertEq(dn.balanceOf(to), initialRecipientTokenBalance + amount);
        // it should NOT increment NFT totalSupply
        assertEq(mirror.totalSupply(), initialNFTTotalSupply);
        // it should NOT increment recipient NFT balance
        assertEq(mirror.balanceOf(to), initialRecipientNFTBalance);
    }

    function test_WhenRecipientsBalanceDifferenceIsUpTo1e18OrAbove(uint256)
        external
        whenRecipientIsNotAddress0
        whenAmountIsNOTGreaterThan_MAX_SUPPLYAndMintDOESNOTMakeNFTTotalSupplyExceed_MAX_SUPPLY
        whenRecipientAddressHasSkipNFTDisabled
    {
        // setup
        address to = address(uint160(_random()));
        if (to == address(0)) to = address(uint160(uint256(keccak256(abi.encode(_random())))));
        uint256 amount = _bound(_random(), 0, 1000);

        uint256 initialTokenTotalSupply = dn.totalSupply();
        uint256 initialRecipientTokenBalance = dn.balanceOf(to);
        uint256 initialNFTTotalSupply = mirror.totalSupply();
        uint256 initialRecipientNFTBalance = mirror.balanceOf(to);
        uint256 initialNextTokenId = getNextTokenId();
        uint256 initialRecipientOwnedLength = getAddressData(to).ownedLength;

        uint256 amountMinted = amount / _WAD;

        // it should emit erc721 transfer events for each id minted to recipient
        for (uint256 i = 1; i < amountMinted + 1; ++i) {
            vm.expectEmit(true, true, true, false, address(mirror));
            emit Transfer(address(0), to, i);
        }

        // it should emit ERC20 transfer event
        // vm.expectEmit(true, true, false, true, address(dn));
        // emitERC20TransferEvent(address(0), to, amount);

        dn.mint(to, amount);

        // it should increment token totalSupply by amount
        assertEq(dn.totalSupply(), initialTokenTotalSupply + amount);
        // it should increment recipient address balance by amount
        assertEq(dn.balanceOf(to), initialRecipientTokenBalance + amount);
        // it should increment NFT totalSupply by the NFT equivalent of amount
        assertEq(mirror.totalSupply(), initialNFTTotalSupply + amountMinted);
        // it should increment recipient address balance by the NFT equivalent of amount
        assertEq(mirror.balanceOf(to), initialRecipientNFTBalance + amountMinted);

        for (uint256 i = 1; i < amountMinted + 1; ++i) {
            // it should set ownership alias of each new id minted to recipient's alias
            assertEq(mirror.ownerOf(i), to);
            // it should set owned index of each new id minted to its id in the recipient's owned array
            assertEq(getOwnedIndexOf(i), i - 1);
        }
        // it should update the nextTokenId to the last assigned token id + 1
        assertEq(getNextTokenId(), initialNextTokenId + amountMinted);
        // it should set increase the length of the recipient's owned array by the NFT equivalent of amount
        assertEq(getAddressData(to).ownedLength, initialRecipientOwnedLength + amountMinted);
    }

    function getNextTokenId() private view returns (uint256) {
        uint256 a = uint256(vm.load(address(dn), bytes32(START_SLOT)));
        return (a >> 32) & type(uint32).max;
    }

    struct AddressData {
        // Auxiliary data.
        uint88 aux;
        // Flags for `initialized` and `skipNFT`.
        uint8 flags;
        // The alias for the address. Zero means absence of an alias.
        uint32 addressAlias;
        // The number of NFT tokens.
        uint32 ownedLength;
        // The token balance in wei.
        uint96 balance;
    }

    function getAddressData(address addr) private view returns (AddressData memory data) {
        uint256 v =
            uint256(vm.load(address(dn), keccak256(abi.encode(addr, bytes32(START_SLOT + 8)))));
        data.aux = uint88(v & type(uint88).max);
        data.flags = uint8((v >> 88) & 0xff);
        data.addressAlias = uint32((v >> 96) & type(uint32).max);
        data.ownedLength = uint32((v >> 128) & type(uint32).max);
        data.balance = uint32((v >> 160) & type(uint32).max);
    }

    function getOwnedIndexOf(uint256 index) private view returns (uint256) {
        uint256 v = uint256(
            vm.load(address(dn), keccak256(abi.encode(index >> 3, bytes32(START_SLOT + 7))))
        );

        return v >> ((index & 7) << 5);
    }

    function _ownedIndex(uint256 i) private pure returns (uint256) {
        unchecked {
            return (i << 1) + 1;
        }
    }

    // /// @dev Returns the uint32 value at `index` in `map`.
    // function _get(Uint32Map storage map, uint256 index) private view returns (uint32 result) {
    //     result = uint32(map.map[index >> 3] >> ((index & 7) << 5));
    // }

    // This should work for emitting overloaded events but foundry fails sometimes and passes sometimes saying log != expected log when the logs shown are in fact the same
    // function emitERC20TransferEvent(address from, address to, uint256 amount) private {
    //     assembly {
    //         // log erc20 transfer using assembly because nft transfer is already defined
    //         mstore(0x00, amount)
    //         log3(
    //             0x00,
    //             0x20,
    //             0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef,
    //             from,
    //             to
    //         )
    //     }
    // }
}
