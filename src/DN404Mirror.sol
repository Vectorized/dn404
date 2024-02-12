// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/// @title DN404Mirror
/// @notice DN404Mirror provides an interface for interacting with the
/// NFT tokens in a DN404 implementation.
///
/// @author vectorized.eth (@optimizoor)
/// @author Quit (@0xQuit)
/// @author Michael Amadi (@AmadiMichaels)
/// @author cygaar (@0xCygaar)
/// @author Thomas (@0xjustadev)
/// @author Harrison (@PopPunkOnChain)
///
/// @dev Note:
/// - The ERC721 data is stored in the base DN404 contract.
contract DN404Mirror {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Emitted when token `id` is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /// @dev Emitted when `owner` enables `account` to manage the `id` token.
    event Approval(address indexed owner, address indexed account, uint256 indexed id);

    /// @dev Emitted when `owner` enables or disables `operator` to manage all of their tokens.
    event ApprovalForAll(address indexed owner, address indexed operator, bool isApproved);

    /// @dev `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    /// @dev `keccak256(bytes("ApprovalForAll(address,address,bool)"))`.
    uint256 private constant _APPROVAL_FOR_ALL_EVENT_SIGNATURE =
        0x17307eab39ab6107e8899845ad3d59bd9653f200f220920489ca2b5937696c31;

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CUSTOM ERRORS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Thrown when a call for an NFT function did not originate
    /// from the base DN404 contract.
    error SenderNotBase();

    /// @dev Thrown when a call for an NFT function did not originate from the deployer.
    error SenderNotDeployer();

    /// @dev Thrown when transferring an NFT to a contract address that
    /// does not implement ERC721Receiver.
    error TransferToNonERC721ReceiverImplementer();

    /// @dev Thrown when linking to the DN404 base contract and the
    /// DN404 supportsInterface check fails or the call reverts.
    error CannotLink();

    /// @dev Thrown when a linkMirrorContract call is received and the
    /// NFT mirror contract has already been linked to a DN404 base contract.
    error AlreadyLinked();

    /// @dev Thrown when retrieving the base DN404 address when a link has not
    /// been established.
    error NotLinked();

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                          STORAGE                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Struct contain the NFT mirror contract storage.
    struct DN404NFTStorage {
        address baseERC20;
        address deployer;
    }

    /// @dev Returns a storage pointer for DN404NFTStorage.
    function _getDN404NFTStorage() internal pure virtual returns (DN404NFTStorage storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            // `uint72(bytes9(keccak256("DN404_MIRROR_STORAGE")))`.
            $.slot := 0x3602298b8c10b01230 // Truncate to 9 bytes to reduce bytecode size.
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CONSTRUCTOR                         */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    constructor(address deployer) {
        // For non-proxies, we will store the deployer so that only the deployer can
        // link the base contract.
        _getDN404NFTStorage().deployer = deployer;
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     ERC721 OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the token collection name from the base DN404 contract.
    function name() public view virtual returns (string memory result) {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(0x00, 0x06fdde03) // `name()`.
            if iszero(staticcall(gas(), base, 0x1c, 0x04, 0x00, 0x00)) {
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            returndatacopy(0x00, 0x00, 0x20)
            returndatacopy(result, mload(0x00), 0x20)
            returndatacopy(add(result, 0x20), add(mload(0x00), 0x20), mload(result))
            mstore(0x40, add(add(result, 0x20), mload(result)))
        }
    }

    /// @dev Returns the token collection symbol from the base DN404 contract.
    function symbol() public view virtual returns (string memory result) {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(0x00, 0x95d89b41) // `symbol()`.
            if iszero(staticcall(gas(), base, 0x1c, 0x04, 0x00, 0x00)) {
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            returndatacopy(0x00, 0x00, 0x20)
            returndatacopy(result, mload(0x00), 0x20)
            returndatacopy(add(result, 0x20), add(mload(0x00), 0x20), mload(result))
            mstore(0x40, add(add(result, 0x20), mload(result)))
        }
    }

    /// @dev Returns the Uniform Resource Identifier (URI) for token `id` from
    /// the base DN404 contract.
    function tokenURI(uint256 id) public view virtual returns (string memory result) {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(0x20, id)
            mstore(0x00, 0xc87b56dd) // `tokenURI()`.
            if iszero(staticcall(gas(), base, 0x1c, 0x24, 0x00, 0x00)) {
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            returndatacopy(0x00, 0x00, 0x20)
            returndatacopy(result, mload(0x00), 0x20)
            returndatacopy(add(result, 0x20), add(mload(0x00), 0x20), mload(result))
            mstore(0x40, add(add(result, 0x20), mload(result)))
        }
    }

    /// @dev Returns the total NFT supply from the base DN404 contract.
    function totalSupply() public view virtual returns (uint256 result) {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0xe2c79281) // `totalNFTSupply()`.
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), base, 0x1c, 0x04, 0x00, 0x20))
            ) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            result := mload(0x00)
        }
    }

    /// @dev Returns the number of NFT tokens owned by `owner` from the base DN404 contract.
    ///
    /// Requirements:
    /// - `owner` must not be the zero address.
    function balanceOf(address owner) public view virtual returns (uint256 result) {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, shr(96, shl(96, owner)))
            mstore(0x00, 0xf5b100ea) // `balanceOfNFT(address)`.
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), base, 0x1c, 0x24, 0x00, 0x20))
            ) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            result := mload(0x00)
        }
    }

    /// @dev Returns the owner of token `id` from the base DN404 contract.
    ///
    /// Requirements:
    /// - Token `id` must exist.
    function ownerOf(uint256 id) public view virtual returns (address result) {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x6352211e) // `ownerOf(uint256)`.
            mstore(0x20, id)
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), base, 0x1c, 0x24, 0x00, 0x20))
            ) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            result := shr(96, mload(0x0c))
        }
    }

    /// @dev Sets `spender` as the approved account to manage token `id` in
    /// the base DN404 contract.
    ///
    /// Requirements:
    /// - Token `id` must exist.
    /// - The caller must be the owner of the token,
    ///   or an approved operator for the token owner.
    ///
    /// Emits an {Approval} event.
    function approve(address spender, uint256 id) public virtual {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            spender := shr(96, shl(96, spender))
            let m := mload(0x40)
            mstore(0x00, 0xd10b6e0c) // `approveNFT(address,uint256,address)`.
            mstore(0x20, spender)
            mstore(0x40, id)
            mstore(0x60, caller())
            if iszero(
                and(
                    gt(returndatasize(), 0x1f),
                    call(gas(), base, callvalue(), 0x1c, 0x64, 0x00, 0x20)
                )
            ) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
            mstore(0x40, m) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
            // Emit the {Approval} event.
            log4(codesize(), 0x00, _APPROVAL_EVENT_SIGNATURE, shr(96, mload(0x0c)), spender, id)
        }
    }

    /// @dev Returns the account approved to manage token `id` from
    /// the base DN404 contract.
    ///
    /// Requirements:
    /// - Token `id` must exist.
    function getApproved(uint256 id) public view virtual returns (address result) {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x081812fc) // `getApproved(uint256)`.
            mstore(0x20, id)
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), base, 0x1c, 0x24, 0x00, 0x20))
            ) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            result := shr(96, mload(0x0c))
        }
    }

    /// @dev Sets whether `operator` is approved to manage the tokens of the caller in
    /// the base DN404 contract.
    ///
    /// Emits an {ApprovalForAll} event.
    function setApprovalForAll(address operator, bool approved) public virtual {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            operator := shr(96, shl(96, operator))
            let m := mload(0x40)
            mstore(0x00, 0x813500fc) // `setApprovalForAll(address,bool,address)`.
            mstore(0x20, operator)
            mstore(0x40, iszero(iszero(approved)))
            mstore(0x60, caller())
            if iszero(
                and(eq(mload(0x00), 1), call(gas(), base, callvalue(), 0x1c, 0x64, 0x00, 0x20))
            ) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
            // Emit the {ApprovalForAll} event.
            log3(0x40, 0x20, _APPROVAL_FOR_ALL_EVENT_SIGNATURE, caller(), operator)
            mstore(0x40, m) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
        }
    }

    /// @dev Returns whether `operator` is approved to manage the tokens of `owner` from
    /// the base DN404 contract.
    function isApprovedForAll(address owner, address operator)
        public
        view
        virtual
        returns (bool result)
    {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(0x40, operator)
            mstore(0x2c, shl(96, owner))
            mstore(0x0c, 0xe985e9c5000000000000000000000000) // `isApprovedForAll(address,address)`.
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), base, 0x1c, 0x44, 0x00, 0x20))
            ) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
            mstore(0x40, m) // Restore the free memory pointer.
            result := iszero(iszero(mload(0x00)))
        }
    }

    /// @dev Transfers token `id` from `from` to `to`.
    ///
    /// Requirements:
    ///
    /// - Token `id` must exist.
    /// - `from` must be the owner of the token.
    /// - `to` cannot be the zero address.
    /// - The caller must be the owner of the token, or be approved to manage the token.
    ///
    /// Emits a {Transfer} event.
    function transferFrom(address from, address to, uint256 id) public virtual {
        address base = baseERC20();
        /// @solidity memory-safe-assembly
        assembly {
            from := shr(96, shl(96, from))
            to := shr(96, shl(96, to))
            let m := mload(0x40)
            mstore(m, 0xe5eb36c8) // `transferFromNFT(address,address,uint256,address)`.
            mstore(add(m, 0x20), from)
            mstore(add(m, 0x40), to)
            mstore(add(m, 0x60), id)
            mstore(add(m, 0x80), caller())
            if iszero(
                and(eq(mload(m), 1), call(gas(), base, callvalue(), add(m, 0x1c), 0x84, m, 0x20))
            ) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
            // Emit the {Transfer} event.
            log4(codesize(), 0x00, _TRANSFER_EVENT_SIGNATURE, from, to, id)
        }
    }

    /// @dev Equivalent to `safeTransferFrom(from, to, id, "")`.
    function safeTransferFrom(address from, address to, uint256 id) public payable virtual {
        transferFrom(from, to, id);

        if (_hasCode(to)) _checkOnERC721Received(from, to, id, "");
    }

    /// @dev Transfers token `id` from `from` to `to`.
    ///
    /// Requirements:
    ///
    /// - Token `id` must exist.
    /// - `from` must be the owner of the token.
    /// - `to` cannot be the zero address.
    /// - The caller must be the owner of the token, or be approved to manage the token.
    /// - If `to` refers to a smart contract, it must implement
    ///   {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
    ///
    /// Emits a {Transfer} event.
    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data)
        public
        virtual
    {
        transferFrom(from, to, id);

        if (_hasCode(to)) _checkOnERC721Received(from, to, id, data);
    }

    /// @dev Returns true if this contract implements the interface defined by `interfaceId`.
    /// See: https://eips.ethereum.org/EIPS/eip-165
    /// This function call must use less than 30000 gas.
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            let s := shr(224, interfaceId)
            // ERC165: 0x01ffc9a7, ERC721: 0x80ac58cd, ERC721Metadata: 0x5b5e139f.
            result := or(or(eq(s, 0x01ffc9a7), eq(s, 0x80ac58cd)), eq(s, 0x5b5e139f))
        }
    }

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                     MIRROR OPERATIONS                      */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the address of the base DN404 contract.
    function baseERC20() public view virtual returns (address base) {
        base = _getDN404NFTStorage().baseERC20;
        if (base == address(0)) revert NotLinked();
    }

    /// @dev Fallback modifier to execute calls from the base DN404 contract.
    modifier dn404NFTFallback() virtual {
        DN404NFTStorage storage $ = _getDN404NFTStorage();

        uint256 fnSelector = _calldataload(0x00) >> 224;

        // `logTransfer(uint256[])`.
        if (fnSelector == 0x263c69d6) {
            if (msg.sender != $.baseERC20) revert SenderNotBase();
            /// @solidity memory-safe-assembly
            assembly {
                // When returndatacopy copies 1 or more out-of-bounds bytes, it reverts.
                returndatacopy(0x00, returndatasize(), lt(calldatasize(), 0x20))
                let o := add(0x24, calldataload(0x04)) // Packed logs offset.
                returndatacopy(0x00, returndatasize(), lt(calldatasize(), o))
                let end := add(o, shl(5, calldataload(sub(o, 0x20))))
                returndatacopy(0x00, returndatasize(), lt(calldatasize(), end))

                for {} iszero(eq(o, end)) { o := add(0x20, o) } {
                    let d := calldataload(o) // Entry in the packed logs.
                    let a := shr(96, d) // The address.
                    let b := and(1, d) // Whether it is a burn.
                    log4(
                        codesize(),
                        0x00,
                        _TRANSFER_EVENT_SIGNATURE,
                        mul(a, b),
                        mul(a, iszero(b)),
                        shr(168, shl(160, d))
                    )
                }
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        }
        // `linkMirrorContract(address)`.
        if (fnSelector == 0x0f4599e5) {
            if ($.deployer != address(0)) {
                if (address(uint160(_calldataload(0x04))) != $.deployer) {
                    revert SenderNotDeployer();
                }
            }
            if ($.baseERC20 != address(0)) revert AlreadyLinked();
            $.baseERC20 = msg.sender;
            /// @solidity memory-safe-assembly
            assembly {
                mstore(0x00, 0x01)
                return(0x00, 0x20)
            }
        }
        _;
    }

    /// @dev Fallback function for calls from base DN404 contract.
    fallback() external payable virtual dn404NFTFallback {}

    receive() external payable virtual {}

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                      PRIVATE HELPERS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    /// @dev Returns the calldata value at `offset`.
    function _calldataload(uint256 offset) private pure returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := calldataload(offset)
        }
    }

    /// @dev Returns if `a` has bytecode of non-zero length.
    function _hasCode(address a) private view returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := extcodesize(a) // Can handle dirty upper bits.
        }
    }

    /// @dev Perform a call to invoke {IERC721Receiver-onERC721Received} on `to`.
    /// Reverts if the target does not support the function correctly.
    function _checkOnERC721Received(address from, address to, uint256 id, bytes memory data)
        private
    {
        /// @solidity memory-safe-assembly
        assembly {
            // Prepare the calldata.
            let m := mload(0x40)
            let onERC721ReceivedSelector := 0x150b7a02
            mstore(m, onERC721ReceivedSelector)
            mstore(add(m, 0x20), caller()) // The `operator`, which is always `msg.sender`.
            mstore(add(m, 0x40), shr(96, shl(96, from)))
            mstore(add(m, 0x60), id)
            mstore(add(m, 0x80), 0x80)
            let n := mload(data)
            mstore(add(m, 0xa0), n)
            if n { pop(staticcall(gas(), 4, add(data, 0x20), n, add(m, 0xc0), n)) }
            // Revert if the call reverts.
            if iszero(call(gas(), to, 0, add(m, 0x1c), add(n, 0xa4), m, 0x20)) {
                if returndatasize() {
                    // Bubble up the revert if the call reverts.
                    returndatacopy(m, 0x00, returndatasize())
                    revert(m, returndatasize())
                }
            }
            // Load the returndata and compare it.
            if iszero(eq(mload(m), shl(224, onERC721ReceivedSelector))) {
                mstore(0x00, 0xd1a57ed6) // `TransferToNonERC721ReceiverImplementer()`.
                revert(0x1c, 0x04)
            }
        }
    }
}
