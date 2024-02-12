// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./DN404.sol";
import {DailyOutflowCounterLib} from "./DailyOutflowCounterLib.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {GasBurnerLib} from "solady/utils/GasBurnerLib.sol";

contract Asterix is DN404, OwnableRoles {
    using DailyOutflowCounterLib for *;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                       CUSTOM ERRORS                        */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    error Locked();

    error MaxBalanceLimitReached();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    string internal _name;

    string internal _symbol;

    string internal _baseURI;

    bool public baseURILocked;

    bool public nameAndSymbolLocked;

    bool public gasBurnFactorLocked;

    bool public whitelistLocked;

    bool public maxBalanceLimitLocked;

    uint8 public maxBalanceLimit;

    uint32 public gasBurnFactor;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CONSTRUCTOR                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    constructor() {
        _construct(tx.origin);
    }

    function _construct(address initialOwner) internal {
        _initializeOwner(initialOwner);
        _setWhitelisted(initialOwner, true);
        _name = "Asterix";
        _symbol = "ASTX";
        gasBurnFactor = 50_000;
        maxBalanceLimit = 35;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          METADATA                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 id) public view override returns (string memory result) {
        if (!_exists(id)) revert TokenDoesNotExist();
        if (bytes(_baseURI).length != 0) {
            result = LibString.replace(_baseURI, "{id}", LibString.toString(id));
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         TRANSFERS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    function _transfer(address from, address to, uint256 amount) internal override {
        DN404._transfer(from, to, amount);
        _applyMaxBalanceLimit(to);
        if (from != to) _applyGasBurn(from, amount);
    }

    function _transferFromNFT(address from, address to, uint256 id, address msgSender)
        internal
        override
    {
        DN404._transferFromNFT(from, to, id, msgSender);
        _applyMaxBalanceLimit(to);
        if (from != to) _applyGasBurn(from, _WAD);
    }

    function _applyMaxBalanceLimit(address to) internal view {
        unchecked {
            uint256 limit = maxBalanceLimit;
            if (limit != 0) {
                if (!_getAux(to).isWhitelisted()) {
                    if (balanceOf(to) > _WAD * limit) revert MaxBalanceLimitReached();
                }
            }
        }
    }

    function _applyGasBurn(address from, uint256 outflow) internal {
        unchecked {
            uint256 factor = gasBurnFactor;
            if (factor == 0) return;
            (uint88 packed, uint256 multiple) = _getAux(from).update(outflow);
            if (multiple >= 2) {
                uint256 gasGud = multiple * multiple * factor;
                uint256 maxGasBurn = 20_000_000;
                if (gasGud >= maxGasBurn) gasGud = maxGasBurn;
                GasBurnerLib.burn(gasGud);
            }
            _setAux(from, packed);
        }
    }

    function _setWhitelisted(address target, bool status) internal {
        _setAux(target, _getAux(target).setWhitelisted(status));
    }

    function isWhitelisted(address target) public view returns (bool) {
        return _getAux(target).isWhitelisted();
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ADMIN FUNCTIONS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    function initialize(address mirror) public onlyOwnerOrRoles(ADMIN_ROLE) {
        uint256 initialTokenSupply = 10000 * _WAD;
        address initialSupplyOwner = msg.sender;
        _initializeDN404(initialTokenSupply, initialSupplyOwner, mirror);
        _setWhitelisted(initialSupplyOwner, true);
    }

    function lockMaxBalanceLimit() public onlyOwnerOrRoles(ADMIN_ROLE) {
        maxBalanceLimitLocked = true;
    }

    function setMaxBalanceLimit(uint8 value) public onlyOwnerOrRoles(ADMIN_ROLE) {
        if (maxBalanceLimitLocked) revert Locked();
        maxBalanceLimit = value;
    }

    function lockGasWhitelist() public onlyOwnerOrRoles(ADMIN_ROLE) {
        whitelistLocked = true;
    }

    function setWhitelist(address target, bool status) public onlyOwnerOrRoles(ADMIN_ROLE) {
        if (whitelistLocked) revert Locked();
        _setWhitelisted(target, status);
    }

    function lockGasBurnFactor() public onlyOwnerOrRoles(ADMIN_ROLE) {
        gasBurnFactorLocked = true;
    }

    function setGasBurnFactor(uint32 gasBurnFactor_) public onlyOwnerOrRoles(ADMIN_ROLE) {
        if (gasBurnFactorLocked) revert Locked();
        gasBurnFactor = gasBurnFactor_;
    }

    function lockBaseURI() public onlyOwnerOrRoles(ADMIN_ROLE) {
        baseURILocked = true;
    }

    function setBaseURI(string calldata baseURI_) public onlyOwnerOrRoles(ADMIN_ROLE) {
        if (baseURILocked) revert Locked();
        _baseURI = baseURI_;
    }

    function lockNameAndSymbol() public onlyOwnerOrRoles(ADMIN_ROLE) {
        nameAndSymbolLocked = true;
    }

    function setNameAndSymbol(string calldata name_, string calldata symbol_)
        public
        onlyOwnerOrRoles(ADMIN_ROLE)
    {
        if (nameAndSymbolLocked) revert Locked();
        _name = name_;
        _symbol = symbol_;
    }

    function withdraw() public onlyOwnerOrRoles(ADMIN_ROLE) {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }
}
