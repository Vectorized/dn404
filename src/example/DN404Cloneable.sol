// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../DN404.sol";
import "../DN404Mirror.sol";
import {Ownable} from "../../lib/solady/src/auth/Ownable.sol";
import {LibString} from "../../lib/solady/src/utils/LibString.sol";
import {SafeTransferLib} from "../../lib/solady/src/utils/SafeTransferLib.sol";
import {Clone} from "../../lib/solady/src/utils/Clone.sol";
import {IERC20} from "../../lib/forge-std/src/interfaces/IERC20.sol";

contract DN404Cloneable is DN404, Ownable, Clone {
    error LiquidityLocked();
    error UnableToGetPair();
    error UnableToWithdraw();
    error InvalidAirdropConfig();
    error FailedToProvideLiquidity();

    LiquidityDetails public liquidityDetails;

    address private constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNISWAP_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    string private _name;
    string private _sym;
    string private _baseURI;
    bool private initialized = true;

    struct Allocations {
        uint80 liquidityAllocation;
        uint80 teamAllocation;
        uint80 airdropAllocation;
    }

    struct LiquidityDetails {
        uint128 liquidityUnlockTimestamp;
        uint128 liquidityAllocation;
    }

    function initialize(
        string calldata name_,
        string calldata sym_,
        Allocations calldata allocations,
        uint96 initialTokenSupply,
        uint256 liquidityLockInSeconds,
        address[] calldata addresses,
        uint256[] calldata amounts
    ) external payable {
        if (initialized) revert();
        initialized = true;

        uint80 teamAllocation = allocations.teamAllocation;
        uint80 airdropAllocation = allocations.airdropAllocation;
        uint80 liquidityAllocation = allocations.liquidityAllocation;
        if (liquidityAllocation + teamAllocation + airdropAllocation != initialTokenSupply) {
            revert();
        }

        _initializeOwner(tx.origin);
        _name = name_;
        _sym = sym_;

        address mirror = address(new DN404Mirror(msg.sender));

        _initializeDN404(uint96(teamAllocation), tx.origin, mirror);

        uint256 supplyBefore = totalSupply();
        for (uint256 i = 0; i < addresses.length; ++i) {
            _mint(addresses[i], amounts[i]);
        }
        uint256 supplyAfter = totalSupply();
        if (supplyAfter - supplyBefore != airdropAllocation) revert InvalidAirdropConfig();

        if (liquidityAllocation > 0) {
            liquidityDetails = LiquidityDetails({
                liquidityUnlockTimestamp: uint128(block.timestamp + liquidityLockInSeconds),
                liquidityAllocation: liquidityAllocation
            });

            _mint(address(this), liquidityAllocation);
            _approve(address(this), UNISWAP_ROUTER, liquidityAllocation);

            address liquidityRecipient = liquidityLockInSeconds == 0 ? tx.origin : address(this);

            (bool success,) = UNISWAP_ROUTER.call{value: msg.value}(
                abi.encodeWithSelector(
                    0xf305d719,
                    address(this),
                    liquidityAllocation,
                    0,
                    0,
                    liquidityRecipient,
                    block.timestamp
                )
            );

            if (!success) revert FailedToProvideLiquidity();
        }
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _sym;
    }

    function setBaseURI(string calldata baseURI_) public onlyOwner {
        _baseURI = baseURI_;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return bytes(_baseURI).length != 0
            ? string(abi.encodePacked(_baseURI, LibString.toString(tokenId)))
            : "";
    }

    function withdraw() public onlyOwner {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }

    function withdrawLP() external onlyOwner {
        if (block.timestamp < liquidityDetails.liquidityUnlockTimestamp) revert LiquidityLocked();

        (bool success, bytes memory result) = UNISWAP_FACTORY.staticcall(
            abi.encodeWithSignature("getPair(address,address)", address(this), WETH)
        );
        if (!success) revert UnableToGetPair();
        address pair = abi.decode(result, (address));
        uint256 balance = IERC20(pair).balanceOf(address(this));
        (success,) = pair.call(abi.encodeWithSelector(0xa9059cbb, owner(), balance));

        if (!success) revert UnableToWithdraw();
    }
}
