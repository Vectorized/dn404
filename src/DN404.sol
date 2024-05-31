// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title DN404
/// @notice DN404 is a hybrid ERC20 and ERC721 implementation that mints
/// and burns NFTs based on an account's ERC20 token balance.
///
/// @author vectorized.eth (@optimizoor)
/// @author Quit (@0xQuit)
/// @author Michael Amadi (@AmadiMichaels)
/// @author cygaar (@0xCygaar)
/// @author Thomas (@0xjustadev)
/// @author Harrison (@PopPunkOnChain)
///
/// @dev Note:
/// - The ERC721 data is stored in this base DN404 contract, however a
///   DN404Mirror contract ***MUST*** be deployed and linked during
///   initialization.
/// - For ERC20 transfers, the most recently acquired NFT will be burned / transferred out first.
/// - A unit worth of ERC20 tokens equates to a deed to one NFT token.
///   The skip NFT status determines if this deed is automatically exercised.
///   An account can configure their skip NFT status.
///     * If `getSkipNFT(owner) == true`, ERC20 mints / transfers to `owner`
///       will NOT trigger NFT mints / transfers to `owner` (i.e. deeds are left unexercised).
///     * If `getSkipNFT(owner) == false`, ERC20 mints / transfers to `owner`
///       will trigger NFT mints / transfers to `owner`, until the NFT balance of `owner`
///       is equal to its ERC20 balance divided by the unit (rounded down).
/// - Invariant: `mirror.balanceOf(owner) <= base.balanceOf(owner) / _unit()`.
/// - The gas costs for automatic minting / transferring / burning of NFTs is O(n).
///   This can exceed the block gas limit.
///   Applications and users may need to break up large transfers into a few transactions.
/// - This implementation does not support "safe" transfers for automatic NFT transfers.
/// - The ERC20 token allowances and ERC721 token / operator approvals are separate.
/// - For MEV safety, users should NOT have concurrently open orders for the ERC20 and ERC721.
abstract contract DN404 {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @dev Emitted when `owner` sets their skipNFT flag to `status`.
    event SkipNFTSet(address indexed owner, bool status);

    /// @dev `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    /// @dev `keccak256(bytes("SkipNFTSet(address,bool)"))`.
    uint256 private constant _SKIP_NFT_SET_EVENT_SIGNATURE =
        0xb5a1de456fff688115a4f75380060c23c8532d14ff85f687cc871456d6420393;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CUSTOM ERRORS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Thrown when attempting to double-initialize the contract.
    error DNAlreadyInitialized();

    /// @dev The function can only be called after the contract has been initialized.
    error DNNotInitialized();

    /// @dev Thrown when attempting to transfer or burn more tokens than sender's balance.
    error InsufficientBalance();

    /// @dev Thrown when a spender attempts to transfer tokens with an insufficient allowance.
    error InsufficientAllowance();

    /// @dev Thrown when minting an amount of tokens that would overflow the max tokens.
    error TotalSupplyOverflow();

    /// @dev The unit must be greater than zero and less than `2**96`.
    error InvalidUnit();

    /// @dev Thrown when the caller for a fallback NFT function is not the mirror contract.
    error SenderNotMirror();

    /// @dev Thrown when attempting to transfer tokens to the zero address.
    error TransferToZeroAddress();

    /// @dev Thrown when the mirror address provided for initialization is the zero address.
    error MirrorAddressIsZero();

    /// @dev Thrown when the link call to the mirror contract reverts.
    error LinkMirrorContractFailed();

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

    /// @dev The flag to denote that the skip NFT flag is initialized.
    uint8 internal constant _ADDRESS_DATA_SKIP_NFT_INITIALIZED_FLAG = 1 << 0;

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
        // The alias for the address. Zero means absence of an alias.
        uint32 addressAlias;
        // The number of NFT tokens.
        uint32 ownedLength;
        // The token balance in wei.
        uint96 balance;
    }

    /// @dev A uint32 map in storage.
    struct Uint32Map {
        uint256 spacer;
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
    struct DN404Storage {
        // Current number of address aliases assigned.
        uint32 numAliases;
        // Next NFT ID to assign for a mint.
        uint32 nextTokenId;
        // The head of the burned pool.
        uint32 burnedPoolHead;
        // The tail of the burned pool.
        uint32 burnedPoolTail;
        // Total number of NFTs in existence.
        uint32 totalNFTSupply;
        // Total supply of tokens.
        uint96 totalSupply;
        // Address of the NFT mirror contract.
        address mirrorERC721;
        // Mapping of a user alias number to their address.
        mapping(uint32 => address) aliasToAddress;
        // Mapping of user operator approvals for NFTs.
        AddressPairToUint256RefMap operatorApprovals;
        // Mapping of NFT approvals to approved operators.
        mapping(uint256 => address) nftApprovals;
        // Bitmap of whether an non-zero NFT approval may exist.
        Bitmap mayHaveNFTApproval;
        // Bitmap of whether a NFT ID exists. Ignored if `_useExistsLookup()` returns false.
        Bitmap exists;
        // Mapping of user allowances for ERC20 spenders.
        AddressPairToUint256RefMap allowance;
        // Mapping of NFT IDs owned by an address.
        mapping(address => Uint32Map) owned;
        // The pool of burned NFT IDs.
        Uint32Map burnedPool;
        // Even indices: owner aliases. Odd indices: owned indices.
        Uint32Map oo;
        // Mapping of user account AddressData.
        mapping(address => AddressData) addressData;
    }

    /// @dev Returns a storage pointer for DN404Storage.
    function _getDN404Storage() internal pure virtual returns (DN404Storage storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            // `uint72(bytes9(keccak256("DN404_STORAGE")))`.
            $.slot := 0xa20d6e21d0e5255308 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                         INITIALIZER                        */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Initializes the DN404 contract with an
    /// `initialTokenSupply`, `initialTokenOwner` and `mirror` NFT contract address.
    ///
    /// Note: The `initialSupplyOwner` will have their skip NFT status set to true.
    function _initializeDN404(
        uint256 initialTokenSupply,
        address initialSupplyOwner,
        address mirror
    ) internal virtual {
        DN404Storage storage $ = _getDN404Storage();

        unchecked {
            if (_unit() - 1 >= 2 ** 96 - 1) revert InvalidUnit();
        }
        if ($.mirrorERC721 != address(0)) revert DNAlreadyInitialized();
        if (mirror == address(0)) revert MirrorAddressIsZero();

        /// @solidity memory-safe-assembly
        assembly {
            // Make the call to link the mirror contract.
            mstore(0x00, 0x0f4599e5) // `linkMirrorContract(address)`.
            mstore(0x20, caller())
            if iszero(and(eq(mload(0x00), 1), call(gas(), mirror, 0, 0x1c, 0x24, 0x00, 0x20))) {
                mstore(0x00, 0xd125259c) // `LinkMirrorContractFailed()`.
                revert(0x1c, 0x04)
            }
        }

        $.nextTokenId = 1;
        $.mirrorERC721 = mirror;

        if (initialTokenSupply != 0) {
            if (initialSupplyOwner == address(0)) revert TransferToZeroAddress();
            if (_totalSupplyOverflows(initialTokenSupply)) revert TotalSupplyOverflow();

            $.totalSupply = uint96(initialTokenSupply);
            AddressData storage initialOwnerAddressData = $.addressData[initialSupplyOwner];
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
    ///
    /// Note: The return value MUST be kept constant after `_initializeDN404` is called.
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

    /// @dev Returns the Uniform Resource Identifier (URI) for token `id`.
    function _tokenURI(uint256 id) internal view virtual returns (string memory);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                       CONFIGURABLES                        */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns if direct NFT transfers should be used during ERC20 transfers
    /// whenever possible, instead of burning and re-minting.
    function _useDirectTransfersIfPossible() internal view virtual returns (bool) {
        return true;
    }

    /// @dev Returns if burns should be added to the burn pool.
    /// This returns false by default, which means the NFT IDs are re-minted in a cycle.
    function _addToBurnedPool(uint256 totalNFTSupplyAfterBurn, uint256 totalSupplyAfterBurn)
        internal
        view
        virtual
        returns (bool)
    {
        // Silence unused variable compiler warning.
        totalSupplyAfterBurn = totalNFTSupplyAfterBurn;
        return false;
    }

    /// @dev Returns whether to use the exists bitmap for more efficient
    /// scanning of an empty token ID slot.
    /// Recommended for collections that do not use the burn pool,
    /// and are expected to have nearly all possible NFTs materialized.
    ///
    /// Note: The returned value must be constant after initialization.
    function _useExistsLookup() internal view virtual returns (bool) {
        return true;
    }

    /// @dev Hook that is called after a batch of NFT transfers.
    /// The lengths of `from`, `to`, and `ids` are guaranteed to be the same.
    function _afterNFTTransfers(address[] memory from, address[] memory to, uint256[] memory ids)
        internal
        virtual
    {}

    /// @dev Override this function to return true if `_afterNFTTransfers` is used.
    /// This is to help the compiler avoid producing dead bytecode.
    function _useAfterNFTTransfers() internal virtual returns (bool) {}

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      ERC20 OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the decimals places of the token. Defaults to 18.
    /// Does not affect DN404's internal calculations.
    /// Will only affect the frontend UI on most protocols.
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /// @dev Returns the amount of tokens in existence.
    function totalSupply() public view virtual returns (uint256) {
        return uint256(_getDN404Storage().totalSupply);
    }

    /// @dev Returns the amount of tokens owned by `owner`.
    function balanceOf(address owner) public view virtual returns (uint256) {
        return _getDN404Storage().addressData[owner].balance;
    }

    /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender) public view returns (uint256) {
        if (_givePermit2DefaultInfiniteAllowance() && spender == _PERMIT2) {
            uint8 flags = _getDN404Storage().addressData[owner].flags;
            if ((flags & _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG) == uint256(0)) {
                return type(uint256).max;
            }
        }
        return _ref(_getDN404Storage().allowance, owner, spender).value;
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
        Uint256Ref storage a = _ref(_getDN404Storage().allowance, from, msg.sender);

        uint256 allowed = _givePermit2DefaultInfiniteAllowance() && msg.sender == _PERMIT2
            && (_getDN404Storage().addressData[from].flags & _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG)
                == uint256(0) ? type(uint256).max : a.value;

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
    ///
    /// Note: The returned value SHOULD be kept constant.
    /// If the returned value changes from false to true,
    /// it can override the user customized allowances for Permit2 to infinity.
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
    /// Note:
    /// - May mint more NFTs than `amount / _unit()`.
    ///   The number of NFTs minted is what is needed to make `to`'s NFT balance whole.
    /// - Token IDs may wrap around `totalSupply / _unit()` back to 1.
    ///
    /// Emits a {Transfer} event.
    function _mint(address to, uint256 amount) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();
        if ($.mirrorERC721 == address(0)) revert DNNotInitialized();
        AddressData storage toAddressData = $.addressData[to];

        _DNMintTemps memory t;
        unchecked {
            {
                uint256 toBalance = uint256(toAddressData.balance) + amount;
                toAddressData.balance = uint96(toBalance);
                t.toEnd = toBalance / _unit();
            }
            uint256 maxId;
            {
                uint256 newTotalSupply = uint256($.totalSupply) + amount;
                $.totalSupply = uint96(newTotalSupply);
                uint256 overflows = _toUint(_totalSupplyOverflows(newTotalSupply));
                if (overflows | _toUint(newTotalSupply < amount) != 0) revert TotalSupplyOverflow();
                maxId = newTotalSupply / _unit();
            }
            while (!getSkipNFT(to)) {
                Uint32Map storage toOwned = $.owned[to];
                Uint32Map storage oo = $.oo;
                uint256 toIndex = toAddressData.ownedLength;
                if ((t.numNFTMints = _zeroFloorSub(t.toEnd, toIndex)) == uint256(0)) break;

                t.packedLogs = _packedLogsMalloc(t.numNFTMints);
                _packedLogsSet(t.packedLogs, to, 0);
                $.totalNFTSupply += uint32(t.numNFTMints);
                toAddressData.ownedLength = uint32(t.toEnd);
                t.toAlias = _registerAndResolveAlias(toAddressData, to);
                uint32 burnedPoolHead = $.burnedPoolHead;
                t.burnedPoolTail = $.burnedPoolTail;
                t.nextTokenId = _wrapNFTId($.nextTokenId, maxId);
                // Mint loop.
                do {
                    uint256 id;
                    if (burnedPoolHead != t.burnedPoolTail) {
                        id = _get($.burnedPool, burnedPoolHead++);
                    } else {
                        id = t.nextTokenId;
                        while (_get(oo, _ownershipIndex(id)) != 0) {
                            id = _useExistsLookup()
                                ? _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId)
                                : _wrapNFTId(id + 1, maxId);
                        }
                        t.nextTokenId = _wrapNFTId(id + 1, maxId);
                    }
                    if (_useExistsLookup()) _set($.exists, id, true);
                    _set(toOwned, toIndex, uint32(id));
                    _setOwnerAliasAndOwnedIndex(oo, id, t.toAlias, uint32(toIndex++));
                    _packedLogsAppend(t.packedLogs, id);
                } while (toIndex != t.toEnd);

                $.nextTokenId = uint32(t.nextTokenId);
                $.burnedPoolHead = burnedPoolHead;
                _packedLogsSend(t.packedLogs, $);
                break;
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, to)))
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(
                _zeroAddresses(t.numNFTMints),
                _filled(t.numNFTMints, to),
                _packedLogsIds(t.packedLogs)
            );
        }
    }

    /// @dev Mints `amount` tokens to `to`, increasing the total supply.
    /// This variant mints NFT tokens starting from ID `preTotalSupply / _unit() + 1`.
    /// The `nextTokenId` will not be changed.
    /// If any NFTs are minted, the burned pool will be invalidated (emptied).
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is set to false.
    ///
    /// Note:
    /// - May mint more NFTs than `amount / _unit()`.
    ///   The number of NFTs minted is what is needed to make `to`'s NFT balance whole.
    /// - Token IDs may wrap around `totalSupply / _unit()` back to 1.
    ///
    /// Emits a {Transfer} event.
    function _mintNext(address to, uint256 amount) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();
        if ($.mirrorERC721 == address(0)) revert DNNotInitialized();
        AddressData storage toAddressData = $.addressData[to];

        _DNMintTemps memory t;
        unchecked {
            {
                uint256 toBalance = uint256(toAddressData.balance) + amount;
                toAddressData.balance = uint96(toBalance);
                t.toEnd = toBalance / _unit();
            }
            uint256 id;
            uint256 maxId;
            {
                uint256 preTotalSupply = uint256($.totalSupply);
                uint256 newTotalSupply = uint256(preTotalSupply) + amount;
                $.totalSupply = uint96(newTotalSupply);
                uint256 overflows = _toUint(_totalSupplyOverflows(newTotalSupply));
                if (overflows | _toUint(newTotalSupply < amount) != 0) revert TotalSupplyOverflow();
                maxId = newTotalSupply / _unit();
                id = _wrapNFTId(preTotalSupply / _unit() + 1, maxId);
            }
            while (!getSkipNFT(to)) {
                Uint32Map storage toOwned = $.owned[to];
                Uint32Map storage oo = $.oo;
                uint256 toIndex = toAddressData.ownedLength;
                if ((t.numNFTMints = _zeroFloorSub(t.toEnd, toIndex)) == uint256(0)) break;

                t.packedLogs = _packedLogsMalloc(t.numNFTMints);
                // Invalidate (empty) the burned pool.
                $.burnedPoolHead = 0;
                $.burnedPoolTail = 0;
                _packedLogsSet(t.packedLogs, to, 0);
                $.totalNFTSupply += uint32(t.numNFTMints);
                toAddressData.ownedLength = uint32(t.toEnd);
                t.toAlias = _registerAndResolveAlias(toAddressData, to);
                // Mint loop.
                do {
                    while (_get(oo, _ownershipIndex(id)) != 0) {
                        id = _useExistsLookup()
                            ? _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId)
                            : _wrapNFTId(id + 1, maxId);
                    }
                    if (_useExistsLookup()) _set($.exists, id, true);
                    _set(toOwned, toIndex, uint32(id));
                    _setOwnerAliasAndOwnedIndex(oo, id, t.toAlias, uint32(toIndex++));
                    _packedLogsAppend(t.packedLogs, id);
                    id = _wrapNFTId(id + 1, maxId);
                } while (toIndex != t.toEnd);

                _packedLogsSend(t.packedLogs, $);
                break;
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, to)))
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(
                _zeroAddresses(t.numNFTMints),
                _filled(t.numNFTMints, to),
                _packedLogsIds(t.packedLogs)
            );
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
        DN404Storage storage $ = _getDN404Storage();
        if ($.mirrorERC721 == address(0)) revert DNNotInitialized();

        AddressData storage fromAddressData = $.addressData[from];
        _DNBurnTemps memory t;

        unchecked {
            t.fromBalance = fromAddressData.balance;
            if (amount > t.fromBalance) revert InsufficientBalance();

            fromAddressData.balance = uint96(t.fromBalance -= amount);
            t.totalSupply = uint256($.totalSupply) - amount;
            $.totalSupply = uint96(t.totalSupply);

            Uint32Map storage fromOwned = $.owned[from];
            uint256 fromIndex = fromAddressData.ownedLength;
            t.numNFTBurns = _zeroFloorSub(fromIndex, t.fromBalance / _unit());

            if (t.numNFTBurns != 0) {
                t.packedLogs = _packedLogsMalloc(t.numNFTBurns);
                _packedLogsSet(t.packedLogs, from, 1);
                bool addToBurnedPool;
                {
                    uint256 totalNFTSupply = uint256($.totalNFTSupply) - t.numNFTBurns;
                    $.totalNFTSupply = uint32(totalNFTSupply);
                    addToBurnedPool = _addToBurnedPool(totalNFTSupply, t.totalSupply);
                }

                Uint32Map storage oo = $.oo;
                uint256 fromEnd = fromIndex - t.numNFTBurns;
                fromAddressData.ownedLength = uint32(fromEnd);
                uint32 burnedPoolTail = $.burnedPoolTail;
                // Burn loop.
                do {
                    uint256 id = _get(fromOwned, --fromIndex);
                    _setOwnerAliasAndOwnedIndex(oo, id, 0, 0);
                    _packedLogsAppend(t.packedLogs, id);
                    if (_useExistsLookup()) _set($.exists, id, false);
                    if (addToBurnedPool) _set($.burnedPool, burnedPoolTail++, uint32(id));
                    if (_get($.mayHaveNFTApproval, id)) {
                        _set($.mayHaveNFTApproval, id, false);
                        delete $.nftApprovals[id];
                    }
                } while (fromIndex != fromEnd);

                if (addToBurnedPool) $.burnedPoolTail = burnedPoolTail;
                _packedLogsSend(t.packedLogs, $);
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), 0)
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(
                _filled(t.numNFTBurns, from),
                _zeroAddresses(t.numNFTBurns),
                _packedLogsIds(t.packedLogs)
            );
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

        DN404Storage storage $ = _getDN404Storage();
        AddressData storage fromAddressData = $.addressData[from];
        AddressData storage toAddressData = $.addressData[to];
        if ($.mirrorERC721 == address(0)) revert DNNotInitialized();

        _DNTransferTemps memory t;
        t.fromOwnedLength = fromAddressData.ownedLength;
        t.toOwnedLength = toAddressData.ownedLength;

        unchecked {
            {
                uint256 fromBalance = fromAddressData.balance;
                if (amount > fromBalance) revert InsufficientBalance();
                fromAddressData.balance = uint96(fromBalance -= amount);

                uint256 toBalance = uint256(toAddressData.balance) + amount;
                toAddressData.balance = uint96(toBalance);
                t.numNFTBurns = _zeroFloorSub(t.fromOwnedLength, fromBalance / _unit());

                if (!getSkipNFT(to)) {
                    if (from == to) t.toOwnedLength = t.fromOwnedLength - t.numNFTBurns;
                    t.numNFTMints = _zeroFloorSub(toBalance / _unit(), t.toOwnedLength);
                }
            }

            while (_useDirectTransfersIfPossible()) {
                uint256 n = _min(t.fromOwnedLength, _min(t.numNFTBurns, t.numNFTMints));
                if (n == uint256(0)) break;
                t.numNFTBurns -= n;
                t.numNFTMints -= n;
                if (from == to) {
                    t.toOwnedLength += n;
                    break;
                }
                t.directLogs = _directLogsMalloc(n, from, to);
                Uint32Map storage fromOwned = $.owned[from];
                Uint32Map storage toOwned = $.owned[to];
                t.toAlias = _registerAndResolveAlias(toAddressData, to);
                uint256 toIndex = t.toOwnedLength;
                n = toIndex + n;
                // Direct transfer loop.
                do {
                    uint256 id = _get(fromOwned, --t.fromOwnedLength);
                    _set(toOwned, toIndex, uint32(id));
                    _setOwnerAliasAndOwnedIndex($.oo, id, t.toAlias, uint32(toIndex));
                    _directLogsAppend(t.directLogs, id);
                    if (_get($.mayHaveNFTApproval, id)) {
                        _set($.mayHaveNFTApproval, id, false);
                        delete $.nftApprovals[id];
                    }
                } while (++toIndex != n);

                toAddressData.ownedLength = uint32(t.toOwnedLength = toIndex);
                fromAddressData.ownedLength = uint32(t.fromOwnedLength);
                break;
            }

            t.totalNFTSupply = uint256($.totalNFTSupply) + t.numNFTMints - t.numNFTBurns;
            $.totalNFTSupply = uint32(t.totalNFTSupply);

            Uint32Map storage oo = $.oo;
            t.packedLogs = _packedLogsMalloc(t.numNFTBurns + t.numNFTMints);

            t.burnedPoolTail = $.burnedPoolTail;
            if (t.numNFTBurns != 0) {
                _packedLogsSet(t.packedLogs, from, 1);
                bool addToBurnedPool = _addToBurnedPool(t.totalNFTSupply, $.totalSupply);
                Uint32Map storage fromOwned = $.owned[from];
                uint256 fromIndex = t.fromOwnedLength;
                fromAddressData.ownedLength = uint32(t.fromEnd = fromIndex - t.numNFTBurns);
                uint32 burnedPoolTail = t.burnedPoolTail;
                // Burn loop.
                do {
                    uint256 id = _get(fromOwned, --fromIndex);
                    _setOwnerAliasAndOwnedIndex(oo, id, 0, 0);
                    _packedLogsAppend(t.packedLogs, id);
                    if (_useExistsLookup()) _set($.exists, id, false);
                    if (addToBurnedPool) _set($.burnedPool, burnedPoolTail++, uint32(id));
                    if (_get($.mayHaveNFTApproval, id)) {
                        _set($.mayHaveNFTApproval, id, false);
                        delete $.nftApprovals[id];
                    }
                } while (fromIndex != t.fromEnd);

                if (addToBurnedPool) $.burnedPoolTail = (t.burnedPoolTail = burnedPoolTail);
            }

            if (t.numNFTMints != 0) {
                _packedLogsSet(t.packedLogs, to, 0);
                Uint32Map storage toOwned = $.owned[to];
                t.toAlias = _registerAndResolveAlias(toAddressData, to);
                uint256 maxId = $.totalSupply / _unit();
                t.nextTokenId = _wrapNFTId($.nextTokenId, maxId);
                uint256 toIndex = t.toOwnedLength;
                toAddressData.ownedLength = uint32(t.toEnd = toIndex + t.numNFTMints);
                uint32 burnedPoolHead = $.burnedPoolHead;
                // Mint loop.
                do {
                    uint256 id;
                    if (burnedPoolHead != t.burnedPoolTail) {
                        id = _get($.burnedPool, burnedPoolHead++);
                    } else {
                        id = t.nextTokenId;
                        while (_get(oo, _ownershipIndex(id)) != 0) {
                            id = _useExistsLookup()
                                ? _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId)
                                : _wrapNFTId(id + 1, maxId);
                        }
                        t.nextTokenId = _wrapNFTId(id + 1, maxId);
                    }
                    if (_useExistsLookup()) _set($.exists, id, true);
                    _set(toOwned, toIndex, uint32(id));
                    _setOwnerAliasAndOwnedIndex(oo, id, t.toAlias, uint32(toIndex++));
                    _packedLogsAppend(t.packedLogs, id);
                } while (toIndex != t.toEnd);

                $.burnedPoolHead = burnedPoolHead;
                $.nextTokenId = uint32(t.nextTokenId);
            }

            if (t.directLogs != bytes32(0)) _directLogsSend(t.directLogs, $);
            if (t.packedLogs != bytes32(0)) _packedLogsSend(t.packedLogs, $);
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            // forgefmt: disable-next-item
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), shr(96, shl(96, to)))
        }
        if (_useAfterNFTTransfers()) {
            uint256[] memory ids = _directLogsIds(t.directLogs);
            unchecked {
                _afterNFTTransfers(
                    _concat(
                        _filled(ids.length + t.numNFTBurns, from), _zeroAddresses(t.numNFTMints)
                    ),
                    _concat(
                        _concat(_filled(ids.length, to), _zeroAddresses(t.numNFTBurns)),
                        _filled(t.numNFTMints, to)
                    ),
                    _concat(ids, _packedLogsIds(t.packedLogs))
                );
            }
        }
    }

    /// @dev Transfers token `id` from `from` to `to`.
    /// Also emits an ERC721 {Transfer} event on the `mirrorERC721`.
    ///
    /// Requirements:
    ///
    /// - Token `id` must exist.
    /// - `from` must be the owner of the token.
    /// - `to` cannot be the zero address.
    /// - `msgSender` must be the owner of the token, or be approved to manage the token.
    ///
    /// Emits a {Transfer} event.
    function _initiateTransferFromNFT(address from, address to, uint256 id, address msgSender)
        internal
        virtual
    {
        // Emit ERC721 {Transfer} event.
        // We do this before the `_transferFromNFT`, as `_transferFromNFT` may use
        // the `_afterNFTTransfers` hook, which may trigger more transfers.
        // This helps keeps the sequence of emitted events consistent.
        // Since `mirrorERC721` is a trusted contract, we can do this.
        bytes32 directLogs = _directLogsMalloc(1, from, to);
        _directLogsAppend(directLogs, id);
        _directLogsSend(directLogs, _getDN404Storage());

        _transferFromNFT(from, to, id, msgSender);
    }

    /// @dev Transfers token `id` from `from` to `to`.
    ///
    /// This function will be called when a ERC721 transfer is made on the mirror contract.
    ///
    /// Requirements:
    ///
    /// - Token `id` must exist.
    /// - `from` must be the owner of the token.
    /// - `to` cannot be the zero address.
    /// - `msgSender` must be the owner of the token, or be approved to manage the token.
    ///
    /// Emits a {Transfer} event.
    function _transferFromNFT(address from, address to, uint256 id, address msgSender)
        internal
        virtual
    {
        if (to == address(0)) revert TransferToZeroAddress();

        DN404Storage storage $ = _getDN404Storage();
        if ($.mirrorERC721 == address(0)) revert DNNotInitialized();

        Uint32Map storage oo = $.oo;

        if (from != $.aliasToAddress[_get(oo, _ownershipIndex(_restrictNFTId(id)))]) {
            revert TransferFromIncorrectOwner();
        }

        if (msgSender != from) {
            if (!_isApprovedForAll(from, msgSender)) {
                if (_getApproved(id) != msgSender) {
                    revert TransferCallerNotOwnerNorApproved();
                }
            }
        }

        AddressData storage fromAddressData = $.addressData[from];
        AddressData storage toAddressData = $.addressData[to];

        uint256 unit = _unit();
        mapping(address => Uint32Map) storage owned = $.owned;

        unchecked {
            uint256 fromBalance = fromAddressData.balance;
            if (unit > fromBalance) revert InsufficientBalance();
            fromAddressData.balance = uint96(fromBalance - unit);
            toAddressData.balance += uint96(unit);
        }
        if (_get($.mayHaveNFTApproval, id)) {
            _set($.mayHaveNFTApproval, id, false);
            delete $.nftApprovals[id];
        }
        unchecked {
            Uint32Map storage fromOwned = owned[from];
            uint32 updatedId = _get(fromOwned, --fromAddressData.ownedLength);
            uint32 i = _get(oo, _ownedIndex(id));
            _set(fromOwned, i, updatedId);
            _set(oo, _ownedIndex(updatedId), i);
        }
        unchecked {
            uint32 n = toAddressData.ownedLength++;
            _set(owned[to], n, uint32(id));
            _setOwnerAliasAndOwnedIndex(oo, id, _registerAndResolveAlias(toAddressData, to), n);
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Transfer} event.
            mstore(0x00, unit)
            // forgefmt: disable-next-item
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), shr(96, shl(96, to)))
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(_filled(1, from), _filled(1, to), _filled(1, id));
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
            _getDN404Storage().addressData[owner].flags |= _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG;
        }
        _ref(_getDN404Storage().allowance, owner, spender).value = amount;
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
        return _getDN404Storage().addressData[owner].aux;
    }

    /// @dev Set the auxiliary data for `owner` to `value`.
    /// Minting, transferring, burning the tokens of `owner` will not change the auxiliary data.
    /// Auxiliary data can be set for any address, even if it does not have any tokens.
    function _setAux(address owner, uint88 value) internal virtual {
        _getDN404Storage().addressData[owner].aux = value;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     SKIP NFT FUNCTIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns true if minting and transferring ERC20s to `owner` will skip minting NFTs.
    /// Returns false otherwise.
    function getSkipNFT(address owner) public view virtual returns (bool result) {
        uint8 flags = _getDN404Storage().addressData[owner].flags;
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(and(flags, _ADDRESS_DATA_SKIP_NFT_FLAG)))
            if iszero(and(flags, _ADDRESS_DATA_SKIP_NFT_INITIALIZED_FLAG)) {
                result := iszero(iszero(extcodesize(owner)))
            }
        }
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
        AddressData storage d = _getDN404Storage().addressData[owner];
        uint8 flags = d.flags;
        /// @solidity memory-safe-assembly
        assembly {
            let s := xor(iszero(and(flags, _ADDRESS_DATA_SKIP_NFT_FLAG)), iszero(state))
            flags := xor(mul(_ADDRESS_DATA_SKIP_NFT_FLAG, s), flags)
            flags := or(_ADDRESS_DATA_SKIP_NFT_INITIALIZED_FLAG, flags)
            mstore(0x00, iszero(iszero(state)))
            log2(0x00, 0x20, _SKIP_NFT_SET_EVENT_SIGNATURE, shr(96, shl(96, owner)))
        }
        d.flags = flags;
    }

    /// @dev Returns the `addressAlias` of account `to`.
    ///
    /// Assigns and registers the next alias if `to` alias was not previously registered.
    function _registerAndResolveAlias(AddressData storage toAddressData, address to)
        internal
        virtual
        returns (uint32 addressAlias)
    {
        DN404Storage storage $ = _getDN404Storage();
        addressAlias = toAddressData.addressAlias;
        if (addressAlias == uint256(0)) {
            unchecked {
                addressAlias = ++$.numAliases;
            }
            toAddressData.addressAlias = addressAlias;
            $.aliasToAddress[addressAlias] = to;
            if (addressAlias == uint256(0)) revert(); // Overflow.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     MIRROR OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the address of the mirror NFT contract.
    function mirrorERC721() public view virtual returns (address) {
        return _getDN404Storage().mirrorERC721;
    }

    /// @dev Returns the total NFT supply.
    function _totalNFTSupply() internal view virtual returns (uint256) {
        return _getDN404Storage().totalNFTSupply;
    }

    /// @dev Returns `owner` NFT balance.
    function _balanceOfNFT(address owner) internal view virtual returns (uint256) {
        return _getDN404Storage().addressData[owner].ownedLength;
    }

    /// @dev Returns the owner of token `id`.
    /// Returns the zero address instead of reverting if the token does not exist.
    function _ownerAt(uint256 id) internal view virtual returns (address) {
        DN404Storage storage $ = _getDN404Storage();
        return $.aliasToAddress[_get($.oo, _ownershipIndex(_restrictNFTId(id)))];
    }

    /// @dev Returns the owner of token `id`.
    ///
    /// Requirements:
    /// - Token `id` must exist.
    function _ownerOf(uint256 id) internal view virtual returns (address) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return _ownerAt(id);
    }

    /// @dev Returns whether `operator` is approved to manage the NFT tokens of `owner`.
    function _isApprovedForAll(address owner, address operator)
        internal
        view
        virtual
        returns (bool)
    {
        return _ref(_getDN404Storage().operatorApprovals, owner, operator).value != 0;
    }

    /// @dev Returns if token `id` exists.
    function _exists(uint256 id) internal view virtual returns (bool) {
        return _ownerAt(id) != address(0);
    }

    /// @dev Returns the account approved to manage token `id`.
    ///
    /// Requirements:
    /// - Token `id` must exist.
    function _getApproved(uint256 id) internal view virtual returns (address) {
        if (!_exists(id)) revert TokenDoesNotExist();
        return _getDN404Storage().nftApprovals[id];
    }

    /// @dev Sets `spender` as the approved account to manage token `id`, using `msgSender`.
    ///
    /// Requirements:
    /// - `msgSender` must be the owner or an approved operator for the token owner.
    function _approveNFT(address spender, uint256 id, address msgSender)
        internal
        virtual
        returns (address owner)
    {
        DN404Storage storage $ = _getDN404Storage();

        owner = $.aliasToAddress[_get($.oo, _ownershipIndex(_restrictNFTId(id)))];

        if (msgSender != owner) {
            if (!_isApprovedForAll(owner, msgSender)) {
                revert ApprovalCallerNotOwnerNorApproved();
            }
        }

        $.nftApprovals[id] = spender;
        _set($.mayHaveNFTApproval, id, spender != address(0));
    }

    /// @dev Approve or remove the `operator` as an operator for `msgSender`,
    /// without authorization checks.
    function _setApprovalForAll(address operator, bool approved, address msgSender)
        internal
        virtual
    {
        // For efficiency, we won't check if `operator` isn't `address(0)` (practically a no-op).
        _ref(_getDN404Storage().operatorApprovals, msgSender, operator).value = _toUint(approved);
    }

    /// @dev Returns the NFT IDs of `owner` in the range `[begin..end)` (exclusive of `end`).
    /// `begin` and `end` are indices in the owner's token ID array, not the entire token range.
    /// Optimized for smaller bytecode size, as this function is intended for off-chain calling.
    function _ownedIds(address owner, uint256 begin, uint256 end)
        internal
        view
        virtual
        returns (uint256[] memory ids)
    {
        DN404Storage storage $ = _getDN404Storage();
        Uint32Map storage owned = $.owned[owner];
        end = _min($.addressData[owner].ownedLength, end);
        /// @solidity memory-safe-assembly
        assembly {
            ids := mload(0x40)
            let i := begin
            for {} lt(i, end) { i := add(i, 1) } {
                let s := add(shl(96, owned.slot), shr(3, i)) // Storage slot.
                let id := and(0xffffffff, shr(shl(5, and(i, 7)), sload(s)))
                mstore(add(add(ids, 0x20), shl(5, sub(i, begin))), id) // Append to.
            }
            mstore(ids, sub(i, begin)) // Store the length.
            mstore(0x40, add(add(ids, 0x20), shl(5, sub(i, begin)))) // Allocate memory.
        }
    }

    /// @dev Fallback modifier to dispatch calls from the mirror NFT contract
    /// to internal functions in this contract.
    modifier dn404Fallback() virtual {
        DN404Storage storage $ = _getDN404Storage();

        uint256 fnSelector = _calldataload(0x00) >> 224;

        // `transferFromNFT(address,address,uint256,address)`.
        if (fnSelector == 0xe5eb36c8) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            _transferFromNFT(
                address(uint160(_calldataload(0x04))), // `from`.
                address(uint160(_calldataload(0x24))), // `to`.
                _calldataload(0x44), // `id`.
                address(uint160(_calldataload(0x64))) // `msgSender`.
            );
            _return(1);
        }
        // `setApprovalForAllNFT(address,bool,address)`.
        if (fnSelector == 0xf6916ddd) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            _setApprovalForAll(
                address(uint160(_calldataload(0x04))), // `spender`.
                _calldataload(0x24) != 0, // `status`.
                address(uint160(_calldataload(0x44))) // `msgSender`.
            );
            _return(1);
        }
        // `isApprovedForAllNFT(address,address)`.
        if (fnSelector == 0x62fb246d) {
            bool result = _isApprovedForAll(
                address(uint160(_calldataload(0x04))), // `owner`.
                address(uint160(_calldataload(0x24))) // `operator`.
            );
            _return(_toUint(result));
        }
        // `ownerOfNFT(uint256)`.
        if (fnSelector == 0x2d8a746e) {
            _return(uint160(_ownerOf(_calldataload(0x04))));
        }
        // `ownerAtNFT(uint256)`.
        if (fnSelector == 0xc016aa52) {
            _return(uint160(_ownerAt(_calldataload(0x04))));
        }
        // `approveNFT(address,uint256,address)`.
        if (fnSelector == 0xd10b6e0c) {
            if (msg.sender != $.mirrorERC721) revert SenderNotMirror();
            address owner = _approveNFT(
                address(uint160(_calldataload(0x04))), // `spender`.
                _calldataload(0x24), // `id`.
                address(uint160(_calldataload(0x44))) // `msgSender`.
            );
            _return(uint160(owner));
        }
        // `getApprovedNFT(uint256)`.
        if (fnSelector == 0x27ef5495) {
            _return(uint160(_getApproved(_calldataload(0x04))));
        }
        // `balanceOfNFT(address)`.
        if (fnSelector == 0xf5b100ea) {
            _return(_balanceOfNFT(address(uint160(_calldataload(0x04)))));
        }
        // `totalNFTSupply()`.
        if (fnSelector == 0xe2c79281) {
            _return(_totalNFTSupply());
        }
        // `tokenURINFT(uint256)`.
        if (fnSelector == 0xcb30b460) {
            /// @solidity memory-safe-assembly
            assembly {
                mstore(0x40, add(mload(0x40), 0x20))
            }
            string memory uri = _tokenURI(_calldataload(0x04));
            /// @solidity memory-safe-assembly
            assembly {
                // Memory safe, as we've advanced the free memory pointer by a word.
                let o := sub(uri, 0x20) // Start of the returndata.
                let z := add(mload(uri), 0x40) // Unpadded length of returndata.
                mstore(add(o, z), 0) // Zeroize the word after the end of the string.
                mstore(o, 0x20) // Store the offset of `uri`.
                return(o, and(not(0x1f), add(0x1f, z)))
            }
        }
        // `implementsDN404()`.
        if (fnSelector == 0xb7a94eb8) {
            _return(1);
        }
        _;
    }

    /// @dev Fallback function for calls from mirror NFT contract.
    /// Override this if you need to implement your custom
    /// fallback with utilities like Solady's `LibZip.cdFallback()`.
    /// And always remember to always wrap the fallback with `dn404Fallback`.
    fallback() external payable virtual dn404Fallback {
        revert FnSelectorNotRecognized(); // Not mandatory. Just for quality of life.
    }

    /// @dev This is to silence the compiler warning.
    /// Override and remove the revert if you want your contract to receive ETH via receive.
    receive() external payable virtual {
        if (msg.value != 0) revert();
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 INTERNAL / PRIVATE HELPERS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns `(i - 1) << 1`.
    function _ownershipIndex(uint256 i) internal pure returns (uint256) {
        unchecked {
            return (i - 1) << 1; // Minus 1 as token IDs start from 1.
        }
    }

    /// @dev Returns `((i - 1) << 1) + 1`.
    function _ownedIndex(uint256 i) internal pure returns (uint256) {
        unchecked {
            return ((i - 1) << 1) + 1; // Minus 1 as token IDs start from 1.
        }
    }

    /// @dev Returns the uint32 value at `index` in `map`.
    function _get(Uint32Map storage map, uint256 index) internal view returns (uint32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, map.slot), shr(3, index)) // Storage slot.
            result := and(0xffffffff, shr(shl(5, and(index, 7)), sload(s)))
        }
    }

    /// @dev Updates the uint32 value at `index` in `map`.
    function _set(Uint32Map storage map, uint256 index, uint32 value) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let s := add(shl(96, map.slot), shr(3, index)) // Storage slot.
            let o := shl(5, and(index, 7)) // Storage slot offset (bits).
            let v := sload(s) // Storage slot value.
            sstore(s, xor(v, shl(o, and(0xffffffff, xor(value, shr(o, v))))))
        }
    }

    /// @dev Sets the owner alias and the owned index together.
    function _setOwnerAliasAndOwnedIndex(
        Uint32Map storage map,
        uint256 id,
        uint32 ownership,
        uint32 ownedIndex
    ) internal {
        /// @solidity memory-safe-assembly
        assembly {
            let i := sub(id, 1) // Index of the uint64 combined value.
            let s := add(shl(96, map.slot), shr(2, i)) // Storage slot.
            let v := sload(s) // Storage slot value.
            let o := shl(6, and(i, 3)) // Storage slot offset (bits).
            let combined := or(shl(32, ownedIndex), and(0xffffffff, ownership))
            sstore(s, xor(v, shl(o, and(0xffffffffffffffff, xor(shr(o, v), combined)))))
        }
    }

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
    /// If no unset bit is found, returns `type(uint256).max`.
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
            let negBits := shl(and(0xff, begin), shr(and(0xff, begin), not(sload(bucket))))
            if iszero(negBits) {
                let lastBucket := add(s, shr(8, upTo))
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
                // From: https://github.com/vectorized/solady/blob/main/src/utils/LibBit.sol
                let b := and(negBits, add(not(negBits), 1)) // Isolate the least significant bit.
                // For the upper 3 bits of the result, use a De Bruijn-like lookup.
                // Credit to adhusson: https://blog.adhusson.com/cheap-find-first-set-evm/
                // forgefmt: disable-next-item
                let r := shl(5, shr(252, shl(shl(2, shr(250, mul(b,
                    0x2aaaaaaaba69a69a6db6db6db2cb2cb2ce739ce73def7bdeffffffff))),
                    0x1412563212c14164235266736f7425221143267a45243675267677)))
                // For the lower 5 bits of the result, use a De Bruijn lookup.
                // forgefmt: disable-next-item
                r := or(r, byte(and(div(0xd76453e0, shr(r, b)), 0x1f),
                    0x001f0d1e100c1d070f090b19131c1706010e11080a1a141802121b1503160405))
                r := or(shl(8, sub(bucket, s)), r)
                unsetBitIndex := or(r, sub(0, or(gt(r, upTo), lt(r, begin))))
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

    /// @dev Returns whether `amount` is an invalid `totalSupply`.
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

    /// @dev Returns `b ? 1 : 0`.
    function _toUint(bool b) internal pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := iszero(iszero(b))
        }
    }

    /// @dev Initiates memory allocation for direct logs with `n` log items.
    function _directLogsMalloc(uint256 n, address from, address to)
        private
        pure
        returns (bytes32 p)
    {
        /// @solidity memory-safe-assembly
        assembly {
            // `p`'s layout:
            //    uint256 offset;
            //    uint256[] logs;
            p := mload(0x40)
            let m := add(p, 0x40)
            mstore(m, 0x144027d3) // `logDirectTransfer(address,address,uint256[])`.
            mstore(add(m, 0x20), shr(96, shl(96, from)))
            mstore(add(m, 0x40), shr(96, shl(96, to)))
            mstore(add(m, 0x60), 0x60) // Offset of `logs` in the calldata to send.
            // Skip 4 words: `fnSelector`, `from`, `to`, `calldataLogsOffset`.
            let logs := add(0x80, m)
            mstore(logs, n) // Store the length.
            let offset := add(0x20, logs) // Skip the word for `p.logs.length`.
            mstore(0x40, add(offset, shl(5, n))) // Allocate memory.
            mstore(add(0x20, p), logs) // Set `p.logs`.
            mstore(p, offset) // Set `p.offset`.
        }
    }

    /// @dev Adds a direct log item to `p` with token `id`.
    function _directLogsAppend(bytes32 p, uint256 id) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            let offset := mload(p)
            mstore(offset, id)
            mstore(p, add(offset, 0x20))
        }
    }

    /// @dev Calls the `mirror` NFT contract to emit {Transfer} events for packed logs `p`.
    function _directLogsSend(bytes32 p, DN404Storage storage $) private {
        address mirror = $.mirrorERC721;
        /// @solidity memory-safe-assembly
        assembly {
            let logs := mload(add(p, 0x20))
            let n := add(0x84, shl(5, mload(logs))) // Length of calldata to send.
            let o := sub(logs, 0x80) // Start of calldata to send.
            if iszero(and(eq(mload(o), 1), call(gas(), mirror, 0, add(o, 0x1c), n, o, 0x20))) {
                revert(o, 0x00)
            }
        }
    }

    /// @dev Returns the token IDs of the direct logs.
    function _directLogsIds(bytes32 p) private pure returns (uint256[] memory ids) {
        /// @solidity memory-safe-assembly
        assembly {
            if p { ids := mload(add(p, 0x20)) }
        }
    }

    /// @dev Initiates memory allocation for packed logs with `n` log items.
    function _packedLogsMalloc(uint256 n) private pure returns (bytes32 p) {
        /// @solidity memory-safe-assembly
        assembly {
            // `p`'s layout:
            //     uint256 offset;
            //     uint256 addressAndBit;
            //     uint256[] logs;
            p := mload(0x40)
            let logs := add(p, 0xa0)
            mstore(logs, n) // Store the length.
            let offset := add(0x20, logs) // Skip the word for `p.logs.length`.
            mstore(0x40, add(offset, shl(5, n))) // Allocate memory.
            mstore(add(0x40, p), logs) // Set `p.logs`.
            mstore(p, offset) // Set `p.offset`.
        }
    }

    /// @dev Set the current address and the burn bit.
    function _packedLogsSet(bytes32 p, address a, uint256 burnBit) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(add(p, 0x20), or(shl(96, a), burnBit)) // Set `p.addressAndBit`.
        }
    }

    /// @dev Adds a packed log item to `p` with token `id`.
    function _packedLogsAppend(bytes32 p, uint256 id) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            let offset := mload(p)
            mstore(offset, or(mload(add(p, 0x20)), shl(8, id))) // `p.addressAndBit | (id << 8)`.
            mstore(p, add(offset, 0x20))
        }
    }

    /// @dev Calls the `mirror` NFT contract to emit {Transfer} events for packed logs `p`.
    function _packedLogsSend(bytes32 p, DN404Storage storage $) private {
        address mirror = $.mirrorERC721;
        /// @solidity memory-safe-assembly
        assembly {
            let logs := mload(add(p, 0x40))
            let o := sub(logs, 0x40) // Start of calldata to send.
            mstore(o, 0x263c69d6) // `logTransfer(uint256[])`.
            mstore(add(o, 0x20), 0x20) // Offset of `logs` in the calldata to send.
            let n := add(0x44, shl(5, mload(logs))) // Length of calldata to send.
            if iszero(and(eq(mload(o), 1), call(gas(), mirror, 0, add(o, 0x1c), n, o, 0x20))) {
                revert(o, 0x00)
            }
        }
    }

    /// @dev Returns the token IDs of the packed logs (destructively).
    function _packedLogsIds(bytes32 p) private pure returns (uint256[] memory ids) {
        /// @solidity memory-safe-assembly
        assembly {
            if p {
                ids := mload(add(p, 0x40))
                let o := add(ids, 0x20)
                let end := add(o, shl(5, mload(ids)))
                for {} iszero(eq(o, end)) { o := add(o, 0x20) } {
                    mstore(o, shr(168, shl(160, mload(o))))
                }
            }
        }
    }

    /// @dev Returns an array of zero addresses.
    function _zeroAddresses(uint256 n) private pure returns (address[] memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(0x40, add(add(result, 0x20), shl(5, n)))
            mstore(result, n)
            codecopy(add(result, 0x20), codesize(), shl(5, n))
        }
    }

    /// @dev Returns an array each set to `value`.
    function _filled(uint256 n, uint256 value) private pure returns (uint256[] memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let o := add(result, 0x20)
            let end := add(o, shl(5, n))
            mstore(0x40, end)
            mstore(result, n)
            for {} iszero(eq(o, end)) { o := add(o, 0x20) } { mstore(o, value) }
        }
    }

    /// @dev Returns an array each set to `value`.
    function _filled(uint256 n, address value) private pure returns (address[] memory result) {
        result = _toAddresses(_filled(n, uint160(value)));
    }

    /// @dev Concatenates the arrays.
    function _concat(uint256[] memory a, uint256[] memory b)
        private
        view
        returns (uint256[] memory result)
    {
        uint256 aN = a.length;
        uint256 bN = b.length;
        if (aN == uint256(0)) return b;
        if (bN == uint256(0)) return a;
        /// @solidity memory-safe-assembly
        assembly {
            let n := add(aN, bN)
            if n {
                result := mload(0x40)
                mstore(result, n)
                let o := add(result, 0x20)
                mstore(0x40, add(o, shl(5, n)))
                let aL := shl(5, aN)
                pop(staticcall(gas(), 4, add(a, 0x20), aL, o, aL))
                pop(staticcall(gas(), 4, add(b, 0x20), shl(5, bN), add(o, aL), shl(5, bN)))
            }
        }
    }

    /// @dev Concatenates the arrays.
    function _concat(address[] memory a, address[] memory b)
        private
        view
        returns (address[] memory result)
    {
        result = _toAddresses(_concat(_toUints(a), _toUints(b)));
    }

    /// @dev Reinterpret cast to an uint array.
    function _toUints(address[] memory a) private pure returns (uint256[] memory casted) {
        /// @solidity memory-safe-assembly
        assembly {
            casted := a
        }
    }

    /// @dev Reinterpret cast to an address array.
    function _toAddresses(uint256[] memory a) private pure returns (address[] memory casted) {
        /// @solidity memory-safe-assembly
        assembly {
            casted := a
        }
    }

    /// @dev Struct of temporary variables for transfers.
    struct _DNTransferTemps {
        uint256 numNFTBurns;
        uint256 numNFTMints;
        uint256 fromOwnedLength;
        uint256 toOwnedLength;
        uint256 totalNFTSupply;
        uint256 fromEnd;
        uint256 toEnd;
        uint32 toAlias;
        uint256 nextTokenId;
        uint32 burnedPoolTail;
        bytes32 directLogs;
        bytes32 packedLogs;
    }

    /// @dev Struct of temporary variables for mints.
    struct _DNMintTemps {
        uint256 nextTokenId;
        uint32 burnedPoolTail;
        uint256 toEnd;
        uint32 toAlias;
        uint256 numNFTMints;
        bytes32 packedLogs;
    }

    /// @dev Struct of temporary variables for burns.
    struct _DNBurnTemps {
        uint256 fromBalance;
        uint256 totalSupply;
        uint256 numNFTBurns;
        bytes32 packedLogs;
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
