// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibMap} from "solady/utils/LibMap.sol";
import {DN404Mirror} from "./DN404Mirror.sol";

abstract contract DN404 {
    using LibMap for *;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event SkipNFTWhitelistSet(address indexed target, bool status);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CUSTOM ERRORS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    error AlreadyInitialized();

    error InvalidTotalNFTSupply();

    error Unauthorized();

    error TransferToZeroAddress();

    error MirrorAddressIsZero();

    error ApprovalCallerNotOwnerNorApproved();

    error TransferCallerNotOwnerNorApproved();

    error TransferFromIncorrectOwner();

    error TokenDoesNotExist();

    uint256 private constant _WAD = 1000000000000000000;

    uint256 private constant _MAX_TOKEN_ID = 0xffffffff;

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
        address mirrorERC721;
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

    function _initializeDN404(uint32 totalNFTSupply, address initialSupplyOwner, address mirror)
        internal
    {
        if (totalNFTSupply == 0 || totalNFTSupply >= _MAX_TOKEN_ID) {
            revert InvalidTotalNFTSupply();
        }
        if (initialSupplyOwner == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        if ($.nextTokenId != 0) revert AlreadyInitialized();

        if (mirror == address(0)) revert MirrorAddressIsZero();
        _linkMirrorContract(mirror);

        $.nextTokenId = 1;
        $.totalNFTSupply = totalNFTSupply;
        $.mirrorERC721 = mirror;

        unchecked {
            uint256 balance = uint256(totalNFTSupply) * _WAD;
            $.addressData[initialSupplyOwner].balance = uint96(balance);

            emit Transfer(address(0), initialSupplyOwner, balance);
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

    function balanceOf(address owner) public view virtual returns (uint256) {
        return _getDN404Storage().addressData[owner].balance;
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        DN404Storage storage $ = _getDN404Storage();

        $.allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external virtual {
        DN404Storage storage $ = _getDN404Storage();

        uint256 allowed = $.allowance[from][msg.sender];

        if (allowed != type(uint256).max) {
            $.allowance[from][msg.sender] = allowed - amount;
        }

        _transfer(from, to, amount);
    }

    function _approveNFT(address spender, uint256 id, address msgSender)
        internal
        returns (address)
    {
        DN404Storage storage $ = _getDN404Storage();

        address owner = $.aliasToAddress[$.ownerships.get(id)];

        if (msgSender != owner) {
            if (!$.operatorApprovals[owner][msgSender]) {
                revert ApprovalCallerNotOwnerNorApproved();
            }
        }

        $.tokenApprovals[id] = spender;

        return owner;
    }

    function _setApprovalForAll(address operator, bool approved, address msgSender)
        internal
        virtual
    {
        DN404Storage storage $ = _getDN404Storage();

        $.operatorApprovals[msgSender][operator] = approved;
    }

    function _transferFromNFT(address from, address to, uint256 id, address msgSender)
        internal
        virtual
    {
        DN404Storage storage $ = _getDN404Storage();

        if (to == address(0)) revert TransferToZeroAddress();

        address owner = $.aliasToAddress[$.ownerships.get(id)];

        if (from != owner) revert TransferFromIncorrectOwner();

        if (msgSender != from) {
            if (!$.operatorApprovals[from][msgSender]) {
                if (msgSender != $.tokenApprovals[id]) {
                    revert TransferCallerNotOwnerNorApproved();
                }
            }
        }

        AddressData storage fromAddressData = $.addressData[from];
        AddressData storage toAddressData = $.addressData[to];

        fromAddressData.balance -= uint96(_WAD);

        unchecked {
            toAddressData.balance += uint96(_WAD);

            $.ownerships.set(id, _registerAndResolveAlias(to));
            delete $.tokenApprovals[id];

            uint256 updatedId = $.owned[from].get(--fromAddressData.ownedLength);
            $.owned[from].set($.ownedIndex.get(id), uint32(updatedId));

            uint256 n = toAddressData.ownedLength++;
            $.ownedIndex.set(updatedId, $.ownedIndex.get(id));
            $.owned[to].set(n, uint32(id));
            $.ownedIndex.set(id, uint32(n));
        }

        emit Transfer(from, to, _WAD);
    }

    function _registerAndResolveAlias(address to) internal returns (uint32) {
        DN404Storage storage $ = _getDN404Storage();
        AddressData storage toAddressData = $.addressData[to];
        uint32 addressAlias = toAddressData.addressAlias;
        if (addressAlias == 0) {
            addressAlias = ++$.numAliases;
            toAddressData.addressAlias = addressAlias;
            $.aliasToAddress[addressAlias] = to;
        }
        return addressAlias;
    }

    struct _TransferTemps {
        address mirror;
        uint256 fromBalanceBefore;
        uint256 toBalanceBefore;
        uint256 toBalance;
        uint256 fromBalance;
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = $.addressData[from];
        AddressData storage toAddressData = $.addressData[to];

        _TransferTemps memory t;
        t.mirror = $.mirrorERC721;

        t.fromBalanceBefore = fromAddressData.balance;
        fromAddressData.balance = uint96(t.fromBalance = t.fromBalanceBefore - amount);

        unchecked {
            t.toBalanceBefore = toAddressData.balance;
            toAddressData.balance = uint96(t.toBalance = t.toBalanceBefore + amount);

            bool isFromWhitelisted = $.whitelist[from];
            bool isToWhitelisted = $.whitelist[to];

            uint256 nftAmountToBurn = ((t.fromBalanceBefore / _WAD) - (t.fromBalance / _WAD));
            uint256 nftAmountToMint = ((t.toBalance / _WAD) - (t.toBalanceBefore / _WAD));

            uint256 total;
            if (!isFromWhitelisted && !isToWhitelisted) {
                total = nftAmountToBurn + nftAmountToMint;
            } else if (isFromWhitelisted && isToWhitelisted) {
                total = 0;
            } else if (isFromWhitelisted) {
                total = nftAmountToMint;
            } else if (isToWhitelisted) {
                total = nftAmountToBurn;
            }

            uint256[] memory packedLogs = new uint256[](total);
            uint256 n;

            if (!isFromWhitelisted) {
                address _from = from;
                LibMap.Uint32Map storage fromOwned = $.owned[_from];
                uint256 i = fromAddressData.ownedLength;
                uint256 end = i - nftAmountToBurn;
                DN404Storage storage _$ = $;

                // Burn loop.
                if (i != end) {
                    do {
                        uint256 id = fromOwned.get(--i);
                        _$.ownedIndex.set(id, 0);
                        _$.ownerships.set(id, 0);
                        delete _$.tokenApprovals[id];

                        packedLogs[n++] = (uint256(uint160(_from)) << 96) | (id << 8) | 1;
                    } while (i != end);
                    fromAddressData.ownedLength = uint32(i);
                }
            }

            if (!isToWhitelisted) {
                address _to = to;
                DN404Storage storage _$ = $;
                LibMap.Uint32Map storage toOwned = $.owned[_to];
                uint256 i = toAddressData.ownedLength;
                AddressData storage _toAddressData = toAddressData;
                uint256 end = i + nftAmountToMint;
                uint256 id = _$.nextTokenId;
                uint32 toAlias = _registerAndResolveAlias(_to);
                uint256 totalNFTSupply = _$.totalNFTSupply;

                // Mint loop.
                if (i != end) {
                    do {
                        while (_$.ownerships.get(id) != 0) {
                            if (++id > totalNFTSupply) id = 1;
                        }

                        toOwned.set(i, uint32(id));
                        _$.ownerships.set(id, toAlias);
                        _$.ownedIndex.set(id, uint32(i++));

                        packedLogs[n++] = (uint256(uint160(_to)) << 96) | (id << 8);

                        // todo: ensure we don't overwrite ownership of early tokens that weren't burned
                        if (++id > totalNFTSupply) id = 1;
                    } while (i != end);
                    _toAddressData.ownedLength = uint32(i);
                    _$.nextTokenId = uint32(id);
                }
            }

            if (packedLogs.length > 0) _logNftTransfer(t.mirror, packedLogs);
        }

        emit Transfer(from, to, amount);
        return true;
    }

    function _logNftTransfer(address mirror, uint256[] memory p) private {
        require(DN404Mirror(payable(mirror)).logTransfer(p));
    }

    function _ownerAt(uint256 id) internal view virtual returns (address result) {
        DN404Storage storage $ = _getDN404Storage();
        result = $.aliasToAddress[$.ownerships.get(id)];
    }

    function _ownerOf(uint256 id) internal view virtual returns (address result) {
        if (!_exists(id)) revert TokenDoesNotExist();
        result = _ownerAt(id);
    }

    function _exists(uint256 id) internal view virtual returns (bool result) {
        result = _ownerAt(id) != address(0);
    }

    function _getApproved(uint256 id) internal view returns (address result) {
        if (!_exists(id)) revert TokenDoesNotExist();
        result = _getDN404Storage().tokenApprovals[id];
    }

    function mirrorERC721() public view returns (address mirror) {
        return _getDN404Storage().mirrorERC721;
    }

    function _linkMirrorContract(address mirror) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x0f4599e5) // `linkMirrorContract(address)`.
            mstore(0x20, caller())
            if iszero(
                and(
                    and(eq(mload(0x00), 1), eq(returndatasize(), 0x20)),
                    call(gas(), mirror, 0, 0x1c, 0x24, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0xd125259c) // `LinkMirrorContractFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    function _calldataload(uint256 offset) private pure returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := calldataload(offset)
        }
    }

    function _return(uint256 x) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, x)
            return(0x00, 0x20)
        }
    }

    modifier dn404Fallback() virtual {
        DN404Storage storage $ = _getDN404Storage();

        uint256 fnSelector = _calldataload(0x00) >> 224;

        // `isApprovedForAll(address,address)`.
        if (fnSelector == 0xe985e9c5) {
            if (msg.sender != $.mirrorERC721) revert Unauthorized();
            if (msg.data.length < 0x44) revert();

            address owner = address(uint160(_calldataload(0x04)));
            address operator = address(uint160(_calldataload(0x24)));

            _return($.operatorApprovals[owner][operator] ? 1 : 0);
        }
        // `ownerOf(uint256)`.
        if (fnSelector == 0x6352211e) {
            if (msg.sender != $.mirrorERC721) revert Unauthorized();
            if (msg.data.length < 0x24) revert();

            uint256 id = _calldataload(0x04);

            _return(uint160(_ownerOf(id)));
        }
        // `transferFromNFT(address,address,uint256,address)`.
        if (fnSelector == 0xe5eb36c8) {
            if (msg.sender != $.mirrorERC721) revert Unauthorized();
            if (msg.data.length < 0x84) revert();

            address from = address(uint160(_calldataload(0x04)));
            address to = address(uint160(_calldataload(0x24)));
            uint256 id = _calldataload(0x44);
            address msgSender = address(uint160(_calldataload(0x64)));

            _transferFromNFT(from, to, id, msgSender);
            _return(1);
        }
        // `setApprovalForAll(address,bool,address)`.
        if (fnSelector == 0x813500fc) {
            if (msg.sender != $.mirrorERC721) revert Unauthorized();
            if (msg.data.length < 0x64) revert();

            address spender = address(uint160(_calldataload(0x04)));
            bool status = _calldataload(0x24) != 0;
            address msgSender = address(uint160(_calldataload(0x44)));

            _setApprovalForAll(spender, status, msgSender);
            _return(1);
        }
        // `approveNFT(address,uint256,address)`.
        if (fnSelector == 0xd10b6e0c) {
            if (msg.sender != $.mirrorERC721) revert Unauthorized();
            if (msg.data.length < 0x64) revert();

            address spender = address(uint160(_calldataload(0x04)));
            uint256 id = _calldataload(0x24);
            address msgSender = address(uint160(_calldataload(0x44)));

            _return(uint160(_approveNFT(spender, id, msgSender)));
        }
        // `getApproved(uint256)`.
        if (fnSelector == 0x081812fc) {
            if (msg.sender != $.mirrorERC721) revert Unauthorized();
            if (msg.data.length < 0x24) revert();

            uint256 id = _calldataload(0x04);

            _return(uint160(_getApproved(id)));
        }
        // `implementsDN404()`.
        if (fnSelector == 0xb7a94eb8) {
            _return(1);
        }
        _;
    }

    fallback() external payable virtual dn404Fallback {}

    receive() external payable virtual {}

    function _getDN404Storage() internal pure returns (DN404Storage storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            // keccak256(abi.encode(uint256(keccak256("dn404")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := 0x61dd0d320a11019af7688ced18637b1235059a4e8141ed71cfccbe9f2da16600
        }
    }
}
