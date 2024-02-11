// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {LibMap} from "solady/utils/LibMap.sol";

abstract contract DN404 {
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

    uint256 private constant _WAD = 1000000000000000000;

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
        // The number of NFT tokens.
        uint32 ownedLength;
        // The token balance in wei.
        uint96 balance;
    }

    struct DN404Storage {
        uint32 numAliases;
        uint32 nextTokenId;
        uint32 numBurned;
        uint32 totalNFTSupply;
        uint96 totalTokenSupply;
        address mirrorERC721;
        mapping(uint32 => address) aliasToAddress;
        mapping(address => mapping(address => bool)) operatorApprovals;
        mapping(uint256 => address) tokenApprovals;
        mapping(address => mapping(address => uint256)) allowance;
        mapping(address => LibMap.Uint32Map) owned;
        LibMap.Uint32Map burnedStack;
        // Even indices: owner aliases. Odd indices: owned indices.
        LibMap.Uint32Map oo;
        mapping(address => AddressData) addressData;
    }

    function _getDN404Storage() internal pure returns (DN404Storage storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            // keccak256(abi.encode(uint256(keccak256("dn404")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := 0x61dd0d320a11019af7688ced18637b1235059a4e8141ed71cfccbe9f2da16600
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         INITIALIZER                        */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    function _initializeDN404(uint96 initialTokenSupply, address initialSupplyOwner, address mirror)
        internal
        virtual
    {
        DN404Storage storage $ = _getDN404Storage();

        if ($.nextTokenId != 0) revert AlreadyInitialized();

        if (mirror == address(0)) revert MirrorAddressIsZero();
        _linkMirrorContract(mirror);

        $.nextTokenId = 1;
        $.mirrorERC721 = mirror;

        if (initialTokenSupply > 0) {
            if (initialSupplyOwner == address(0)) revert TransferToZeroAddress();
            if (initialTokenSupply / _WAD > (_MAX_TOKEN_ID - 1)) revert InvalidTotalNFTSupply();

            $.totalTokenSupply = initialTokenSupply;
            $.addressData[initialSupplyOwner].balance = initialTokenSupply;

            emit Transfer(address(0), initialSupplyOwner, initialTokenSupply);

            _setSkipNFT(initialSupplyOwner, true);
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*               METADATA FUNCTIONS TO OVERRIDE               */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    function name() public view virtual returns (string memory);

    function symbol() public view virtual returns (string memory);

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ERC20 OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual returns (uint256) {
        return uint256(_getDN404Storage().totalTokenSupply);
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
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual {
        DN404Storage storage $ = _getDN404Storage();

        uint256 allowed = $.allowance[from][msg.sender];

        if (allowed != type(uint256).max) {
            $.allowance[from][msg.sender] = allowed - amount;
        }

        _transfer(from, to, amount);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 SHARED TRANSFER OPERATIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    struct _TransferTemps {
        uint256 nftAmountToBurn; // 0x20.
        uint256 nftAmountToMint; // 0x40.
        uint256 toBalance;
        uint256 fromBalance;
        uint256 numBurned;
    }

    struct _PackedLogs {
        uint256[] logs;
        uint256 offset;
    }

    function _packedLogsMalloc(uint256 n) private pure returns (_PackedLogs memory p) {
        /// @solidity memory-safe-assembly
        assembly {
            let logs := add(mload(0x40), 0x40)
            mstore(logs, n)
            let offset := add(0x20, logs)
            mstore(0x40, add(offset, shl(5, n)))
            mstore(p, logs)
            mstore(add(0x20, p), offset)
        }
    }

    function _packedLogsAppend(_PackedLogs memory p, address a, uint256 id, uint256 burnBit)
        private
        pure
    {
        /// @solidity memory-safe-assembly
        assembly {
            let offset := mload(add(0x20, p))
            mstore(offset, or(or(shl(96, a), shl(8, id)), burnBit))
            mstore(add(0x20, p), add(offset, 0x20))
        }
    }

    function _packedLogsSend(_PackedLogs memory p, address mirror) private {
        /// @solidity memory-safe-assembly
        assembly {
            let logs := mload(p)
            let o := sub(logs, 0x40) // Start of calldata to send.
            mstore(o, 0x263c69d6) // `logTransfer(uint256[])`.
            mstore(add(o, 0x20), 0x20) // Offset of `logs` in the calldata to send.
            let n := add(0x44, shl(5, mload(logs))) // Length of calldata to send.
            if iszero(
                and(
                    and(eq(mload(0x00), 1), gt(returndatasize(), 0x1f)),
                    call(gas(), mirror, 0, add(o, 0x1c), n, 0x00, 0x20)
                )
            ) { revert(0x00, 0x00) }
        }
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        _TransferTemps memory t;
        t.numBurned = $.numBurned;

        fromAddressData.balance = uint96(t.fromBalance = fromAddressData.balance - amount);

        unchecked {
            toAddressData.balance = uint96(t.toBalance = toAddressData.balance + amount);

            t.nftAmountToBurn = _zeroFloorSub(fromAddressData.ownedLength, t.fromBalance / _WAD);

            if (!toAddressData.skipNFT) {
                t.nftAmountToMint = _zeroFloorSub(t.toBalance / _WAD, toAddressData.ownedLength);
            }

            _PackedLogs memory packedLogs = _packedLogsMalloc(t.nftAmountToBurn + t.nftAmountToMint);

            if (t.nftAmountToBurn != 0) {
                LibMap.Uint32Map storage fromOwned = $.owned[from];
                uint256 i = fromAddressData.ownedLength;
                uint256 end = i - t.nftAmountToBurn;
                $.totalNFTSupply -= uint32(t.nftAmountToBurn);
                // Burn loop.
                if (i != end) {
                    do {
                        uint256 id = fromOwned.get(--i);
                        $.oo.set(_ownedIndex(id), 0);
                        $.oo.set(_ownershipIndex(id), 0);
                        $.burnedStack.set(t.numBurned++, uint32(id));
                        delete $.tokenApprovals[id];
                        _packedLogsAppend(packedLogs, from, id, 1);
                    } while (i != end);
                    fromAddressData.ownedLength = uint32(i);
                }
            }

            if (t.nftAmountToMint != 0) {
                LibMap.Uint32Map storage toOwned = $.owned[to];
                uint256 i = toAddressData.ownedLength;
                uint256 end = i + t.nftAmountToMint;
                uint256 id = $.nextTokenId;
                uint32 toAlias = _registerAndResolveAlias(toAddressData, to);
                uint256 totalNFTSupply = $.totalNFTSupply;
                totalNFTSupply += t.nftAmountToMint;
                $.totalNFTSupply = uint32(totalNFTSupply);

                // Mint loop.
                if (i != end) {
                    do {
                        if ($.oo.get(_ownershipIndex(id)) != 0) {
                            if (t.numBurned != 0) {
                                id = $.burnedStack.get(--t.numBurned);
                            } else {
                                do {
                                    if (++id > totalNFTSupply) id = 1;
                                } while ($.oo.get(_ownershipIndex(id)) == 0);
                            }
                        }

                        toOwned.set(i, uint32(id));
                        $.oo.set(_ownershipIndex(id), toAlias);
                        $.oo.set(_ownedIndex(id), uint32(i++));
                        _packedLogsAppend(packedLogs, to, id, 0);

                        if (++id > totalNFTSupply) id = 1;
                    } while (i != end);
                    toAddressData.ownedLength = uint32(i);
                    $.nextTokenId = uint32(id);
                }
            }

            if (packedLogs.logs.length != 0) {
                $.numBurned = uint32(t.numBurned);
                _packedLogsSend(packedLogs, $.mirrorERC721);
            }
        }

        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();

        AddressData storage toAddressData = _addressData(to);

        uint256 currentTokenSupply = $.totalTokenSupply;
        currentTokenSupply += amount;
        if (currentTokenSupply / _WAD > (_MAX_TOKEN_ID - 1)) revert InvalidTotalNFTSupply();
        $.totalTokenSupply = uint96(currentTokenSupply);

        unchecked {
            uint256 toBalance = toAddressData.balance + amount;
            toAddressData.balance = uint96(toBalance);

            if (!toAddressData.skipNFT) {
                LibMap.Uint32Map storage toOwned = $.owned[to];
                uint256 toIndex = toAddressData.ownedLength;
                uint256 toMaxNFTs = (toBalance / _WAD);
                if (toMaxNFTs > toIndex) {
                    uint256 nftAmountToMint = toMaxNFTs - toIndex;

                    _PackedLogs memory packedLogs = _packedLogsMalloc(nftAmountToMint);

                    uint256 currentNFTSupply = $.totalNFTSupply;
                    currentNFTSupply += nftAmountToMint;
                    $.totalNFTSupply = uint32(currentNFTSupply);

                    toAddressData.ownedLength = uint32(toMaxNFTs);

                    uint256 id = $.nextTokenId;
                    uint32 toAlias = _registerAndResolveAlias(toAddressData, to);
                    // Mint loop.
                    do {
                        while ($.oo.get(_ownershipIndex(id)) != 0) {
                            if (++id > currentNFTSupply) id = 1;
                        }

                        toOwned.set(toIndex, uint32(id));
                        $.oo.set(_ownershipIndex(id), toAlias);
                        $.oo.set(_ownedIndex(id), uint32(toIndex++));
                        _packedLogsAppend(packedLogs, to, id, 0);

                        // todo: ensure we don't overwrite ownership of early tokens that weren't burned
                        if (++id > currentNFTSupply) id = 1;
                    } while (toIndex != toMaxNFTs);

                    $.nextTokenId = uint32(id);

                    _packedLogsSend(packedLogs, $.mirrorERC721);
                }
            }
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        DN404Storage storage $ = _getDN404Storage();

        AddressData storage fromAddressData = _addressData(from);

        uint256 fromBalance = fromAddressData.balance;
        fromBalance -= amount;
        fromAddressData.balance = uint96(fromBalance);

        uint256 currentTokenSupply = $.totalTokenSupply;
        unchecked {
            currentTokenSupply -= amount;
        }
        $.totalTokenSupply = uint96(currentTokenSupply);

        unchecked {
            LibMap.Uint32Map storage fromOwned = $.owned[from];
            uint256 fromIndex = fromAddressData.ownedLength;
            uint256 fromMaxNFTs = (fromBalance / _WAD);
            if (fromIndex > fromMaxNFTs) {
                uint256 nftAmountToBurn = fromIndex - fromMaxNFTs;
                $.totalNFTSupply -= uint32(nftAmountToBurn);

                _PackedLogs memory packedLogs = _packedLogsMalloc(nftAmountToBurn);

                uint256 fromEnd = fromIndex - nftAmountToBurn;
                // Burn loop.
                if (fromIndex != fromEnd) {
                    do {
                        uint256 id = fromOwned.get(--fromIndex);
                        $.oo.set(_ownedIndex(id), 0);
                        $.oo.set(_ownershipIndex(id), 0);
                        delete $.tokenApprovals[id];
                        _packedLogsAppend(packedLogs, from, id, 1);
                    } while (fromIndex != fromEnd);

                    fromAddressData.ownedLength = uint32(fromIndex);

                    _packedLogsSend(packedLogs, $.mirrorERC721);
                }
            }
        }

        emit Transfer(from, address(0), amount);
    }

    function _transferFromNFT(address from, address to, uint256 id, address msgSender)
        internal
        virtual
    {
        DN404Storage storage $ = _getDN404Storage();

        if (to == address(0)) revert TransferToZeroAddress();

        address owner = $.aliasToAddress[$.oo.get(_ownershipIndex(id))];

        if (from != owner) revert TransferFromIncorrectOwner();

        if (msgSender != from) {
            if (!$.operatorApprovals[from][msgSender]) {
                if (msgSender != $.tokenApprovals[id]) {
                    revert TransferCallerNotOwnerNorApproved();
                }
            }
        }

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        fromAddressData.balance -= uint96(_WAD);

        unchecked {
            toAddressData.balance += uint96(_WAD);

            $.oo.set(_ownershipIndex(id), _registerAndResolveAlias(toAddressData, to));
            delete $.tokenApprovals[id];

            uint256 updatedId = $.owned[from].get(--fromAddressData.ownedLength);
            $.owned[from].set($.oo.get(_ownedIndex(id)), uint32(updatedId));

            uint256 n = toAddressData.ownedLength++;
            $.oo.set(_ownedIndex(updatedId), $.oo.get(_ownedIndex(id)));
            $.owned[to].set(n, uint32(id));
            $.oo.set(_ownedIndex(id), uint32(n));
        }

        emit Transfer(from, to, _WAD);
    }

    function setSkipNFT(bool skipNFT) external {
        _setSkipNFT(msg.sender, skipNFT);
    }

    function _setSkipNFT(address target, bool state) internal {
        _addressData(target).skipNFT = state;
        emit SkipNFTSet(target, state);
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
            addressAlias = ++$.numAliases;
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

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     MIRROR OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    function mirrorERC721() public view returns (address) {
        return _getDN404Storage().mirrorERC721;
    }

    function _totalNFTSupply() internal view virtual returns (uint256) {
        return _getDN404Storage().totalNFTSupply;
    }

    function _balanceOfNFT(address owner) internal view virtual returns (uint256) {
        return _getDN404Storage().addressData[owner].ownedLength;
    }

    function _ownerAt(uint256 id) internal view virtual returns (address) {
        DN404Storage storage $ = _getDN404Storage();
        return $.aliasToAddress[$.oo.get(_ownershipIndex(id))];
    }

    function _ownerOf(uint256 id) internal view virtual returns (address) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return _ownerAt(id);
    }

    function _exists(uint256 id) internal view virtual returns (bool) {
        return _ownerAt(id) != address(0);
    }

    function _getApproved(uint256 id) internal view returns (address) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return _getDN404Storage().tokenApprovals[id];
    }

    function _approveNFT(address spender, uint256 id, address msgSender)
        internal
        returns (address)
    {
        DN404Storage storage $ = _getDN404Storage();

        address owner = $.aliasToAddress[$.oo.get(_ownershipIndex(id))];

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
        _getDN404Storage().operatorApprovals[msgSender][operator] = approved;
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
        // `balanceOfNFT(address)`.
        if (fnSelector == 0xf5b100ea) {
            if (msg.sender != $.mirrorERC721) revert Unauthorized();
            if (msg.data.length < 0x24) revert();

            address owner = address(uint160(_calldataload(0x04)));

            _return(_balanceOfNFT(owner));
        }
        // `totalNFTSupply()`.
        if (fnSelector == 0xe2c79281) {
            if (msg.sender != $.mirrorERC721) revert Unauthorized();
            if (msg.data.length < 0x04) revert();

            _return(_totalNFTSupply());
        }
        // `implementsDN404()`.
        if (fnSelector == 0xb7a94eb8) {
            _return(1);
        }
        _;
    }

    fallback() external payable virtual dn404Fallback {}

    receive() external payable virtual {}

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
}
