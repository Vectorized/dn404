// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../DN404.sol";
import "../DN404Mirror.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {MerkleProofLib} from "solady/utils/MerkleProofLib.sol";

/**
 * @title NFTMintDN404
 * @notice Sample DN404 contract that demonstrates the owner selling NFTs rather than the fungible token.
 * The underlying call still mints ERC20 tokens, but to the end user it'll appear as a standard NFT mint.
 * Each address is limited to MAX_PER_WALLET total mints.
 */
contract NFTMintDN404 is DN404, Ownable {
    string private _name;
    string private _symbol;
    string private _baseURI;
    bytes32 private allowlistRoot;
    uint120 public publicPrice;
    uint120 public allowlistPrice;
    bool public live;
    uint256 public numMinted;

    uint256 public constant MAX_PER_WALLET = 5;
    uint256 public constant MAX_SUPPLY = 5000;

    error InvalidProof();
    error InvalidMint();
    error InvalidPrice();
    error TotalSupplyReached();
    error NotLive();

    modifier isValidMint(uint256 price, uint256 amount) {
        if (!live) {
            revert NotLive();
        }
        if (price * amount != msg.value) {
            revert InvalidPrice();
        }
        if (numMinted + amount > MAX_SUPPLY) {
            revert TotalSupplyReached();
        }
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        bytes32 allowlistRoot_,
        uint120 publicPrice_,
        uint120 allowlistPrice_,
        uint96 initialTokenSupply,
        address initialSupplyOwner
    ) {
        _initializeOwner(msg.sender);

        _name = name_;
        _symbol = symbol_;
        allowlistRoot = allowlistRoot_;
        publicPrice = publicPrice_;
        allowlistPrice = allowlistPrice_;

        address mirror = address(new DN404Mirror(msg.sender));
        _initializeDN404(initialTokenSupply, initialSupplyOwner, mirror);
    }

    function mint(uint88 amount) public payable isValidMint(publicPrice, amount) {
        uint88 curMintCount = _getAux(msg.sender);
        if (curMintCount + amount > MAX_PER_WALLET) {
            revert InvalidMint();
        }
        unchecked {
            _setAux(msg.sender, curMintCount + amount);
            ++numMinted;
        }
        _mint(msg.sender, amount * _unit());
    }

    function allowlistMint(uint88 amount, bytes32[] calldata proof)
        public
        payable
        isValidMint(allowlistPrice, amount)
    {
        if (
            !MerkleProofLib.verifyCalldata(
                proof, allowlistRoot, keccak256(abi.encodePacked(msg.sender))
            )
        ) {
            revert InvalidProof();
        }
        uint88 curMintCount = _getAux(msg.sender);
        if (curMintCount + amount > MAX_PER_WALLET) {
            revert InvalidMint();
        }
        unchecked {
            _setAux(msg.sender, curMintCount + amount);
            ++numMinted;
        }
        _mint(msg.sender, amount * _unit());
    }

    function setBaseURI(string calldata baseURI_) public onlyOwner {
        _baseURI = baseURI_;
    }

    function setPrices(uint120 publicPrice_, uint120 allowlistPrice_) public onlyOwner {
        publicPrice = publicPrice_;
        allowlistPrice = allowlistPrice_;
    }

    function toggleLive() public onlyOwner {
        live = !live;
    }

    function withdraw() public onlyOwner {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory result) {
        if (bytes(_baseURI).length != 0) {
            result = string(abi.encodePacked(_baseURI, LibString.toString(tokenId)));
        }
    }
}
