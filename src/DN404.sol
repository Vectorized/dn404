// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibMap} from "solady/utils/LibMap.sol";

abstract contract ERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721Receiver.onERC721Received.selector;
    }
}

abstract contract DN404 {
    using LibMap for *;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    event ERC20Transfer(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id
    );

    event ERC721Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id
    );

    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    event SkipNFTWhitelistSet(
        address indexed target,
        bool status
    );

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CUSTOM ERRORS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    error AlreadyInitialized();

    error InvalidTotalNFTSupply();

    error TransferToZeroAddress();

    error TokenDoesNotExist();

    error TokenAlreadyExists();

    error ApprovalCallerNotOwnerNorApproved();

    error TransferCallerNotOwnerNorApproved();

    error TransferFromIncorrectOwner();

    error UnsafeRecipient();

    uint256 private constant _WAD = 1000000000000000000;

    uint256 private constant _MAX_TOKEN_ID = 0xffffffff;

    // keccak256(abi.encode(uint256(keccak256("dn404")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _DN404_STORAGE_LOCATION =
        0x61dd0d320a11019af7688ced18637b1235059a4e8141ed71cfccbe9f2da16600;

    struct AddressData {
        // The alias for the address. Zero means absence of an alias.
        uint32 addressAlias;
        // The number of NFT tokens.
        uint32 ownedLength;
        // The token balance in wei.
        uint96 balance;
    }

    struct DN404Storage {

        uint32 numAliases;

        uint32 nextTokenId;

        uint32 totalNFTSupply;

        mapping(uint32 => address) aliasToAddress;

        mapping(address => mapping(address => bool)) operatorApprovals;

        mapping(uint256 => address) tokenApprovals;

        mapping(address => mapping(address => uint256)) allowance;

        LibMap.Uint32Map ownedIndex;

        mapping(address => LibMap.Uint32Map) owned;

        LibMap.Uint32Map ownerships; 

        mapping(address => AddressData) addressData;

        mapping(address => bool) whitelist;
    }

    function _initializeDN404(uint32 totalNFTSupply, address initialSupplyOwner) internal {
        if (totalNFTSupply == 0 || totalNFTSupply >= _MAX_TOKEN_ID) revert InvalidTotalNFTSupply();
        if (initialSupplyOwner == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        if ($.nextTokenId != 0) revert AlreadyInitialized();
        
        $.nextTokenId = 1;
        $.totalNFTSupply = totalNFTSupply;

        unchecked {
            uint256 balance = uint256(totalNFTSupply) * _WAD;
            $.addressData[initialSupplyOwner].balance = uint96(balance);

            emit ERC20Transfer(address(0), initialSupplyOwner, balance);
        }
        
        _setSkipNFTWhitelist(initialSupplyOwner, true);
    }

    function name() public view virtual returns (string memory);

    function symbol() public view virtual returns (string memory);

    function tokenURI(uint256 id) public view virtual returns (string memory);

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function _setSkipNFTWhitelist(address target, bool state) internal {
        _getDN404Storage().whitelist[target] = state;
        emit SkipNFTWhitelistSet(target, state);
    }

    function totalSupply() public view returns (uint256) {
        unchecked {
            return uint256(_getDN404Storage().totalNFTSupply) * _WAD;    
        }
    }

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        DN404Storage storage $ = _getDN404Storage();
        owner = $.aliasToAddress[$.ownerships.get(id)];
        if (owner == address(0)) revert TokenDoesNotExist();
    }
    
    function approve(
        address spender,
        uint256 amountOrId
    ) public virtual returns (bool) {
        DN404Storage storage $ = _getDN404Storage();

        if (_isId(amountOrId)) {
            address owner = $.aliasToAddress[$.ownerships.get(amountOrId)];

            if (msg.sender != owner)
                if (!$.operatorApprovals[owner][msg.sender])
                    revert ApprovalCallerNotOwnerNorApproved();

            $.tokenApprovals[amountOrId] = spender;

            emit Approval(owner, spender, amountOrId);
        } else {
            $.allowance[msg.sender][spender] = amountOrId;

            emit Approval(msg.sender, spender, amountOrId);
        }

        return true;
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        DN404Storage storage $ = _getDN404Storage();
        $.operatorApprovals[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function _isId(uint256 amountOrId) private pure returns (bool result) {
        assembly {
            result := iszero(or(iszero(amountOrId), gt(amountOrId, _MAX_TOKEN_ID)))
        }
    }

    function transferFrom(
        address from,
        address to,
        uint256 amountOrId
    ) public virtual {
        DN404Storage storage $ = _getDN404Storage();

        if (_isId(amountOrId)) {
            if (to == address(0)) revert TransferToZeroAddress();

            address owner = $.aliasToAddress[$.ownerships.get(amountOrId)];

            if (from != owner) revert TransferFromIncorrectOwner();

            if (msg.sender != from) {
                if (!$.operatorApprovals[from][msg.sender])
                    if (msg.sender != $.tokenApprovals[amountOrId])
                        revert TransferCallerNotOwnerNorApproved();
            }

            AddressData storage fromAddressData = $.addressData[from];
            AddressData storage toAddressData = $.addressData[to];

            fromAddressData.balance -= uint96(_WAD);

            unchecked {
                toAddressData.balance += uint96(_WAD);

                $.ownerships.set(amountOrId, _registerAndResolveAlias(to));
                delete $.tokenApprovals[amountOrId];

                uint256 updatedId = $.owned[from].get(--fromAddressData.ownedLength);
                $.owned[from].set($.ownedIndex.get(amountOrId), uint32(updatedId));

                uint256 n = toAddressData.ownedLength++;
                $.ownedIndex.set(updatedId, $.ownedIndex.get(amountOrId));
                $.owned[to].set(n, uint32(amountOrId));            
                $.ownedIndex.set(amountOrId, uint32(n));
            }

            emit Transfer(from, to, amountOrId);
            emit ERC20Transfer(from, to, _WAD);

        } else {
            uint256 allowed = $.allowance[from][msg.sender];

            if (allowed != type(uint256).max) {
                $.allowance[from][msg.sender] = allowed - amountOrId;
            }

            _transfer(from, to, amountOrId);
        }
    }

    function _registerAndResolveAlias(address to) private returns (uint32) {
        DN404Storage storage $ = _getDN404Storage();
        AddressData storage toAddressData = $.addressData[to];
        uint32 addressAlias = toAddressData.addressAlias;
        if (addressAlias == 0) {
            addressAlias = ++$.numAliases;
            toAddressData.addressAlias = addressAlias;
        }
        return addressAlias;
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0 &&
            ERC721Receiver(to).onERC721Received(msg.sender, from, id, "") !=
            ERC721Receiver.onERC721Received.selector
        ) {
            revert UnsafeRecipient();
        }
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0 &&
            ERC721Receiver(to).onERC721Received(msg.sender, from, id, data) !=
            ERC721Receiver.onERC721Received.selector
        ) {
            revert UnsafeRecipient();
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = $.addressData[from];
        AddressData storage toAddressData = $.addressData[to];

        uint256 fromBalanceBefore = fromAddressData.balance;
        fromAddressData.balance = uint96(fromBalanceBefore - amount);

        unchecked {
            uint256 toBalanceBefore = toAddressData.balance;
            toAddressData.balance = uint96(toBalanceBefore + amount);

            if (!$.whitelist[from]) {
                LibMap.Uint32Map storage fromOwned = $.owned[from];
                uint256 i = fromAddressData.ownedLength;
                uint256 end = i - ((fromBalanceBefore / _WAD) - ((fromBalanceBefore - amount) / _WAD));
                // Burn loop.
                if (i != end) {
                    do {
                        uint256 id = fromOwned.get(--i);
                        $.ownedIndex.set(id, 0);
                        $.ownerships.set(id, 0);
                        delete $.tokenApprovals[id];

                        emit Transfer(from, address(0), id);
                    } while (i != end);
                    fromAddressData.ownedLength = uint32(i);
                }    
            }

            if (!$.whitelist[to]) {
                LibMap.Uint32Map storage toOwned = $.owned[to];
                uint256 i = toAddressData.ownedLength;
                uint256 end = i + (((toBalanceBefore + amount) / _WAD) - (toBalanceBefore / _WAD));
                uint256 id = $.nextTokenId;
                uint32 toAlias = _registerAndResolveAlias(to);
                // Mint loop.
                if (i != end) {
                    do {
                        while ($.ownerships.get(id) != 0) if (++id > _MAX_TOKEN_ID) id = 1;

                        toOwned.set(i, uint32(id));
                        $.ownerships.set(id, toAlias);
                        $.ownedIndex.set(id, uint32(i++));

                        emit Transfer(address(0), to, id);
                        if (++id > _MAX_TOKEN_ID) id = 1;
                    } while (i != end);
                    toAddressData.ownedLength = uint32(i);
                    $.nextTokenId = uint32(id);
                }
            }
        }

        emit ERC20Transfer(from, to, amount);
        return true;
    }

    function _getDN404Storage() private pure returns (DN404Storage storage $) {
        assembly {
            $.slot := _DN404_STORAGE_LOCATION
        }
    }
}