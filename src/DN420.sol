// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title DN420
/// @notice DN420 is a fully standard compliant, single-contract, 
/// ERC20 and ERC1155 chimera implementation that mints
/// and burns NFTs based on an account's ERC20 token balance.
///
/// @author vectorized.eth (@optimizoor)
/// @author Quit (@0xQuit)
/// @author Michael Amadi (@AmadiMichaels)
/// @author cygaar (@0xCygaar)
/// @author Thomas (@0xjustadev)
/// @author Harrison (@PopPunkOnChain)
abstract contract DN420 {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @dev Emitted when `target` sets their skipNFT flag to `status`.
    event SkipNFTSet(address indexed target, bool status);

    /// @dev Emitted when `amount` of token `id` is transferred
    /// from `from` to `to` by `operator`.
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    /// @dev Emitted when `amounts` of token `ids` are transferred
    /// from `from` to `to` by `operator`.
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] amounts
    );

    /// @dev Emitted when `owner` enables or disables `operator` to manage all of their tokens.
    event ApprovalForAll(address indexed owner, address indexed operator, bool isApproved);

    /// @dev Emitted when the Uniform Resource Identifier (URI) for token `id`
    /// is updated to `value`. This event is not used in the base contract.
    /// You may need to emit this event depending on your URI logic.
    ///
    /// See: https://eips.ethereum.org/EIPS/eip-1155#metadata
    event URI(string value, uint256 indexed id);

    /// @dev `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    /// @dev `keccak256(bytes("SkipNFTSet(address,bool)"))`.
    uint256 private constant _SKIP_NFT_SET_EVENT_SIGNATURE =
        0xb5a1de456fff688115a4f75380060c23c8532d14ff85f687cc871456d6420393;

    /// @dev `keccak256(bytes("TransferSingle(address,address,address,uint256,uint256)"))`.
    uint256 private constant _TRANSFER_SINGLE_EVENT_SIGNATURE =
        0xc3d58168c5ae7397731d063d5bbf3d657854427343f4c083240f7aacaa2d0f62;

    /// @dev `keccak256(bytes("TransferBatch(address,address,address,uint256[],uint256[])"))`.
    uint256 private constant _TRANSFER_BATCH_EVENT_SIGNATURE =
        0x4a39dc06d4c0dbc64b70af90fd698a233a518aa5d07e595d983b8c0526c8f7fb;

    /// @dev `keccak256(bytes("ApprovalForAll(address,address,bool)"))`.
    uint256 private constant _APPROVAL_FOR_ALL_EVENT_SIGNATURE =
        0x17307eab39ab6107e8899845ad3d59bd9653f200f220920489ca2b5937696c31;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CUSTOM ERRORS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Thrown when attempting to double-initialize the contract.
    error DNAlreadyInitialized();

    /// @dev The contract has not been initialized.
    error DNNotInitialized();

    /// @dev Thrown when attempting to transfer or burn more tokens than sender's balance.
    error InsufficientBalance();

    /// @dev Thrown when a spender attempts to transfer tokens with an insufficient allowance.
    error InsufficientAllowance();

    /// @dev Thrown when minting an amount of tokens that would overflow the max tokens.
    error TotalSupplyOverflow();

    /// @dev The unit cannot be zero.
    error UnitIsZero();

    /// @dev Thrown when attempting to transfer tokens to the zero address.
    error TransferToZeroAddress();

    /// @dev Thrown when setting an NFT token approval
    /// and the caller is not the owner or an approved operator.
    error ApprovalCallerNotOwnerNorApproved();

    /// @dev Thrown when transferring an NFT
    /// and the caller is not the owner or an approved operator.
    error TransferCallerNotOwnerNorApproved();

    /// @dev Thrown when transferring an NFT and the from address is not the current owner.
    error TransferFromIncorrectOwner();

    /// @dev Thrown when checking the owner or approved address for a non-existent NFT.
    error TokenDoesNotExist();

    /// @dev The function selector is not recognized.
    error FnSelectorNotRecognized();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         CONSTANTS                          */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev The flag to denote that the address data is initialized.
    uint8 internal constant _ADDRESS_DATA_INITIALIZED_FLAG = 1 << 0;

    /// @dev The flag to denote that the address should skip NFTs.
    uint8 internal constant _ADDRESS_DATA_SKIP_NFT_FLAG = 1 << 1;

    /// @dev The flag to denote that the address has overridden the default Permit2 allowance.
    uint8 internal constant _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG = 1 << 2;

    /// @dev The canonical Permit2 address.
    /// For signature-based allowance granting for single transaction ERC20 `transferFrom`.
    /// To enable, override `_givePermit2DefaultInfiniteAllowance()`.
    /// [Github](https://github.com/Uniswap/permit2)
    /// [Etherscan](https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3)
    address internal constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Struct containing an address's token data and settings.
    struct AddressData {
        // Auxiliary data.
        uint88 aux;
        // Flags for `initialized` and `skipNFT`.
        uint8 flags;
        // The inclusive upper bound on the NFT IDs owned.
        uint32 ownedUpTo;
        // The number of NFT tokens.
        uint32 ownedCount;
        // The token balance in wei.
        uint96 balance;
    }

    /// @dev A bitmap in storage.
    struct Bitmap {
        uint256 spacer;
    }

    /// @dev A struct to wrap a uint256 in storage.
    struct Uint256Ref {
        uint256 value;
    }

    /// @dev A mapping of an address pair to a Uint256Ref.
    struct AddressPairToUint256RefMap {
        uint256 spacer;
    }

    /// @dev Struct containing the base token contract storage.
    struct DN420Storage {
        // Next NFT ID to assign for a mint.
        uint32 nextTokenId;
        // Total supply of tokens.
        uint96 totalSupply;
        // Mapping of user operator approvals for NFTs.
        AddressPairToUint256RefMap operatorApprovals;
        // Bitmap of whether a NFT ID exists.
        Bitmap exists;
        // Mapping of user allowances for ERC20 spenders.
        AddressPairToUint256RefMap allowance;
        // Bitmap of NFT IDs owned by an address.
        mapping(address => Bitmap) owned;
        // Mapping of user account AddressData.
        mapping(address => AddressData) addressData;
    }

    /// @dev Returns a storage pointer for DN420Storage.
    function _getDN420Storage() internal pure virtual returns (DN420Storage storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            // `uint72(bytes9(keccak256("DN420_STORAGE")))`.
            $.slot := 0xb6dffd38a260769cb2 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         INITIALIZER                        */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the DN420 contract with an
    /// `initialTokenSupply` and `initialTokenOwner`.
    function _initializeDN420(
        uint256 initialTokenSupply,
        address initialSupplyOwner
    ) internal virtual {
        DN420Storage storage $ = _getDN420Storage();

        if (_unit() == 0) revert UnitIsZero();
        
        $.nextTokenId = 1;

        if (initialTokenSupply != 0) {
            if (initialSupplyOwner == address(0)) revert TransferToZeroAddress();
            if (_totalSupplyOverflows(initialTokenSupply)) revert TotalSupplyOverflow();

            $.totalSupply = uint96(initialTokenSupply);
            AddressData storage initialOwnerAddressData = _addressData(initialSupplyOwner);
            initialOwnerAddressData.balance = uint96(initialTokenSupply);

            /// @solidity memory-safe-assembly
            assembly {
                // Emit the {Transfer} event.
                mstore(0x00, initialTokenSupply)
                log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, initialSupplyOwner)))
            }

            _setSkipNFT(initialSupplyOwner, true);
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*               BASE UNIT FUNCTION TO OVERRIDE               */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Amount of token balance that is equal to one NFT.
    function _unit() internal view virtual returns (uint256) {
        return 10 ** 18;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*               METADATA FUNCTIONS TO OVERRIDE               */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the name of the token.
    function name() public view virtual returns (string memory);

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual returns (string memory);

    /// @dev Returns the URI for token `id`.
    ///
    /// You can either return the same templated URI for all token IDs,
    /// (e.g. "https://example.com/api/{id}.json"),
    /// or return a unique URI for each `id`.
    ///
    /// See: https://eips.ethereum.org/EIPS/eip-1155#metadata
    function uri(uint256 id) public view virtual returns (string memory);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                       CONFIGURABLES                        */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns if direct NFT transfers should be used during ERC20 transfers
    /// whenever possible, instead of burning and re-minting.
    function _useDirectTransfersIfPossible() internal view virtual returns (bool) {
        return true;
    }

    /// @dev Hook that is called after any NFT token transfers, including minting and burning.
    function _afterNFTTransfer(address from, address to, uint256 id) internal virtual {}

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ERC20 OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the decimals places of the token. Always 18.
    function decimals() public pure returns (uint8) {
        return 18;
    }

    /// @dev Returns the amount of tokens in existence.
    function totalSupply() public view virtual returns (uint256) {
        return uint256(_getDN420Storage().totalSupply);
    }

    /// @dev Returns the amount of tokens owned by `owner`.
    function balanceOf(address owner) public view virtual returns (uint256) {
        return _getDN420Storage().addressData[owner].balance;
    }

    /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender) public view returns (uint256) {
        if (_givePermit2DefaultInfiniteAllowance() && spender == _PERMIT2) {
            uint8 flags = _getDN420Storage().addressData[owner].flags;
            if (flags & _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG == 0) return type(uint256).max;
        }
        return _ref(_getDN420Storage().allowance, owner, spender).value;
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @dev Transfer `amount` tokens from the caller to `to`.
    ///
    /// Will burn sender NFTs if balance after transfer is less than
    /// the amount required to support the current NFT balance.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    ///
    /// Emits a {Transfer} event.
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    /// @dev Transfers `amount` tokens from `from` to `to`.
    ///
    /// Note: Does not update the allowance if it is the maximum uint256 value.
    ///
    /// Will burn sender NFTs if balance after transfer is less than
    /// the amount required to support the current NFT balance.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    /// - The caller must have at least `amount` of allowance to transfer the tokens of `from`.
    ///
    /// Emits a {Transfer} event.
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        Uint256Ref storage a = _ref(_getDN420Storage().allowance, from, msg.sender);

        uint256 allowed = _givePermit2DefaultInfiniteAllowance() && msg.sender == _PERMIT2
            && (_getDN420Storage().addressData[from].flags & _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG) == 0
            ? type(uint256).max
            : a.value;

        if (allowed != type(uint256).max) {
            if (amount > allowed) revert InsufficientAllowance();
            unchecked {
                a.value = allowed - amount;
            }
        }
        _transfer(from, to, amount);
        return true;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          PERMIT2                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Whether Permit2 has infinite allowances by default for all owners.
    /// For signature-based allowance granting for single transaction ERC20 `transferFrom`.
    /// To enable, override this function to return true.
    function _givePermit2DefaultInfiniteAllowance() internal view virtual returns (bool) {
        return false;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                  INTERNAL MINT FUNCTIONS                   */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Mints `amount` tokens to `to`, increasing the total supply.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is set to false.
    ///
    /// Emits a {Transfer} event.
    function _mint(address to, uint256 amount) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        AddressData storage toAddressData = _addressData(to);
        DN420Storage storage $ = _getDN420Storage();
        if ($.nextTokenId == 0) revert DNNotInitialized();

        uint256 toEnd;
        unchecked {
            uint256 toBalance = uint256(toAddressData.balance) + amount;
            toAddressData.balance = uint96(toBalance);
            toEnd = toBalance / _unit();
        }
        uint256 maxId;
        unchecked {
            uint256 totalSupply_ = uint256($.totalSupply) + amount;
            $.totalSupply = uint96(totalSupply_);
            uint256 overflows = _toUint(_totalSupplyOverflows(totalSupply_));
            if (overflows | _toUint(totalSupply_ < amount) != 0) revert TotalSupplyOverflow();
            maxId = totalSupply_ / _unit();
        }
        unchecked {
            if (toAddressData.flags & _ADDRESS_DATA_SKIP_NFT_FLAG == 0) {
                uint256 numNFTMints = _zeroFloorSub(toEnd, toAddressData.ownedCount);
                if (numNFTMints != 0) {
                    _DNBatchLogs memory p = _batchLogsMalloc(numNFTMints);
                    Bitmap storage toOwned = $.owned[to];
                    uint256 ownedUpTo = toAddressData.ownedUpTo;
                    uint256 nextTokenId = _wrapNFTId($.nextTokenId, maxId);
                    // Mint loop.
                    do {
                        uint256 id = nextTokenId;
                        while (_get($.exists, id)) {
                            id = _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId);
                        }
                        nextTokenId = _wrapNFTId(id + 1, maxId);
                        _set($.exists, id, true);
                        _set(toOwned, id, true);
                        ownedUpTo = _max(ownedUpTo, id);
                        _batchLogsAppend(p, id);
                        _afterNFTTransfer(address(0), to, id);
                    } while (--numNFTMints != 0);

                    toAddressData.ownedUpTo = uint32(ownedUpTo);
                    toAddressData.ownedCount = uint32(toEnd);
                    $.nextTokenId = uint32(nextTokenId);
                    _batchLogsEmit(p, address(0), to);
                }
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, to)))
        }
    }

    /// @dev Mints `amount` tokens to `to`, increasing the total supply.
    /// This variant mints NFT tokens starting from ID `preTotalSupply / _unit() + 1`.
    /// This variant will not touch the `burnedPool` and `nextTokenId`.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is set to false.
    ///
    /// Emits a {Transfer} event.
    function _mintNext(address to, uint256 amount) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        AddressData storage toAddressData = _addressData(to);
        DN420Storage storage $ = _getDN420Storage();
        if ($.nextTokenId == 0) revert DNNotInitialized();

        uint256 toEnd;
        unchecked {
            uint256 toBalance = uint256(toAddressData.balance) + amount;
            toAddressData.balance = uint96(toBalance);
            toEnd = toBalance / _unit();
        }
        uint256 startId;
        uint256 maxId;
        unchecked {
            uint256 preTotalSupply = uint256($.totalSupply);
            startId = preTotalSupply / _unit() + 1;
            uint256 totalSupply_ = uint256(preTotalSupply) + amount;
            $.totalSupply = uint96(totalSupply_);
            uint256 overflows = _toUint(_totalSupplyOverflows(totalSupply_));
            if (overflows | _toUint(totalSupply_ < amount) != 0) revert TotalSupplyOverflow();
            maxId = totalSupply_ / _unit();
        }
        unchecked {
            if (toAddressData.flags & _ADDRESS_DATA_SKIP_NFT_FLAG == 0) {
                uint256 numNFTMints = _zeroFloorSub(toEnd, toAddressData.ownedCount);
                if (numNFTMints != 0) {
                    _DNBatchLogs memory p = _batchLogsMalloc(numNFTMints);
                    Bitmap storage toOwned = $.owned[to];
                    uint256 ownedUpTo = toAddressData.ownedUpTo;
                    // Mint loop.
                    do {
                        uint256 id = startId;
                        while (_get($.exists, id)) {
                            id = _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId);
                        }
                        startId = _wrapNFTId(id + 1, maxId);
                        _set($.exists, id, true);
                        _set(toOwned, id, true);
                        ownedUpTo = _max(ownedUpTo, id);
                        _batchLogsAppend(p, id);
                        _afterNFTTransfer(address(0), to, id);
                    } while (--numNFTMints != 0);

                    toAddressData.ownedUpTo = uint32(ownedUpTo);
                    toAddressData.ownedCount = uint32(toEnd);
                    _batchLogsEmit(p, address(0), to);
                }
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, to)))
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                  INTERNAL BURN FUNCTIONS                   */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Burns `amount` tokens from `from`, reducing the total supply.
    ///
    /// Will burn sender NFTs if balance after transfer is less than
    /// the amount required to support the current NFT balance.
    ///
    /// Emits a {Transfer} event.
    function _burn(address from, uint256 amount) internal virtual {
        AddressData storage fromAddressData = _addressData(from);
        DN420Storage storage $ = _getDN420Storage();
        if ($.nextTokenId == 0) revert DNNotInitialized();

        uint256 fromBalance = fromAddressData.balance;
        if (amount > fromBalance) revert InsufficientBalance();

        unchecked {
            fromAddressData.balance = uint96(fromBalance -= amount);
            uint256 totalSupply_ = uint256($.totalSupply) - amount;
            $.totalSupply = uint96(totalSupply_);

            Bitmap storage fromOwned = $.owned[from];
            uint256 fromIndex = fromAddressData.ownedCount;
            uint256 numNFTBurns = _zeroFloorSub(fromIndex, fromBalance / _unit());

            if (numNFTBurns != 0) {
                _DNBatchLogs memory p = _batchLogsMalloc(numNFTBurns);
                fromAddressData.ownedCount = uint32(fromIndex - numNFTBurns);
                uint256 id = fromAddressData.ownedUpTo;
                // Burn loop.
                do {
                    id = _findLastSet(fromOwned, id);
                    _set(fromOwned, id, false);
                    _set($.exists, id, false);
                    _afterNFTTransfer(from, address(0), id);
                    _batchLogsAppend(p, id);
                } while (--numNFTBurns != 0);

                fromAddressData.ownedUpTo = uint32(id);
                _batchLogsEmit(p, from, address(0));
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), 0)
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                INTERNAL TRANSFER FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Moves `amount` of tokens from `from` to `to`.
    ///
    /// Will burn sender NFTs if balance after transfer is less than
    /// the amount required to support the current NFT balance.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///
    /// Emits a {Transfer} event.
    function _transfer(address from, address to, uint256 amount) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);
        DN420Storage storage $ = _getDN420Storage();
        if ($.nextTokenId == 0) revert DNNotInitialized();

        _DNTransferTemps memory t;
        t.fromOwnedCount = fromAddressData.ownedCount;
        t.toOwnedCount = toAddressData.ownedCount;

        if (amount > (t.fromBalance = fromAddressData.balance)) revert InsufficientBalance();

        unchecked {
            fromAddressData.balance = uint96(t.fromBalance -= amount);
            toAddressData.balance = uint96(t.toBalance = uint256(toAddressData.balance) + amount);

            t.numNFTBurns = _zeroFloorSub(t.fromOwnedCount, t.fromBalance / _unit());

            if (toAddressData.flags & _ADDRESS_DATA_SKIP_NFT_FLAG == 0) {
                if (from == to) t.toOwnedCount = t.fromOwnedCount - t.numNFTBurns;
                t.numNFTMints = _zeroFloorSub(t.toBalance / _unit(), t.toOwnedCount);
            }

            while (_useDirectTransfersIfPossible()) {
                uint256 n = _min(t.fromOwnedCount, _min(t.numNFTBurns, t.numNFTMints));
                if (n == 0) break;
                t.numNFTBurns -= n;
                t.numNFTMints -= n;
                if (from == to) {
                    t.toOwnedCount += n;
                    break;
                }
                _DNBatchLogs memory p = _batchLogsMalloc(n);
                Bitmap storage fromOwned = $.owned[from];
                Bitmap storage toOwned = $.owned[to];
                
                uint256 id = fromAddressData.ownedUpTo;
                fromAddressData.ownedCount = uint32(t.fromOwnedCount -= n);
                toAddressData.ownedUpTo = uint32(_max(toAddressData.ownedUpTo, id));
                toAddressData.ownedCount = uint32(t.toOwnedCount += n);
                // Direct transfer loop.
                do {
                    id = _findLastSet(fromOwned, id);
                    _set(fromOwned, id, false);
                    _set(toOwned, id, true);
                    _batchLogsAppend(p, id);
                    _afterNFTTransfer(from, to, id);
                } while (--n != 0);

                fromAddressData.ownedUpTo = uint32(id);
                _batchLogsEmit(p, from, to);
                break;
            }

            if (t.numNFTBurns != 0) {
                uint256 n = t.numNFTBurns;
                _DNBatchLogs memory p = _batchLogsMalloc(n);
                Bitmap storage fromOwned = $.owned[from];
                fromAddressData.ownedCount = uint32(t.fromOwnedCount -= n);
                uint256 id = fromAddressData.ownedUpTo;
                // Burn loop.
                do {
                    id = _findLastSet(fromOwned, id);
                    _set(fromOwned, id, false);
                    _set($.exists, id, false);
                    _batchLogsAppend(p, id);                    
                    _afterNFTTransfer(from, address(0), id);
                } while (--n != 0);

                fromAddressData.ownedUpTo = uint32(id);
                _batchLogsEmit(p, from, address(0));
            }

            if (t.numNFTMints != 0) {
                uint256 n = t.numNFTMints;
                _DNBatchLogs memory p = _batchLogsMalloc(n);
                Bitmap storage toOwned = $.owned[to];
                toAddressData.ownedCount = uint32(t.toOwnedCount += n);
                uint256 maxId = $.totalSupply / _unit();
                uint256 nextTokenId = _wrapNFTId($.nextTokenId, maxId);
                uint256 ownedUpTo = toAddressData.ownedUpTo;
                // Mint loop.
                do {
                    uint256 id = nextTokenId;
                    while (_get($.exists, id)) {
                        id = _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId);
                    }
                    nextTokenId = _wrapNFTId(id + 1, maxId);
                    _set($.exists, id, true);
                    _set(toOwned, id, true);
                    ownedUpTo = _max(ownedUpTo, id);
                    _batchLogsAppend(p, id);
                    _afterNFTTransfer(address(0), to, id);
                } while (--n != 0);

                toAddressData.ownedUpTo = uint32(ownedUpTo);
                $.nextTokenId = uint32(nextTokenId);
                _batchLogsEmit(p, address(0), to);
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            // forgefmt: disable-next-item
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), shr(96, shl(96, to)))
        }
    }

    /// @dev Transfers token `id` from `from` to `to`.
    ///
    /// Requirements:
    ///
    /// - Call must originate from the mirror contract.
    /// - Token `id` must exist.
    /// - `from` must be the owner of the token.
    /// - `to` cannot be the zero address.
    ///   `msgSender` must be the owner of the token, or be approved to manage the token.
    ///
    /// Emits a {Transfer} event.
    function _transferFromNFT(address from, address to, uint256 id)
        internal
        virtual
    {
        if (to == address(0)) revert TransferToZeroAddress();

        DN420Storage storage $ = _getDN420Storage();
        if ($.nextTokenId == 0) revert DNNotInitialized();

        Bitmap storage fromOwned = $.owned[from];
        Bitmap storage toOwned = $.owned[to];

        if (!_get(fromOwned, id)) {
            revert TransferFromIncorrectOwner();
        }

        if (msg.sender != from) {
            if (_ref($.operatorApprovals, from, msg.sender).value == 0) {
                revert TransferCallerNotOwnerNorApproved();
            }
        }

        AddressData storage fromAddressData = _addressData(from);
        AddressData storage toAddressData = _addressData(to);

        uint256 unit = _unit();

        unchecked {
            uint256 fromBalance = fromAddressData.balance;
            if (unit > fromBalance) revert InsufficientBalance();
            fromAddressData.balance = uint96(fromBalance - unit);
            toAddressData.balance += uint96(unit);

            _set(fromOwned, id, false);
            _set(toOwned, id, true);

            --fromAddressData.ownedCount;
            ++toAddressData.ownedCount;
            toAddressData.ownedUpTo = uint32(_max(toAddressData.ownedUpTo, id));
        }
        _afterNFTTransfer(from, to, id);
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, unit)
            // forgefmt: disable-next-item
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), shr(96, shl(96, to)))
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 INTERNAL APPROVE FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets `amount` as the allowance of `spender` over the tokens of `owner`.
    ///
    /// Emits a {Approval} event.
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        if (_givePermit2DefaultInfiniteAllowance() && spender == _PERMIT2) {
            _getDN420Storage().addressData[owner].flags |= _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG;
        }
        _ref(_getDN420Storage().allowance, owner, spender).value = amount;
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Approval} event.
            mstore(0x00, amount)
            // forgefmt: disable-next-item
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, shr(96, shl(96, owner)), shr(96, shl(96, spender)))
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 DATA HITCHHIKING FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the auxiliary data for `owner`.
    /// Minting, transferring, burning the tokens of `owner` will not change the auxiliary data.
    /// Auxiliary data can be set for any address, even if it does not have any tokens.
    function _getAux(address owner) internal view virtual returns (uint88) {
        return _getDN420Storage().addressData[owner].aux;
    }

    /// @dev Set the auxiliary data for `owner` to `value`.
    /// Minting, transferring, burning the tokens of `owner` will not change the auxiliary data.
    /// Auxiliary data can be set for any address, even if it does not have any tokens.
    function _setAux(address owner, uint88 value) internal virtual {
        _getDN420Storage().addressData[owner].aux = value;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     SKIP NFT FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns true if minting and transferring ERC20s to `owner` will skip minting NFTs.
    /// Returns false otherwise.
    function getSkipNFT(address owner) public view virtual returns (bool) {
        AddressData storage d = _getDN420Storage().addressData[owner];
        if (d.flags & _ADDRESS_DATA_INITIALIZED_FLAG == 0) return _hasCode(owner);
        return d.flags & _ADDRESS_DATA_SKIP_NFT_FLAG != 0;
    }

    /// @dev Sets the caller's skipNFT flag to `skipNFT`. Returns true.
    ///
    /// Emits a {SkipNFTSet} event.
    function setSkipNFT(bool skipNFT) public virtual returns (bool) {
        _setSkipNFT(msg.sender, skipNFT);
        return true;
    }

    /// @dev Internal function to set account `owner` skipNFT flag to `state`
    ///
    /// Initializes account `owner` AddressData if it is not currently initialized.
    ///
    /// Emits a {SkipNFTSet} event.
    function _setSkipNFT(address owner, bool state) internal virtual {
        AddressData storage d = _addressData(owner);
        if ((d.flags & _ADDRESS_DATA_SKIP_NFT_FLAG != 0) != state) {
            d.flags ^= _ADDRESS_DATA_SKIP_NFT_FLAG;
        }
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, iszero(iszero(state)))
            log2(0x00, 0x20, _SKIP_NFT_SET_EVENT_SIGNATURE, shr(96, shl(96, owner)))
        }
    }

    /// @dev Returns a storage data pointer for account `owner` AddressData
    ///
    /// Initializes account `owner` AddressData if it is not currently initialized.
    function _addressData(address owner) internal virtual returns (AddressData storage d) {
        d = _getDN420Storage().addressData[owner];
        unchecked {
            if (d.flags & _ADDRESS_DATA_INITIALIZED_FLAG == 0) {
                uint256 skipNFT = _toUint(_hasCode(owner)) * _ADDRESS_DATA_SKIP_NFT_FLAG;
                d.flags = uint8(skipNFT | _ADDRESS_DATA_INITIALIZED_FLAG);
            }
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     ERC1155 OPERATIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns `owner` NFT balance.
    function _balanceOfNFT(address owner) internal view virtual returns (uint256) {
        return _getDN420Storage().addressData[owner].ownedCount;
    }

    /// @dev Returns if token `id` exists.
    function _exists(uint256 id) internal view virtual returns (bool) {
        return _get(_getDN420Storage().exists, id);
    }

    /// @dev Returns the NFT IDs of `owner` in range `[begin, end)`.
    /// Optimized for smaller bytecode size, as this function is intended for off-chain calling.
    function _findOwnedIds(address owner, uint256 begin, uint256 end)
        internal
        view
        virtual
        returns (uint256[] memory ids)
    {
        unchecked {
            DN420Storage storage $ = _getDN420Storage();
            Bitmap storage owned = $.owned[owner];
            end = _min(uint256($.addressData[owner].ownedUpTo) + 1, end);
            /// @solidity memory-safe-assembly
            assembly {
                ids := mload(0x40)
                let n := 0
                let s := shl(96, owned.slot)
                for { let id := begin } lt(id, end) { id := add(1, id) } {
                    if and(1, shr(and(0xff, id), sload(add(s, shr(8, id))))) {
                        mstore(add(add(ids, 0x20), shl(5, n)), id)
                        n := add(1, n)
                    }
                }
                mstore(ids, n)
                mstore(0x40, add(shl(5, n), add(0x20, ids)))
            }
        }
    }

    // /// @dev Fallback modifier to dispatch calls from the mirror NFT contract
    // /// to internal functions in this contract.
    // modifier dn404Fallback() virtual {
    //     DN404Storage storage $ = _getDN420Storage();

    //     uint256 fnSelector = _calldataload(0x00) >> 224;
    //     address mirror = $.mirrorERC721;

    //     // `transferFromNFT(address,address,uint256,address)`.
    //     if (fnSelector == 0xe5eb36c8) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         _transferFromNFT(
    //             address(uint160(_calldataload(0x04))), // `from`.
    //             address(uint160(_calldataload(0x24))), // `to`.
    //             _calldataload(0x44), // `id`.
    //             address(uint160(_calldataload(0x64))) // `msgSender`.
    //         );
    //         _return(1);
    //     }
    //     // `setApprovalForAll(address,bool,address)`.
    //     if (fnSelector == 0x813500fc) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         _setApprovalForAll(
    //             address(uint160(_calldataload(0x04))), // `spender`.
    //             _calldataload(0x24) != 0, // `status`.
    //             address(uint160(_calldataload(0x44))) // `msgSender`.
    //         );
    //         _return(1);
    //     }
    //     // `isApprovedForAll(address,address)`.
    //     if (fnSelector == 0xe985e9c5) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         Uint256Ref storage ref = _ref(
    //             $.operatorApprovals,
    //             address(uint160(_calldataload(0x04))), // `owner`.
    //             address(uint160(_calldataload(0x24))) // `operator`.
    //         );
    //         _return(ref.value);
    //     }
    //     // `ownerOf(uint256)`.
    //     if (fnSelector == 0x6352211e) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         _return(uint160(_ownerOf(_calldataload(0x04))));
    //     }
    //     // `ownerAt(uint256)`.
    //     if (fnSelector == 0x24359879) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         _return(uint160(_ownerAt(_calldataload(0x04))));
    //     }
    //     // `approveNFT(address,uint256,address)`.
    //     if (fnSelector == 0xd10b6e0c) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         address owner = _approveNFT(
    //             address(uint160(_calldataload(0x04))), // `spender`.
    //             _calldataload(0x24), // `id`.
    //             address(uint160(_calldataload(0x44))) // `msgSender`.
    //         );
    //         _return(uint160(owner));
    //     }
    //     // `getApproved(uint256)`.
    //     if (fnSelector == 0x081812fc) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         _return(uint160(_getApproved(_calldataload(0x04))));
    //     }
    //     // `balanceOfNFT(address)`.
    //     if (fnSelector == 0xf5b100ea) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         _return(_balanceOfNFT(address(uint160(_calldataload(0x04)))));
    //     }
    //     // `totalNFTSupply()`.
    //     if (fnSelector == 0xe2c79281) {
    //         if (msg.sender != mirror) revert SenderNotMirror();
    //         _return(_totalNFTSupply());
    //     }
    //     // `implementsDN404()`.
    //     if (fnSelector == 0xb7a94eb8) {
    //         _return(1);
    //     }
    //     _;
    // }

    // /// @dev Fallback function for calls from mirror NFT contract.
    // /// Override this if you need to implement your custom
    // /// fallback with utilities like Solady's `LibZip.cdFallback()`.
    // /// And always remember to always wrap the fallback with `dn404Fallback`.
    // fallback() external payable virtual dn404Fallback {
    //     revert FnSelectorNotRecognized(); // Not mandatory. Just for quality of life.
    // }

    // /// @dev This is to silence the compiler warning.
    // /// Override and remove the revert if you want your contract to receive ETH via receive.
    // receive() external payable virtual {
    //     if (msg.value != 0) revert();
    // }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 INTERNAL / PRIVATE HELPERS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the boolean value of the bit at `index` in `bitmap`.
    function _get(Bitmap storage bitmap, uint256 index) internal view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, bitmap.slot), shr(8, index)) // Storage slot.
            result := and(1, shr(and(0xff, index), sload(s)))
        }
    }

    /// @dev Updates the bit at `index` in `bitmap` to `value`.
    function _set(Bitmap storage bitmap, uint256 index, bool value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, bitmap.slot), shr(8, index)) // Storage slot.
            let o := and(0xff, index) // Storage slot offset (bits).
            sstore(s, or(and(sload(s), not(shl(o, 1))), shl(o, iszero(iszero(value)))))
        }
    }

    /// @dev Returns the index of the least significant unset bit in `[begin..upTo]`.
    /// If no set bit is found, returns `type(uint256).max`.
    function _findFirstUnset(Bitmap storage bitmap, uint256 begin, uint256 upTo)
        internal
        view
        returns (uint256 unsetBitIndex)
    {
        /// @solidity memory-safe-assembly
        assembly {
            unsetBitIndex := not(0) // Initialize to `type(uint256).max`.
            let s := shl(96, bitmap.slot) // Storage offset of the bitmap.
            let bucket := add(s, shr(8, begin))
            let lastBucket := add(s, shr(8, upTo))
            let negBits := shl(and(0xff, begin), shr(and(0xff, begin), not(sload(bucket))))
            if iszero(negBits) {
                for {} 1 {} {
                    bucket := add(bucket, 1)
                    negBits := not(sload(bucket))
                    if or(negBits, gt(bucket, lastBucket)) { break }
                }
                if gt(bucket, lastBucket) {
                    negBits := shr(and(0xff, not(upTo)), shl(and(0xff, not(upTo)), negBits))
                }
            }
            if negBits {
                // Find-first-set routine.
                let b := and(negBits, add(not(negBits), 1)) // Isolate the least significant bit.
                let r := shl(7, lt(0xffffffffffffffffffffffffffffffff, b))
                r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, b))))
                r := or(r, shl(5, lt(0xffffffff, shr(r, b))))
                // For the remaining 32 bits, use a De Bruijn lookup.
                // forgefmt: disable-next-item
                r := or(r, byte(and(div(0xd76453e0, shr(r, b)), 0x1f),
                    0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
                r := or(shl(8, sub(bucket, s)), r)
                unsetBitIndex := or(r, sub(0, or(gt(r, upTo), lt(r, begin))))
            }
        }
    }

    /// @dev Returns the index of the most significant set bit in `[0..upTo]`.
    /// If no set bit is found, returns `type(uint256).max`.
    function _findLastSet(Bitmap storage bitmap, uint256 upTo) internal view returns (uint256 setBitIndex) {
        /// @solidity memory-safe-assembly
        assembly {
            setBitIndex := not(0) // Initialize to `type(uint256).max`.
            let s := shl(96, bitmap.slot) // Storage offset of the bitmap.
            let bucket := add(s, shr(8, upTo))
            let bits := shr(and(0xff, not(upTo)), shl(and(0xff, not(upTo)), sload(bucket)))
            if iszero(or(bits, eq(bucket, s))) {
                for {} 1 {} {
                    bucket := add(bucket, setBitIndex) // `sub(bucket, 1)`.
                    mstore(0x00, bucket)
                    bits := sload(bucket)
                    if or(bits, eq(bucket, s)) { break }
                }
            }
            if bits {
                // Find-last-set routine.
                let r := shl(7, lt(0xffffffffffffffffffffffffffffffff, bits))
                r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, bits))))
                r := or(r, shl(5, lt(0xffffffff, shr(r, bits))))
                r := or(r, shl(4, lt(0xffff, shr(r, bits))))
                r := or(r, shl(3, lt(0xff, shr(r, bits))))
                // forgefmt: disable-next-item
                r := or(r, byte(and(0x1f, shr(shr(r, bits), 0x8421084210842108cc6318c6db6d54be)),
                    0x0706060506020504060203020504030106050205030304010505030400000000))
                r := or(shl(8, sub(bucket, s)), r)
                setBitIndex := or(r, sub(0, gt(r, upTo)))
            }
        }
    }

    /// @dev Returns a storage reference to the value at (`a0`, `a1`) in `map`.
    function _ref(AddressPairToUint256RefMap storage map, address a0, address a1)
        internal
        pure
        returns (Uint256Ref storage ref)
    {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x28, a1)
            mstore(0x14, a0)
            mstore(0x00, map.slot)
            ref.slot := keccak256(0x00, 0x48)
            // Clear the part of the free memory pointer that was overwritten.
            mstore(0x28, 0x00)
        }
    }

    /// @dev Wraps the NFT ID.
    function _wrapNFTId(uint256 id, uint256 maxId) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := or(mul(iszero(gt(id, maxId)), id), gt(id, maxId))
        }
    }

    /// @dev Returns `id > type(uint32).max ? 0 : id`.
    function _restrictNFTId(uint256 id) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mul(id, lt(id, 0x100000000))
        }
    }

    /// @dev Returns whether `amount` is a valid `totalSupply`.
    function _totalSupplyOverflows(uint256 amount) internal view returns (bool result) {
        uint256 unit = _unit();
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(or(shr(96, amount), lt(0xfffffffe, div(amount, unit)))))
        }
    }

    /// @dev Returns `max(0, x - y)`.
    function _zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    /// @dev Returns `x < y ? x : y`.
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }

    /// @dev Returns `x > y ? x : y`.
    function _max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := xor(x, mul(xor(x, y), gt(y, x)))
        }
    }

    /// @dev Returns `b ? 1 : 0`.
    function _toUint(bool b) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(b))
        }
    }

    /// @dev Struct containing the data to be emitted in a {TransferBatch} event.
    struct _DNBatchLogs {
        uint256 offset;
        uint256[] ids;
    }

    function _batchLogsMalloc(uint256 n) private pure returns (_DNBatchLogs memory p) {
        /// @solidity memory-safe-assembly
        assembly {
            let ids := mload(0x40)
            let offset := add(ids, 0x20)
            mstore(ids, n)
            mstore(0x40, add(offset, shl(5, n)))
            mstore(p, offset)
            mstore(add(p, 0x20), ids)
        }
    }

    function _batchLogsAppend(_DNBatchLogs memory p, uint256 id) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            let offset := mload(p)
            mstore(offset, id)
            mstore(p, add(offset, 0x20))
        }
    }

    function _batchLogsEmit(_DNBatchLogs memory p, address from, address to) private {
        /// @solidity memory-safe-assembly
        assembly {
            let ids := mload(add(0x20, p))
            let m := mload(0x40)
            mstore(m, 0x40)
            let n := add(0x20, shl(5, mload(ids)))
            let o := add(m, 0x40)
            pop(staticcall(gas(), 4, ids, n, o, n)) // Copy the `ids`.
            mstore(add(m, 0x20), add(0x40, returndatasize()))
            o := add(o, returndatasize())
            // Store the length of `amounts`.
            mstore(o, mload(ids))
            let end := add(o, returndatasize())
            for { o := add(o, 0x20) } iszero(eq(o, end)) { o := add(0x20, o) } { mstore(o, 1) }
            // Emit a {TransferBatch} event.
            log4(m, sub(o, m), _TRANSFER_BATCH_EVENT_SIGNATURE, caller(), shr(96, shl(96, from)), shr(96, shl(96, to)))
        }
    }

    /// @dev Struct of temporary variables for transfers.
    struct _DNTransferTemps {
        uint256 numNFTBurns;
        uint256 numNFTMints;
        uint256 fromBalance;
        uint256 toBalance;
        uint256 fromOwnedCount;
        uint256 toOwnedCount;
    }

    /// @dev Returns if `a` has bytecode of non-zero length.
    function _hasCode(address a) private view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := extcodesize(a) // Can handle dirty upper bits.
        }
    }

    /// @dev Returns the calldata value at `offset`.
    function _calldataload(uint256 offset) private pure returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := calldataload(offset)
        }
    }

    /// @dev Executes a return opcode to return `x` and end the current call frame.
    function _return(uint256 x) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, x)
            return(0x00, 0x20)
        }
    }
}
