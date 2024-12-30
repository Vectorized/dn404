// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title DN420
/// @notice DN420 is a fully standard compliant, single-contract,
/// ERC20 and ERC1155 chimera implementation that mints
/// and burns NFTs based on an account's ERC20 token balance.
///
/// This contract has not yet been audited. USE AT YOUR OWN RISK!
///
/// @author vectorized.eth (@optimizoor)
/// @author Quit (@0xQuit)
/// @author Michael Amadi (@AmadiMichaels)
/// @author cygaar (@0xCygaar)
/// @author Thomas (@0xjustadev)
/// @author Harrison (@PopPunkOnChain)
///
/// @dev Note:
/// - On-transfer token ID burning scheme:
///     * DN420: Largest token ID up to owned checkpoint (inclusive) first.
///     * DN404: Most recently acquired token ID first.
/// - This implementation uses bitmap scans to find ERC1155 token IDs
///   to transfer / burn upon ERC20 transfers.
/// - For long-term gas efficiency, please ensure that the maximum
///   supply of NFTs is bounded and not too big.
///   10k is fine; it will cost less than 100k gas to bitmap scan 10k bits.
///   Otherwise, users can still always call `setOwnedCheckpoint` to unblock.
/// - A unit worth of ERC20 tokens equates to a deed to one NFT token.
///   The skip NFT status determines if this deed is automatically exercised.
///   An account can configure their skip NFT status.
///     * If `getSkipNFT(owner) == true`, ERC20 mints / transfers to `owner`
///       will NOT trigger NFT mints / transfers to `owner` (i.e. deeds are left unexercised).
///     * If `getSkipNFT(owner) == false`, ERC20 mints / transfers to `owner`
///       will trigger NFT mints / transfers to `owner`, until the NFT balance of `owner`
///       is equal to its ERC20 balance divided by the unit (rounded down).
/// - Invariant: `_balanceOfNFT(owner) <= balanceOf(owner) / _unit()`.
/// - The gas costs for automatic minting / transferring / burning of NFTs is O(n).
///   This can exceed the block gas limit.
///   Applications and users may need to break up large transfers into a few transactions.
/// - This implementation uses safe transfers for automatic NFT transfers,
///   as all transfers require the recipient check by the ERC1155 spec.
/// - The ERC20 token allowances and ERC1155 token / operator approvals are separate.
/// - For MEV safety, users should NOT have concurrently open orders for the ERC20 and ERC1155.
abstract contract DN420 {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @dev Emitted when `owner` sets their skipNFT flag to `status`.
    event SkipNFTSet(address indexed owner, bool status);

    /// @dev Emitted when `owner` sets their owned checkpoint to `id`.
    event OwnedCheckpointSet(address indexed owner, uint256 id);

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
        0xb5a1de456fff688115a4f75380060c23c8532d14ff85f687cc871456d669393;

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

    /// @dev The lengths of the input arrays are not the same.
    error ArrayLengthsMismatch();

    /// @dev The unit must be greater than zero and less than `2**96`.
    error InvalidUnit();

    /// @dev Thrown when attempting to transfer tokens to the zero address.
    error TransferToZeroAddress();

    /// @dev Thrown when transferring an NFT
    /// and the caller is not the owner or an approved operator.
    error NotOwnerNorApproved();

    /// @dev Thrown when transferring an NFT and the from address is not the current owner.
    error TransferFromIncorrectOwner();

    /// @dev The amount of ERC1155 NFT transferred per token must be 1.
    error InvalidNFTAmount();

    /// @dev The function selector is not recognized.
    error FnSelectorNotRecognized();

    /// @dev Cannot safely transfer to a contract that does not implement
    /// the ERC1155Receiver interface.
    error TransferToNonERC1155ReceiverImplementer();

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

    /// @dev The ZKsync Permit2 deployment.
    /// If deploying on ZKsync or Abstract, override `_isPermit2(address)` to check against this too.
    /// [Etherscan](https://era.zksync.network/address/0x0000000000225e31D15943971F47aD3022F714Fa)
    address internal constant _ZKSYNC_PERMIT_2 = 0x0000000000225e31D15943971F47aD3022F714Fa;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Struct containing an address's token data and settings.
    struct AddressData {
        // Auxiliary data.
        uint88 aux;
        // Flags for `initialized` and `skipNFT`.
        uint8 flags;
        // The index which to start scanning backwards for burnable / transferable token IDs.
        uint32 ownedCheckpoint;
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
        // This is greater than or equal to the largest NFT ID minted thus far.
        // A non-zero value is used to denote that the contract has been initialized.
        uint32 tokenIdUpTo;
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
    ///
    /// Note: The `initialSupplyOwner` will have their skip NFT status set to true.
    function _initializeDN420(uint256 initialTokenSupply, address initialSupplyOwner)
        internal
        virtual
    {
        DN420Storage storage $ = _getDN420Storage();

        if ($.tokenIdUpTo != 0) revert DNAlreadyInitialized();
        unchecked {
            $.tokenIdUpTo = uint32((initialTokenSupply / _unit()) | 1);
            if (_unit() - 1 >= 2 ** 96 - 1) revert InvalidUnit();
        }
        $.nextTokenId = 1;

        if (initialTokenSupply != 0) {
            if (initialSupplyOwner == address(0)) revert TransferToZeroAddress();
            if (_totalSupplyOverflows(initialTokenSupply)) revert TotalSupplyOverflow();

            $.totalSupply = uint96(initialTokenSupply);

            AddressData storage initialOwnerAddressData = $.addressData[initialSupplyOwner];
            initialOwnerAddressData.balance = uint96(initialTokenSupply);

            /// @solidity memory-safe-assembly
            assembly {
                // Emit the ERC20 {Transfer} event.
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
    /// Note: The return value MUST be kept constant after `_initializeDN420` is called.
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

    /// @dev Returns the decimals places of the ERC20 token. Always 18.
    function decimals() public pure returns (uint8) {
        return 18;
    }

    /// @dev Returns the amount of ERC20 tokens in existence.
    function totalSupply() public view virtual returns (uint256) {
        return uint256(_getDN420Storage().totalSupply);
    }

    /// @dev Returns the amount of ERC20 tokens owned by `owner`.
    function balanceOf(address owner) public view virtual returns (uint256) {
        return _getDN420Storage().addressData[owner].balance;
    }

    /// @dev Returns the amount of ERC20 tokens that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender) public view returns (uint256) {
        if (_givePermit2DefaultInfiniteAllowance() && _isPermit2(spender)) {
            uint8 flags = _getDN420Storage().addressData[owner].flags;
            if ((flags & _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG) == uint256(0)) {
                return type(uint256).max;
            }
        }
        return _ref(_getDN420Storage().allowance, owner, spender).value;
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's ERC20 tokens.
    ///
    /// Emits an ERC20 {Approval} event.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    /// @dev Transfer `amount` ERC20 tokens from the caller to `to`.
    ///
    /// Will burn sender's ERC1155 NFTs if balance after transfer is less than
    /// the amount required to support the current NFT balance.
    ///
    /// Will mint ERC1155 NFTs to `to` if the recipient's new balance supports
    /// additional ERC1155 NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///
    /// Requirements:
    /// - `from` must at least have `amount` ERC20 tokens.
    ///
    /// Emits an ERC1155 {TransferBatch} event for direct transfers (if any).
    /// Emits an ERC1155 {TransferBatch} event for mints (if any).
    /// Emits an ERC1155 {TransferBatch} event for burns (if any).
    /// Emits an ERC20 {Transfer} event.
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _transfer(msg.sender, to, amount, "");
        return true;
    }

    /// @dev Transfers `amount` ERC20 tokens from `from` to `to`.
    ///
    /// Note: Does not update the ERC20 allowance if it is the maximum uint256 value.
    ///
    /// Will burn sender ERC1155 NFTs if balance after transfer is less than
    /// the amount required to support the current ERC1155 NFT balance.
    ///
    /// Will mint ERC1155 NFTs to `to` if the recipient's new balance supports
    /// additional ERC1155 NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///
    /// Requirements:
    /// - `from` must at least have `amount` ERC20 tokens.
    /// - The caller must have at least `amount` of ERC20 allowance to transfer the tokens of `from`.
    ///
    /// Emits a {Transfer} event.
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        Uint256Ref storage a = _ref(_getDN420Storage().allowance, from, msg.sender);

        uint256 allowed = _givePermit2DefaultInfiniteAllowance() && _isPermit2(msg.sender)
            && (_getDN420Storage().addressData[from].flags & _ADDRESS_DATA_OVERRIDE_PERMIT2_FLAG)
                == uint256(0) ? type(uint256).max : a.value;

        if (allowed != type(uint256).max) {
            if (amount > allowed) revert InsufficientAllowance();
            unchecked {
                a.value = allowed - amount;
            }
        }
        _transfer(from, to, amount, "");
        return true;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          PERMIT2                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Whether Permit2 has infinite ERC20 allowances by default for all owners.
    /// For signature-based allowance granting for single transaction ERC20 `transferFrom`.
    /// To enable, override this function to return true.
    function _givePermit2DefaultInfiniteAllowance() internal view virtual returns (bool) {
        return false;
    }

    /// @dev Returns checks if `sender` is the canonical Permit2 address.
    /// If on ZKsync, override this function to check against `_ZKSYNC_PERMIT_2` as well.
    function _isPermit2(address sender) internal view virtual returns (bool) {
        return sender == _PERMIT2;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                  INTERNAL MINT FUNCTIONS                   */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Mints `amount` ERC20 tokens to `to`, increasing the total supply.
    ///
    /// Will mint ERC1155 NFTs to `to` if the recipient's new balance supports
    /// additional ERC1155 NFTs ***AND*** the `to` address's skipNFT flag is set to false.
    ///
    /// Emits an ERC1155 {TransferBatch} event for mints (if any).
    /// Emits an ERC20 {Transfer} event.
    function _mint(address to, uint256 amount, bytes memory data) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        DN420Storage storage $ = _getDN420Storage();
        if ($.tokenIdUpTo == uint256(0)) revert DNNotInitialized();
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
                uint256 totalSupply_ = uint256($.totalSupply) + amount;
                $.totalSupply = uint96(totalSupply_);
                uint256 overflows = _toUint(_totalSupplyOverflows(totalSupply_));
                if (overflows | _toUint(totalSupply_ < amount) != 0) revert TotalSupplyOverflow();
                maxId = totalSupply_ / _unit();
                $.tokenIdUpTo = uint32(_max($.tokenIdUpTo, maxId));
            }
            if (!getSkipNFT(to)) {
                t.mintIds = _idsMalloc(_zeroFloorSub(t.toEnd, toAddressData.ownedCount));
                if (t.mintIds.length != 0) {
                    Bitmap storage toOwned = $.owned[to];
                    uint256 ownedCheckpoint = toAddressData.ownedCheckpoint;
                    uint256 id = _wrapNFTId($.nextTokenId, maxId);
                    // Mint loop.
                    for (uint256 n = t.mintIds.length;;) {
                        while (_get($.exists, id)) {
                            id = _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId);
                        }
                        _set($.exists, id, true);
                        _set(toOwned, id, true);
                        ownedCheckpoint = _max(ownedCheckpoint, id);
                        _idsAppend(t.mintIds, id);
                        id = _wrapNFTId(id + 1, maxId);
                        if (--n == uint256(0)) break;
                    }
                    toAddressData.ownedCheckpoint = uint32(ownedCheckpoint);
                    toAddressData.ownedCount = uint32(t.toEnd);
                    $.nextTokenId = uint32(id);
                    _batchTransferEmit(address(0), to, t.mintIds);
                }
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the ERC20 {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, to)))
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(
                _zeroAddresses(t.mintIds.length), _filled(t.mintIds.length, to), t.mintIds
            );
        }
        if (_hasCode(to)) _checkOnERC1155BatchReceived(address(0), to, t.mintIds, data);
    }

    /// @dev Mints `amount` tokens to `to`, increasing the total supply.
    /// This variant mints NFT tokens starting from ID `preTotalSupply / _unit() + 1`.
    /// The `nextTokenId` will not be changed.
    ///
    /// Will mint NFTs to `to` if the recipient's new balance supports
    /// additional NFTs ***AND*** the `to` address's skipNFT flag is set to false.
    ///
    /// Note:
    /// - May mint more NFTs than `amount / _unit()`.
    ///   The number of NFTs minted is what is needed to make `to`'s NFT balance whole.
    /// - Token IDs may wrap around `totalSupply / _unit()` back to 1.
    ///
    /// Emits an ERC1155 {TransferBatch} event for mints (if any).
    /// Emits an ERC20 {Transfer} event.
    function _mintNext(address to, uint256 amount, bytes memory data) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        DN420Storage storage $ = _getDN420Storage();
        if ($.tokenIdUpTo == uint256(0)) revert DNNotInitialized();
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
                $.tokenIdUpTo = uint32(_max($.tokenIdUpTo, maxId));
            }
            if (!getSkipNFT(to)) {
                t.mintIds = _idsMalloc(_zeroFloorSub(t.toEnd, toAddressData.ownedCount));
                if (t.mintIds.length != 0) {
                    Bitmap storage toOwned = $.owned[to];
                    uint256 ownedCheckpoint = toAddressData.ownedCheckpoint;
                    // Mint loop.
                    for (uint256 n = t.mintIds.length;;) {
                        while (_get($.exists, id)) {
                            id = _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId);
                        }
                        _set($.exists, id, true);
                        _set(toOwned, id, true);
                        ownedCheckpoint = _max(ownedCheckpoint, id);
                        _idsAppend(t.mintIds, id);
                        id = _wrapNFTId(id + 1, maxId);
                        if (--n == uint256(0)) break;
                    }
                    toAddressData.ownedCheckpoint = uint32(ownedCheckpoint);
                    toAddressData.ownedCount = uint32(t.toEnd);
                    _batchTransferEmit(address(0), to, t.mintIds);
                }
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the ERC20 {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, shl(96, to)))
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(
                _zeroAddresses(t.mintIds.length), _filled(t.mintIds.length, to), t.mintIds
            );
        }
        if (_hasCode(to)) _checkOnERC1155BatchReceived(address(0), to, t.mintIds, data);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                  INTERNAL BURN FUNCTIONS                   */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Burns `amount` ERC20 tokens from `from`, reducing the total supply.
    ///
    /// Will burn sender's ERC1155 NFTs if balance after transfer is less than
    /// the amount required to support the current ERC1155 NFT balance.
    ///
    /// Emits an ERC1155 {TransferBatch} event for burns (if any).
    /// Emits an ERC20 {Transfer} event.
    function _burn(address from, uint256 amount) internal virtual {
        DN420Storage storage $ = _getDN420Storage();
        if ($.tokenIdUpTo == uint256(0)) revert DNNotInitialized();
        AddressData storage fromAddressData = $.addressData[from];

        uint256[] memory ids;
        unchecked {
            uint256 fromBalance = fromAddressData.balance;
            if (amount > fromBalance) revert InsufficientBalance();

            fromAddressData.balance = uint96(fromBalance -= amount);
            $.totalSupply -= uint96(amount);

            Bitmap storage fromOwned = $.owned[from];
            uint256 fromIndex = fromAddressData.ownedCount;
            uint256 numNFTBurns = _zeroFloorSub(fromIndex, fromBalance / _unit());

            if (numNFTBurns != 0) {
                ids = _idsMalloc(numNFTBurns);
                fromAddressData.ownedCount = uint32(fromIndex - numNFTBurns);
                uint256 id = fromAddressData.ownedCheckpoint;
                // Burn loop.
                while (true) {
                    id = _findLastSet(fromOwned, id);
                    if (id == uint256(0)) id = _findLastSet(fromOwned, $.tokenIdUpTo);
                    _set(fromOwned, id, false);
                    _set($.exists, id, false);
                    _idsAppend(ids, id);
                    if (--numNFTBurns == uint256(0)) break;
                }
                fromAddressData.ownedCheckpoint = uint32(id);
                _batchTransferEmit(from, address(0), ids);
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the ERC20 {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), 0)
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(_filled(ids.length, from), _zeroAddresses(ids.length), ids);
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                INTERNAL TRANSFER FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Moves `amount` of ERC20 tokens from `from` to `to`.
    ///
    /// Will burn sender ERC1155 NFTs if balance after transfer is less than
    /// the amount required to support the current ERC1155 NFT balance.
    ///
    /// Will mint ERC1155 NFTs to `to` if the recipient's new balance supports
    /// additional ERC1155 NFTs ***AND*** the `to` address's skipNFT flag is
    /// set to false.
    ///.
    /// Emits an ERC1155 {TransferBatch} event for direct transfers (if any).
    /// Emits an ERC1155 {TransferBatch} event for mints (if any).
    /// Emits an ERC1155 {TransferBatch} event for burns (if any).
    /// Emits an ERC20 {Transfer} event
    function _transfer(address from, address to, uint256 amount, bytes memory data)
        internal
        virtual
    {
        if (to == address(0)) revert TransferToZeroAddress();

        DN420Storage storage $ = _getDN420Storage();
        if ($.tokenIdUpTo == uint256(0)) revert DNNotInitialized();
        AddressData storage fromAddressData = $.addressData[from];
        AddressData storage toAddressData = $.addressData[to];

        _DNTransferTemps memory t;
        t.fromOwnedCount = fromAddressData.ownedCount;
        t.toOwnedCount = toAddressData.ownedCount;

        unchecked {
            uint256 toBalance;
            uint256 fromBalance = fromAddressData.balance;
            if (amount > fromBalance) revert InsufficientBalance();

            fromAddressData.balance = uint96(fromBalance -= amount);
            toAddressData.balance = uint96(toBalance = uint256(toAddressData.balance) + amount);

            t.numNFTBurns = _zeroFloorSub(t.fromOwnedCount, fromBalance / _unit());

            if (!getSkipNFT(to)) {
                if (from == to) t.toOwnedCount = t.fromOwnedCount - t.numNFTBurns;
                t.numNFTMints = _zeroFloorSub(toBalance / _unit(), t.toOwnedCount);
            }
        }

        unchecked {
            while (_useDirectTransfersIfPossible()) {
                uint256 n = _min(t.fromOwnedCount, _min(t.numNFTBurns, t.numNFTMints));
                if (n == uint256(0)) break;
                t.numNFTBurns -= n;
                t.numNFTMints -= n;
                if (from == to) {
                    t.toOwnedCount += n;
                    break;
                }
                t.directIds = _idsMalloc(n);
                Bitmap storage fromOwned = $.owned[from];
                Bitmap storage toOwned = $.owned[to];

                uint256 id = fromAddressData.ownedCheckpoint;
                fromAddressData.ownedCount = uint32(t.fromOwnedCount -= n);
                toAddressData.ownedCheckpoint = uint32(_max(toAddressData.ownedCheckpoint, id));
                toAddressData.ownedCount = uint32(t.toOwnedCount += n);
                // Direct transfer loop.
                while (true) {
                    id = _findLastSet(fromOwned, id);
                    if (id == uint256(0)) id = _findLastSet(fromOwned, $.tokenIdUpTo);
                    _set(fromOwned, id, false);
                    _set(toOwned, id, true);
                    _idsAppend(t.directIds, id);
                    if (--n == uint256(0)) break;
                }
                fromAddressData.ownedCheckpoint = uint32(id);
                _batchTransferEmit(from, to, t.directIds);
                break;
            }

            if (t.numNFTBurns != 0) {
                uint256 n = t.numNFTBurns;
                t.burnIds = _idsMalloc(n);
                Bitmap storage fromOwned = $.owned[from];
                fromAddressData.ownedCount = uint32(t.fromOwnedCount - n);
                uint256 id = fromAddressData.ownedCheckpoint;
                // Burn loop.
                while (true) {
                    id = _findLastSet(fromOwned, id);
                    if (id == uint256(0)) id = _findLastSet(fromOwned, $.tokenIdUpTo);
                    _set(fromOwned, id, false);
                    _set($.exists, id, false);
                    _idsAppend(t.burnIds, id);
                    if (--n == uint256(0)) break;
                }
                fromAddressData.ownedCheckpoint = uint32(id);
                _batchTransferEmit(from, address(0), t.burnIds);
            }

            if (t.numNFTMints != 0) {
                uint256 n = t.numNFTMints;
                t.mintIds = _idsMalloc(n);
                Bitmap storage toOwned = $.owned[to];
                toAddressData.ownedCount = uint32(t.toOwnedCount + n);
                uint256 maxId = $.totalSupply / _unit();
                uint256 id = _wrapNFTId($.nextTokenId, maxId);
                uint256 ownedCheckpoint = toAddressData.ownedCheckpoint;
                // Mint loop.
                while (true) {
                    while (_get($.exists, id)) {
                        id = _wrapNFTId(_findFirstUnset($.exists, id + 1, maxId), maxId);
                    }
                    _set($.exists, id, true);
                    _set(toOwned, id, true);
                    ownedCheckpoint = _max(ownedCheckpoint, id);
                    _idsAppend(t.mintIds, id);
                    id = _wrapNFTId(id + 1, maxId);
                    if (--n == uint256(0)) break;
                }
                toAddressData.ownedCheckpoint = uint32(ownedCheckpoint);
                $.nextTokenId = uint32(id);
                _batchTransferEmit(address(0), to, t.mintIds);
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the ERC20 {Transfer} event.
            mstore(0x00, amount)
            // forgefmt: disable-next-item
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), shr(96, shl(96, to)))
        }
        if (_useAfterNFTTransfers()) {
            uint256[] memory ids = t.directIds;
            unchecked {
                _afterNFTTransfers(
                    _concat(
                        _filled(ids.length + t.numNFTBurns, from), _zeroAddresses(t.numNFTMints)
                    ),
                    _concat(
                        _concat(_filled(ids.length, to), _zeroAddresses(t.numNFTBurns)),
                        _filled(t.numNFTMints, to)
                    ),
                    _concat(_concat(ids, t.burnIds), t.mintIds)
                );
            }
        }
        if (_hasCode(to)) {
            _checkOnERC1155BatchReceived(from, to, t.directIds, data);
            _checkOnERC1155BatchReceived(address(0), to, t.mintIds, data);
        }
    }

    /// @dev Transfers ERC1155 `id` from `from` to `to`.
    ///
    /// Requirements:
    /// - `to` cannot be the zero address.
    /// - `from` must have `id`.
    /// - If `by` is not the zero address, it must be either `from`,
    ///   or approved to manage the ERC1155 tokens of `from`.
    /// - If `to` refers to a smart contract, it must implement
    ///   {ERC1155-onERC1155Reveived}, which is called upon a batch transfer.
    ///
    /// Emits an ERC1155 {TransferSingle} event.
    /// Emits an ERC20 {Transfer} event.
    function _safeTransferNFT(address by, address from, address to, uint256 id, bytes memory data)
        internal
        virtual
    {
        if (to == address(0)) revert TransferToZeroAddress();

        DN420Storage storage $ = _getDN420Storage();
        if ($.tokenIdUpTo == uint256(0)) revert DNNotInitialized();

        if (_toUint(by == address(0)) | _toUint(by == from) == uint256(0)) {
            if (!isApprovedForAll(from, by)) revert NotOwnerNorApproved();
        }

        Bitmap storage fromOwned = $.owned[from];
        if (!_owns(fromOwned, id)) revert TransferFromIncorrectOwner();
        _set(fromOwned, id, false);
        _set($.owned[to], id, true);

        uint256 unit = _unit();
        AddressData storage fromAddressData = $.addressData[from];
        AddressData storage toAddressData = $.addressData[to];
        /// @solidity memory-safe-assembly
        assembly {
            let diff := shl(128, or(shl(32, unit), 1))
            sstore(fromAddressData.slot, sub(sload(fromAddressData.slot), diff))
            let toPacked := sload(toAddressData.slot)
            let toCheckpoint := and(0xffffffff, shr(96, toPacked))
            // forgefmt: disable-next-item
            sstore(toAddressData.slot, add(diff,
                xor(toPacked, shl(96, mul(gt(id, toCheckpoint), xor(id, toCheckpoint))))))
        }
        /// @solidity memory-safe-assembly
        assembly {
            from := shr(96, shl(96, from))
            to := shr(96, shl(96, to))
            // Emit the ERC1155 {TransferSingle} event.
            mstore(0x00, id)
            mstore(0x20, 1)
            log4(0x00, 0x40, _TRANSFER_SINGLE_EVENT_SIGNATURE, caller(), from, to)
            // Emit the ERC20 {Transfer} event.
            mstore(0x00, unit)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, from, to)
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(_filled(1, from), _filled(1, to), _filled(1, id));
        }
        if (_hasCode(to)) _checkOnERC1155Received(from, to, id, data);
    }

    /// @dev Transfers `id` from `from` to `to`.
    ///
    /// Requirements:
    /// - `to` cannot be the zero address.
    /// - `from` must have `ids`.
    /// - If `by` is not the zero address, it must be either `from`,
    ///   or approved to manage the ERC1155 tokens of `from`.
    /// - If `to` refers to a smart contract, it must implement
    ///   {ERC1155-onERC1155Reveived}, which is called upon a batch transfer.
    ///
    /// Emits an ERC1155 {TransferBatch} event.
    /// Emits an ERC20 {Transfer} event.
    function _safeBatchTransferNFTs(
        address by,
        address from,
        address to,
        uint256[] memory ids,
        bytes memory data
    ) internal virtual {
        if (to == address(0)) revert TransferToZeroAddress();

        DN420Storage storage $ = _getDN420Storage();
        if ($.tokenIdUpTo == uint256(0)) revert DNNotInitialized();

        if (_toUint(by == address(0)) | _toUint(by == from) == uint256(0)) {
            if (!isApprovedForAll(from, by)) revert NotOwnerNorApproved();
        }

        uint256 amount;
        uint256 upTo;
        AddressData storage fromAddressData = $.addressData[from];
        AddressData storage toAddressData = $.addressData[to];
        unchecked {
            uint256 n = ids.length;
            amount = n * _unit();
            Bitmap storage fromOwned = $.owned[from];
            Bitmap storage toOwned = $.owned[to];
            while (n != 0) {
                uint256 id = _get(ids, --n);
                if (!_owns(fromOwned, id)) revert TransferFromIncorrectOwner();
                _set(fromOwned, id, false);
                _set(toOwned, id, true);
                upTo = _max(upTo, id);
            }
        }
        /// @solidity memory-safe-assembly
        assembly {
            let diff := shl(128, or(shl(32, amount), mload(ids)))
            sstore(fromAddressData.slot, sub(sload(fromAddressData.slot), diff))
            let toPacked := sload(toAddressData.slot)
            let toCheckpoint := and(0xffffffff, shr(96, toPacked))
            // forgefmt: disable-next-item
            sstore(toAddressData.slot, add(diff,
                xor(toPacked, shl(96, mul(gt(upTo, toCheckpoint), xor(upTo, toCheckpoint))))))
        }
        _batchTransferEmit(from, to, ids);
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the ERC20 {Transfer} event.
            mstore(0x00, amount)
            // forgefmt: disable-next-item
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), shr(96, shl(96, to)))
        }
        if (_useAfterNFTTransfers()) {
            _afterNFTTransfers(_filled(ids.length, from), _filled(ids.length, to), ids);
        }
        if (_hasCode(to)) _checkOnERC1155BatchReceived(from, to, ids, data);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 INTERNAL APPROVE FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Sets `amount` as the allowance of `spender` over the tokens of `owner`.
    ///
    /// Emits a {Approval} event.
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        if (_givePermit2DefaultInfiniteAllowance() && _isPermit2(spender)) {
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
    function getSkipNFT(address owner) public view virtual returns (bool result) {
        uint8 flags = _getDN420Storage().addressData[owner].flags;
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
        AddressData storage d = _getDN420Storage().addressData[owner];
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

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                 OWNED CHECKPOINT FUNCTIONS                 */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the owned checkpoint of `owner`.
    function getOwnedCheckpoint(address owner) public view virtual returns (uint256) {
        return _getDN420Storage().addressData[owner].ownedCheckpoint;
    }

    /// @dev Just in case the collection gets too large and the caller needs
    /// to set their owned checkpoint manually to skip large bitmap scans
    /// for automatic ERC1155 NFT burns upon ERC20 transfers.
    function setOwnedCheckpoint(uint256 id) public virtual {
        _setOwnedCheckpoint(msg.sender, id);
    }

    /// @dev Sets the owned checkpoint of `owner` to `id`.
    /// `id` will be clamped to `[1..tokenIdUpTo]`.
    function _setOwnedCheckpoint(address owner, uint256 id) internal virtual {
        DN420Storage storage $ = _getDN420Storage();
        id = _min(_max(1, id), $.tokenIdUpTo);
        $.addressData[owner].ownedCheckpoint = uint32(id);
        emit OwnedCheckpointSet(owner, id);
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     ERC1155 OPERATIONS                     */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns if `owner` owns ERC1155 `id`.
    function owns(address owner, uint256 id) public view virtual returns (bool) {
        return _owns(_getDN420Storage().owned[owner], id);
    }

    /// @dev Returns if the ERC1155 `id` is set in `owned`.
    function _owns(Bitmap storage owned, uint256 id) internal view virtual returns (bool) {
        return _get(owned, _restrictNFTId(id));
    }

    /// @dev Returns whether `operator` is approved to manage the ERC1155 tokens of `owner`.
    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return _ref(_getDN420Storage().operatorApprovals, owner, operator).value != 0;
    }

    /// @dev Sets whether `operator` is approved to manage the ERC1155 tokens of the caller.
    ///
    /// Emits a {ApprovalForAll} event.
    function setApprovalForAll(address operator, bool isApproved) public virtual {
        _setApprovalForAll(msg.sender, operator, isApproved);
    }

    /// @dev Sets whether `operator` is approved to manage the ERC1155 tokens of the caller.
    ///
    /// Emits a {ApprovalForAll} event.
    function _setApprovalForAll(address owner, address operator, bool isApproved)
        internal
        virtual
    {
        _ref(_getDN420Storage().operatorApprovals, owner, operator).value = _toUint(isApproved);
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {ApprovalForAll} event.
            mstore(0x00, isApproved)
            // forgefmt: disable-next-item
            log3(0x00, 0x20, _APPROVAL_FOR_ALL_EVENT_SIGNATURE,
                shr(96, shl(96, owner)), shr(96, shl(96, operator)))
        }
    }

    /// @dev Transfers the ERC1155 NFT at `id` from `from` to `to`.
    function safeTransferNFT(address from, address to, uint256 id, bytes memory data)
        public
        virtual
    {
        _safeTransferNFT(msg.sender, from, to, id, data);
    }

    /// @dev Transfers the ERC1155 NFTs at `ids` from `from` to `to`.
    function safeBatchTransferNFTs(
        address from,
        address to,
        uint256[] memory ids,
        bytes memory data
    ) public virtual {
        _safeBatchTransferNFTs(msg.sender, from, to, ids, data);
    }

    /// @dev Returns true if this contract implements the interface defined by `interfaceId`.
    /// See: https://eips.ethereum.org/EIPS/eip-165
    /// This function call must use less than 30000 gas.
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            let s := shr(224, interfaceId)
            // ERC165: 0x01ffc9a7, ERC1155: 0xd9b67a26, ERC1155MetadataURI: 0x0e89341c.
            result := or(or(eq(s, 0x01ffc9a7), eq(s, 0xd9b67a26)), eq(s, 0x0e89341c))
        }
    }

    /// @dev Returns `owner`'s ERC1155 NFT balance.
    function _balanceOfNFT(address owner) internal view virtual returns (uint256) {
        return _getDN420Storage().addressData[owner].ownedCount;
    }

    /// @dev Returns if the ERC1155 token `id` exists.
    function _exists(uint256 id) internal view virtual returns (bool) {
        return _get(_getDN420Storage().exists, _restrictNFTId(id));
    }

    /// @dev Returns the ERC1155 NFT IDs of `owner` in range `[lower, upper)`.
    /// Optimized for smaller bytecode size, as this function is intended for off-chain calling.
    function _findOwnedIds(address owner, uint256 lower, uint256 upper)
        internal
        view
        virtual
        returns (uint256[] memory ids)
    {
        unchecked {
            DN420Storage storage $ = _getDN420Storage();
            Bitmap storage owned = $.owned[owner];
            upper = _min(uint256($.tokenIdUpTo) + 1, upper);
            /// @solidity memory-safe-assembly
            assembly {
                ids := mload(0x40)
                let n := 0
                let s := shl(96, owned.slot)
                for { let id := lower } lt(id, upper) { id := add(1, id) } {
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

    /// @dev Fallback modifier for the regular ERC1155 functions and other functions.
    modifier dn420Fallback() virtual {
        uint256 fnSelector = _calldataload(0x00) >> 224;

        // We hide the regular ERC1155 functions that has variable amounts
        // in the fallback for ABI aesthetic purposes.

        // `safeTransferFrom(address,address,uint256,uint256,bytes)`.
        if (fnSelector == 0xf242432a) {
            if (_calldataload(0x64) != 1) revert InvalidNFTAmount();
            _safeTransferNFT(
                msg.sender, // `by`.
                address(uint160(_calldataload(0x04))), // `from`.
                address(uint160(_calldataload(0x24))), // `to`.
                _calldataload(0x44), // `id`.
                _calldataBytes(0x84) // `data`.
            );
            _return(1);
        }
        // `safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)`.
        if (fnSelector == 0x2eb2c2d6) {
            uint256[] memory ids = _calldataUint256Array(0x44);
            unchecked {
                uint256[] memory amounts = _calldataUint256Array(0x64);
                uint256 n = ids.length;
                if (n != amounts.length) revert ArrayLengthsMismatch();
                while (n-- != 0) if (_get(amounts, n) != 1) revert InvalidNFTAmount();
            }
            _safeBatchTransferNFTs(
                msg.sender,
                address(uint160(_calldataload(0x04))), // `from`.
                address(uint160(_calldataload(0x24))), // `to`.
                ids,
                _calldataBytes(0x84) // `data.
            );
            _return(1);
        }
        // `balanceOfBatch(address[],uint256[])`.
        if (fnSelector == 0x4e1273f4) {
            uint256[] memory owners = _calldataUint256Array(0x04);
            uint256[] memory ids = _calldataUint256Array(0x24);
            unchecked {
                uint256 n = ids.length;
                if (owners.length != n) revert ArrayLengthsMismatch();
                uint256[] memory result = _idsMalloc(n);
                while (n-- != 0) {
                    address owner = address(uint160(_get(owners, n)));
                    _set(result, n, _toUint(owns(owner, _get(ids, n))));
                }
                /// @solidity memory-safe-assembly
                assembly {
                    mstore(sub(result, 0x20), 0x20)
                    return(sub(result, 0x20), add(0x40, shl(5, mload(result))))
                }
            }
        }
        // `balanceOf(address,uint256)`.
        if (fnSelector == 0x00fdd58e) {
            bool result = owns(
                address(uint160(_calldataload(0x04))), // `owner`.
                _calldataload(0x24) // `id`.
            );
            _return(_toUint(result));
        }
        // `implementsDN420()`.
        if (fnSelector == 0x0e0b0984) {
            _return(1);
        }
        _;
    }

    /// @dev Fallback function for regular ERC1155 functions and other functions.
    /// Override this if you need to implement your custom
    /// fallback with utilities like Solady's `LibZip.cdFallback()`.
    /// And always remember to always wrap the fallback with `dn420Fallback`.
    fallback() external payable virtual dn420Fallback {
        revert FnSelectorNotRecognized(); // Not mandatory. Just for quality of life.
    }

    /// @dev This is to silence the compiler warning.
    /// Override and remove the revert if you want your contract to receive ETH via receive.
    receive() external payable virtual {
        if (msg.value != 0) revert();
    }

    /// @dev Perform a call to invoke {IERC1155Receiver-onERC1155Received} on `to`.
    /// Reverts if the target does not support the function correctly.
    function _checkOnERC1155Received(address from, address to, uint256 id, bytes memory data)
        private
    {
        /// @solidity memory-safe-assembly
        assembly {
            // Prepare the calldata.
            let m := mload(0x40)
            // `onERC1155Received(address,address,uint256,uint256,bytes)`.
            mstore(m, 0xf23a6e61)
            mstore(add(m, 0x20), caller())
            mstore(add(m, 0x40), shr(96, shl(96, from)))
            mstore(add(m, 0x60), id)
            mstore(add(m, 0x80), 1)
            mstore(add(m, 0xa0), 0xa0)
            let n := mload(data)
            mstore(add(m, 0xc0), n)
            if n { pop(staticcall(gas(), 4, add(data, 0x20), n, add(m, 0xe0), n)) }
            // Revert if the call reverts.
            if iszero(call(gas(), to, 0, add(m, 0x1c), add(0xc4, n), m, 0x20)) {
                if returndatasize() {
                    // Bubble up the revert if the call reverts.
                    returndatacopy(m, 0x00, returndatasize())
                    revert(m, returndatasize())
                }
            }
            // Load the returndata and compare it with the function selector.
            if iszero(eq(mload(m), shl(224, 0xf23a6e61))) {
                mstore(0x00, 0x9c05499b) // `TransferToNonERC1155ReceiverImplementer()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Perform a call to invoke {IERC1155Receiver-onERC1155BatchReceived} on `to`.
    /// Reverts if the target does not support the function correctly.
    function _checkOnERC1155BatchReceived(
        address from,
        address to,
        uint256[] memory ids,
        bytes memory data
    ) private {
        if (ids.length == uint256(0)) return;
        /// @solidity memory-safe-assembly
        assembly {
            // Prepare the calldata.
            let m := mload(0x40)
            // `onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)`.
            mstore(m, 0xbc197c81)
            mstore(add(m, 0x20), caller())
            mstore(add(m, 0x40), shr(96, shl(96, from)))
            // Copy the `ids`.
            mstore(add(m, 0x60), 0xa0)
            let o := add(m, 0xc0)
            {
                let n := add(0x20, shl(5, mload(ids)))
                pop(staticcall(gas(), 4, ids, n, o, n))
            }
            // Copy the `amounts`.
            mstore(add(m, 0x80), add(0xa0, returndatasize()))
            mstore(add(m, 0xa0), add(returndatasize(), add(0xa0, returndatasize())))
            o := add(o, returndatasize())
            mstore(o, mload(ids))
            let end := add(o, returndatasize())
            for { o := add(o, 0x20) } iszero(eq(o, end)) { o := add(0x20, o) } { mstore(o, 1) }
            // Copy the `data`.
            {
                let n := add(0x20, mload(data))
                pop(staticcall(gas(), 4, data, n, end, n))
            }
            // Revert if the call reverts.
            // forgefmt: disable-next-item
            if iszero(call(gas(), to, 0,
                add(m, 0x1c), sub(add(end, returndatasize()), add(m, 0x1c)), m, 0x20)) {
                if returndatasize() {
                    // Bubble up the revert if the call reverts.
                    returndatacopy(m, 0x00, returndatasize())
                    revert(m, returndatasize())
                }
            }
            // Load the returndata and compare it with the function selector.
            if iszero(eq(mload(m), shl(224, 0xbc197c81))) {
                mstore(0x00, 0x9c05499b) // `TransferToNonERC1155ReceiverImplementer()`.
                revert(0x1c, 0x04)
            }
        }
    }

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

    /// @dev Returns the index of the most significant set bit in `[0..upTo]`.
    /// If no set bit is found, returns zero.
    function _findLastSet(Bitmap storage bitmap, uint256 upTo)
        internal
        view
        returns (uint256 setBitIndex)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let s := shl(96, bitmap.slot) // Storage offset of the bitmap.
            let bucket := add(s, shr(8, upTo))
            let bits := shr(and(0xff, not(upTo)), shl(and(0xff, not(upTo)), sload(bucket)))
            if iszero(or(bits, eq(bucket, s))) {
                for {} 1 {} {
                    bucket := sub(bucket, 1)
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
                setBitIndex := mul(r, iszero(gt(r, upTo)))
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

    /// @dev Creates an array with length `n` that is suitable for `_idsAppend`.
    function _idsMalloc(uint256 n) private pure returns (uint256[] memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := add(0x20, mload(0x40))
            let offset := add(result, 0x20)
            mstore(sub(result, 0x20), offset)
            mstore(result, n)
            mstore(0x40, add(offset, shl(5, n)))
        }
    }

    /// @dev Appends `id` to `a`. `a` must be created via `_idsMalloc`.
    function _idsAppend(uint256[] memory a, uint256 id) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            let offset := mload(sub(a, 0x20))
            mstore(offset, id)
            mstore(sub(a, 0x20), add(offset, 0x20))
        }
    }

    /// @dev Emits the ERC1155 {TransferBatch} event with `from`, `to`, and `ids`.
    function _batchTransferEmit(address from, address to, uint256[] memory ids) private {
        if (ids.length == uint256(0)) return;
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, 0x40)
            let o := add(m, 0x40)
            // We have to copy the `ids`, as it might not be from `_idsMalloc`.
            // See: `_safeBatchTransferNFTs`.
            {
                let n := add(0x20, shl(5, mload(ids)))
                pop(staticcall(gas(), 4, ids, n, o, n))
            }
            mstore(add(m, 0x20), add(0x40, returndatasize()))
            o := add(o, returndatasize())
            // Store the length of `amounts`.
            mstore(o, mload(ids))
            let end := add(o, returndatasize())
            for { o := add(o, 0x20) } iszero(eq(o, end)) { o := add(0x20, o) } { mstore(o, 1) }
            // Emit a {TransferBatch} event.
            // forgefmt: disable-next-item
            log4(m, sub(o, m), _TRANSFER_BATCH_EVENT_SIGNATURE, caller(),
                shr(96, shl(96, from)), shr(96, shl(96, to)))
        }
    }

    /// @dev Returns an array of zero addresses.
    function _zeroAddresses(uint256 n) private pure returns (address[] memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(0x40, add(add(result, 0x20), shl(5, n)))
            mstore(result, n)
            calldatacopy(add(result, 0x20), calldatasize(), shl(5, n))
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
        pure
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
                function copy(dst_, src_, n_) -> _end {
                    _end := add(dst_, shl(5, n_))
                    if n_ {
                        for { let d_ := sub(src_, dst_) } 1 {} {
                            mstore(dst_, mload(add(dst_, d_)))
                            dst_ := add(dst_, 0x20)
                            if eq(dst_, _end) { break }
                        }
                    }
                }
                mstore(0x40, copy(copy(add(result, 0x20), add(a, 0x20), aN), add(b, 0x20), bN))
            }
        }
    }

    /// @dev Concatenates the arrays.
    function _concat(address[] memory a, address[] memory b)
        private
        pure
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

    /// @dev Struct of temporary variables for mints.
    struct _DNMintTemps {
        uint256 toEnd;
        uint256[] mintIds;
    }

    /// @dev Struct of temporary variables for transfers.
    struct _DNTransferTemps {
        uint256 numNFTBurns;
        uint256 numNFTMints;
        uint256 fromOwnedCount;
        uint256 toOwnedCount;
        uint256 ownedCheckpoint;
        uint256[] directIds;
        uint256[] burnIds;
        uint256[] mintIds;
    }

    /// @dev Returns if `a` has bytecode of non-zero length.
    function _hasCode(address a) private view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := extcodesize(a) // Can handle dirty upper bits.
        }
    }

    /// @dev Returns a `uint256[] calldata` at `offset` in calldata as `uint256[] memory`.
    function _calldataUint256Array(uint256 offset) private pure returns (uint256[] memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let o := add(0x04, calldataload(offset))
            let n := calldataload(o)
            mstore(result, n)
            calldatacopy(add(0x20, result), add(o, 0x20), shl(5, n))
            mstore(0x40, add(add(0x20, result), shl(5, n)))
        }
    }

    /// @dev Returns a `bytes calldata` at `offset` in calldata as `bytes memory`.
    function _calldataBytes(uint256 offset) private pure returns (bytes memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let o := add(0x04, calldataload(offset))
            let n := calldataload(o)
            mstore(result, n)
            calldatacopy(add(0x20, result), add(o, 0x20), n)
            o := add(add(0x20, result), n)
            mstore(o, 0) // Zeroize the slot after the last word.
            mstore(0x40, add(0x20, o))
        }
    }

    /// @dev Returns `a[i]` without bounds check.
    function _get(uint256[] memory a, uint256 i) private pure returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(add(add(0x20, a), shl(5, i)))
        }
    }

    /// @dev Sets `a[i]` to `value`, without bounds check.
    function _set(uint256[] memory a, uint256 i, uint256 value) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(add(add(0x20, a), shl(5, i)), value)
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
