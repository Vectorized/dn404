// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../DN404.sol";
import "../DN404Mirror.sol";
import {Ownable} from "../../lib/solady/src/auth/Ownable.sol";
import {LibString} from "../../lib/solady/src/utils/LibString.sol";

contract SimpleDN404 is DN404, Ownable {
    string private _name;
    string private _symbol;
    string private _baseURI;
    DN404Mirror private _mirror;

    error TransferFailed();

    constructor(
        string memory name_,
        string memory symbol_,
        uint96 initialTokenSupply,
        address initialSupplyOwner
    ) {
        _initializeOwner(msg.sender);

        _name = name_;
        _symbol = symbol_;

        _mirror = new DN404Mirror(owner());
        _initializeDN404(initialTokenSupply, initialSupplyOwner, address(_mirror));
    }

    // This allows anyone to mint more ERC20 tokens
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function setBaseURI(string calldata baseURI_) public onlyOwner {
        _baseURI = baseURI_;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return bytes(_baseURI).length != 0
            ? string(abi.encodePacked(_baseURI, LibString.toString(tokenId)))
            : "";
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }
}
