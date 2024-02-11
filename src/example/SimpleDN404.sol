// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../DN404.sol";
import "../DN404Mirror.sol";
import {Ownable} from "../../lib/solady/src/auth/Ownable.sol";

contract SimpleDN404 is DN404, Ownable {
    string private _name;
    string private _symbol;
    string private _baseURI;
    uint96 private _initialTokenSupply;
    address private _initialSupplyOwner;
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
        _initialTokenSupply = initialTokenSupply;
        _initialSupplyOwner = initialSupplyOwner;

        _mirror = new DN404Mirror(owner());
    }

    function initializeDN404() public onlyOwner {
        _initializeDN404(_initialTokenSupply, _initialSupplyOwner, address(_mirror));
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

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(_baseURI, id));
    }

    function withdraw() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }
}
