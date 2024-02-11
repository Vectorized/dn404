// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibMap} from "solady/utils/LibMap.sol";

abstract contract DN404A {
    using LibMap for *;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event SkipNFTSet(address indexed target, bool status);

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

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    uint32 private constant _BURNED_ALIAS = 1;

    uint256 private constant _WAD = 1e18;

    uint256 private constant _MAX_TOKEN_ID = 0xffffffff;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    struct AddressData {
        // Set true when address data storage has been initialized.
        bool initialized;
        // If the account should skip NFT minting.
        bool skipNFT;
        // The alias for the address. Zero means absence of an alias.
        uint32 addressAlias;
        // The number of owned lots.
        uint32 ownedLength;
        // The token balance in wei.
        uint96 balance;
    }

    struct DN404Storage {
        uint32 nextAlias;
        uint32 numMinted;
        uint32 numBurned;
        uint32 totalNFTSupply;
        uint96 totalTokenSupply;
        address mirrorERC721;
        mapping(uint32 => address) aliasToAddress;
        mapping(address => mapping(address => bool)) operatorApprovals;
        mapping(uint256 => address) tokenApprovals;
        mapping(address => mapping(address => uint256)) allowance;
        mapping(address => LibMap.Uint32Map) lotHeadIds;
        LibMap.Uint32Map burnedStack;
        // Even indices: owner aliases. Odd indices: owned lot index.
        LibMap.Uint32Map oo;
        mapping(address => AddressData) addressData;
    }

    function _initializeDN404() internal {
        DN404Storage storage $ = _getDN404Storage();
        $.nextAlias = _BURNED_ALIAS + 1;
    }

    function ownerOf(uint256 id) public view returns (address) {
        DN404Storage storage $ = _getDN404Storage();
        if (id > $.numMinted || id == 0) revert TokenDoesNotExist();
        uint32 ownerAlias;
        unchecked {
            do {
                ownerAlias = $.oo.get(_ownershipIndex(id--));
            } while (ownerAlias == 0);
        }
        if (ownerAlias == _BURNED_ALIAS) revert TokenDoesNotExist();
        return $.aliasToAddress[ownerAlias];
    }

    function _getDN404Storage() internal pure returns (DN404Storage storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            // keccak256(abi.encode(uint256(keccak256("dn404")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := 0x61dd0d320a11019af7688ced18637b1235059a4e8141ed71cfccbe9f2da16600
        }
    }

    /// @dev Assumes that {from} has sufficient NFTs to transfer {tokenCount}
    function _transferTokens(address from, address to, uint32 tokenCount) internal {
        DN404Storage storage $ = _getDN404Storage();
        AddressData storage fromData = $.addressData[from];
        AddressData storage toData = $.addressData[to];
        uint32 toAlias = _registerAndResolveAlias(toData, to);
        unchecked {
            while (tokenCount > 0) {
                uint256 nextLotIndex = fromData.ownedLength - 1;
                uint32 headId = $.lotHeadIds[from].get(nextLotIndex);
                uint32 lotSize = _getLotSize(headId);
                if (lotSize > tokenCount) {
                    // We know lot size is at least 2 (lotSize > tokenCount > 0).

                    // Update the lot size that the sender keeps (even if to 1, will get
                    // overwritten).
                    $.oo.set(_ownedIndex(headId + 1), lotSize - tokenCount);

                    headId += lotSize - tokenCount;
                    // Make sure we store the lot size in the next slot if the size > 1.
                    if (tokenCount > 1) {
                        $.oo.set(_ownedIndex(headId + 1), tokenCount);
                    }

                    tokenCount = 0;
                } else {
                    // Pop lot from sender. Don't need to delete index as it'll be overwritten at
                    // next push.
                    fromData.ownedLength--;
                    tokenCount -= lotSize;
                }
                // Push lot to recipient.
                uint32 lotIndex = toData.ownedLength++;
                $.lotHeadIds[to].set(lotIndex, headId);
                // Update lot data for new owner.
                $.oo.set(_ownershipIndex(headId), toAlias);
                $.oo.set(_ownedIndex(headId), lotIndex);
            }
        }
    }

    /// @dev Does not update fungible balances or total supply.
    function _mintTokens(address to, uint256 tokenCount) internal {
        if (to == address(0)) revert TransferToZeroAddress();
        DN404Storage storage $ = _getDN404Storage();
        uint256 numMinted = $.numMinted;
        uint256 headId = numMinted + 1;

        AddressData storage toData = _addressData(to);
        uint32 toAlias = _registerAndResolveAlias(toData, to);

        // Push new lot.
        uint32 lotIndex = toData.ownedLength++;
        $.lotHeadIds[to].set(lotIndex, uint32(headId));

        // Update ownership.
        $.oo.set(_ownershipIndex(headId), toAlias);
        $.oo.set(_ownedIndex(headId), lotIndex);

        // Store lot size if above one (can later detect that it's not an actual index by seeing
        // that the alias is 0).
        if (tokenCount > 1) {
            $.oo.set(_ownedIndex(headId + 1), uint32(tokenCount));
        }

        unchecked {
            uint256 lastId = numMinted + tokenCount;
            if (lastId > _MAX_TOKEN_ID) revert InvalidTotalNFTSupply();

            $.numMinted = uint32(numMinted + tokenCount);
        }
    }

    /**
     * @dev Assumes that headId is valid.
     * @param headId First token ID of lot.
     */
    function _getLotSize(uint256 headId) internal view returns (uint32) {
        DN404Storage storage $ = _getDN404Storage();
        // If at the end of valid IDs must be a lot of size 1.
        if (headId == $.numMinted) return 1;
        unchecked {
            uint256 nextId = headId + 1;
            uint32 nextOwnerAlias = $.oo.get(_ownershipIndex(nextId));
            return nextOwnerAlias == 0 ? $.oo.get(_ownedIndex(nextId)) : 1;
        }
    }

    function _addressData(address a) internal returns (AddressData storage d) {
        DN404Storage storage $ = _getDN404Storage();
        d = $.addressData[a];

        if (!d.initialized) {
            d.initialized = true;
            if (_hasCode(a)) d.skipNFT = true;
        }
    }

    /// @dev Returns if `a` has bytecode of non-zero length.
    function _hasCode(address a) private view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := extcodesize(a) // Can handle dirty upper bits.
        }
    }

    function _registerAndResolveAlias(AddressData storage toAddressData, address to)
        internal
        returns (uint32 addressAlias)
    {
        DN404Storage storage $ = _getDN404Storage();
        addressAlias = toAddressData.addressAlias;
        if (addressAlias == 0) {
            addressAlias = $.nextAlias++;
            toAddressData.addressAlias = addressAlias;
            $.aliasToAddress[addressAlias] = to;
        }
    }

    /// @dev Returns `max(0, x - y)`.
    function _zeroFloorSub(uint256 x, uint256 y) private pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    function _ownershipIndex(uint256 i) private pure returns (uint256) {
        return i << 1;
    }

    function _ownedIndex(uint256 i) private pure returns (uint256) {
        unchecked {
            return (i << 1) + 1;
        }
    }
}
