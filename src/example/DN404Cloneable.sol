// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../DN404.sol";
import "../DN404Mirror.sol";
import {Ownable} from "../../lib/solady/src/auth/Ownable.sol";
import {LibString} from "../../lib/solady/src/utils/LibString.sol";
import {SafeTransferLib} from "../../lib/solady/src/utils/SafeTransferLib.sol";
import {Initializable} from "../../lib/solady/src/utils/Initializable.sol";
import {LibClone} from "../../lib/solady/src/utils/LibClone.sol";
import {IERC20} from "../../lib/forge-std/src/interfaces/IERC20.sol";

/**
 * @title DN404Cloneable
 * @notice Simple DN404 contract that allows clones of the contract to be created.
 * Both DN404 Base and DN404Mirror are created as EIP 1167 clones.
 */
contract DN404Cloneable is DN404, Ownable, Initializable {
    error MaxTokenSupplyExceeded();

    string private _name;
    string private _sym;
    string private _baseURI;

    uint96 private _maxTokenSupply;

    // Immutable so clones don't inherit this and proxy calls still read the right value.
    address private immutable dn404mirrorImpl = address(new DN404Mirror(address(this)));

    function initialize(
        address owner_,
        string calldata name_,
        string calldata symbol_,
        string calldata baseURI_,
        address initialMintTarget_,
        uint96 initialTokenSupply_,
        uint96 maxTokenSupply_
    ) external payable initializer {
        _initializeOwner(owner_);

        _name = name_;
        _sym = symbol_;
        _baseURI = baseURI_;
        _maxTokenSupply = maxTokenSupply_;

        // We don't care about the constructor since address(0) is acceptable.
        address mirror = LibClone.clone(dn404mirrorImpl);

        _initializeDN404(initialTokenSupply_, initialMintTarget_, mirror);
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

    function mint(address to, uint256 amount) public onlyOwner {
        if (amount + totalSupply() > _maxTokenSupply) {
            revert MaxTokenSupplyExceeded();
        }

        _mint(to, amount);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return bytes(_baseURI).length != 0
            ? string(abi.encodePacked(_baseURI, LibString.toString(tokenId)))
            : "";
    }

    function withdraw() public onlyOwner {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }
}
