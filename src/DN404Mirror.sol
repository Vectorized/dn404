// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract DN404Mirror {
    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                           EVENTS                           */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-«-*/
    /*                        CUSTOM ERRORS                       */
    /*-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»-»*/

    error Unauthorized();

    error TransferToNonERC721ReceiverImplementer();

    error CannotLink();

    error AlreadyLinked();

    error NotLinked();

    uint256 private constant _WAD = 1000000000000000000;

    struct DN404NFTStorage {
        address rootERC20;
        address deployer;
    }

    constructor() {
        // For non-proxies, we will store the deployer so that only the deployer can
        // link the root contract.
        _getDN404NFTStorage().deployer = msg.sender;
    }

    function name() public view virtual returns (string memory result) {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(result, 0x06fdde03) // `name()`.
            if iszero(staticcall(gas(), root, add(result, 0x1c), 0x04, 0x00, 0x00)) {
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            returndatacopy(0x00, 0x00, 0x20)
            returndatacopy(result, mload(0x00), 0x20)
            returndatacopy(add(result, 0x20), add(mload(0x00), 0x20), mload(result))
            mstore(0x40, add(add(result, 0x20), mload(result)))
        }
    }

    function symbol() public view virtual returns (string memory result) {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(result, 0x95d89b41) // `symbol()`.
            if iszero(staticcall(gas(), root, add(result, 0x1c), 0x04, 0x00, 0x00)) {
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            returndatacopy(0x00, 0x00, 0x20)
            returndatacopy(result, mload(0x00), 0x20)
            returndatacopy(add(result, 0x20), add(mload(0x00), 0x20), mload(result))
            mstore(0x40, add(add(result, 0x20), mload(result)))
        }
    }

    function tokenURI(uint256 id) public view virtual returns (string memory result) {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            mstore(result, 0xc87b56dd) // `tokenURI()`.
            mstore(add(result, 0x20), id)
            if iszero(staticcall(gas(), root, add(result, 0x1c), 0x24, 0x00, 0x00)) {
                returndatacopy(result, 0x00, returndatasize())
                revert(result, returndatasize())
            }
            returndatacopy(0x00, 0x00, 0x20)
            returndatacopy(result, mload(0x00), 0x20)
            returndatacopy(add(result, 0x20), add(mload(0x00), 0x20), mload(result))
            mstore(0x40, add(add(result, 0x20), mload(result)))
        }
    }

    function totalSupply() public view returns (uint256 result) {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x18160ddd) // `totalSupply()`.
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), root, 0x1c, 0x04, 0x00, 0x20))
            ) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            result := div(mload(0x00), _WAD)
        }
    }

    function balanceOf(address owner) public view virtual returns (uint256 result) {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x70a08231) // `balanceOf(address)`.
            mstore(0x20, shr(96, shl(96, owner)))
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), root, 0x1c, 0x24, 0x00, 0x20))
            ) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            result := div(mload(0x00), _WAD)
        }
    }

    function ownerOf(uint256 id) public view virtual returns (address result) {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x6352211e) // `ownerOf(uint256)`.
            mstore(0x20, id)
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), root, 0x1c, 0x24, 0x00, 0x20))
            ) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            result := shr(96, shl(96, mload(0x00)))
        }
    }

    function approve(address spender, uint256 id) public virtual {
        address root = rootERC20();
        address owner;
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, 0xd10b6e0c) // `approveNFT(address,uint256,address)`.
            mstore(add(m, 0x20), shr(96, shl(96, spender)))
            mstore(add(m, 0x40), id)
            mstore(add(m, 0x60), caller())
            if iszero(
                and(
                    gt(returndatasize(), 0x1f),
                    call(gas(), root, callvalue(), add(m, 0x1c), 0x64, 0x00, 0x20)
                )
            ) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
            owner := shr(96, shl(96, mload(0x00)))
        }
        emit Approval(owner, spender, id);
    }

    function getApproved(uint256 id) public view virtual returns (address result) {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, 0x081812fc) // `getApproved(uint256)`.
            mstore(0x20, id)
            if iszero(
                and(gt(returndatasize(), 0x1f), staticcall(gas(), root, 0x1c, 0x24, 0x00, 0x20))
            ) {
                returndatacopy(mload(0x40), 0x00, returndatasize())
                revert(mload(0x40), returndatasize())
            }
            result := shr(96, shl(96, mload(0x00)))
        }
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, 0x813500fc) // `setApprovalForAll(address,bool,address)`.
            mstore(add(m, 0x20), shr(96, shl(96, operator)))
            mstore(add(m, 0x40), iszero(iszero(approved)))
            mstore(add(m, 0x60), caller())
            if iszero(
                and(
                    and(eq(mload(0x00), 1), gt(returndatasize(), 0x1f)),
                    call(gas(), root, callvalue(), add(m, 0x1c), 0x64, 0x00, 0x20)
                )
            ) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
        }
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator)
        public
        view
        virtual
        returns (bool result)
    {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, 0xe985e9c5) // `isApprovedForAll(address,address)`.
            mstore(add(m, 0x20), shr(96, shl(96, owner)))
            mstore(add(m, 0x40), shr(96, shl(96, operator)))
            if iszero(
                and(
                    gt(returndatasize(), 0x1f),
                    staticcall(gas(), root, add(m, 0x1c), 0x44, 0x00, 0x20)
                )
            ) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
            result := iszero(iszero(mload(0x00)))
        }
    }

    function transferFrom(address from, address to, uint256 id) public virtual {
        address root = rootERC20();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40)
            mstore(m, 0xe5eb36c8) // `transferFromNFT(address,address,uint256,address)`.
            mstore(add(m, 0x20), shr(96, shl(96, from)))
            mstore(add(m, 0x40), shr(96, shl(96, to)))
            mstore(add(m, 0x60), id)
            mstore(add(m, 0x80), caller())
            if iszero(
                and(
                    and(eq(mload(0x00), 1), gt(returndatasize(), 0x1f)),
                    call(gas(), root, callvalue(), add(m, 0x1c), 0x84, 0x00, 0x20)
                )
            ) {
                returndatacopy(m, 0x00, returndatasize())
                revert(m, returndatasize())
            }
        }
        emit Transfer(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id) public payable virtual {
        transferFrom(from, to, id);

        if (_hasCode(to)) _checkOnERC721Received(from, to, id, "");
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data)
        public
        virtual
    {
        transferFrom(from, to, id);

        if (_hasCode(to)) _checkOnERC721Received(from, to, id, data);
    }

    /// @dev Returns true if this contract implements the interface defined by
    /// `interfaceId`. See the corresponding
    /// [EIP section](https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified)
    /// to learn more about how these ids are created.
    ///
    /// This function call must use less than 30000 gas.
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        // The interface IDs are constants representing the first 4 bytes
        // of the XOR of all function selectors in the interface.
        // See: [ERC165](https://eips.ethereum.org/EIPS/eip-165)
        // (e.g. `bytes4(i.functionA.selector ^ i.functionB.selector ^ ...)`)
        return interfaceId == 0x01ffc9a7 // ERC165 interface ID for ERC165.
            || interfaceId == 0x80ac58cd // ERC165 interface ID for ERC721.
            || interfaceId == 0x5b5e139f; // ERC165 interface ID for ERC721Metadata.
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

    function _calldataload(uint256 offset) private pure returns (uint256 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := calldataload(offset)
        }
    }

    function _return(uint256 word) private pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, word)
            return(0x00, 0x20)
        }
    }

    function rootERC20() public view returns (address root) {
        root = _getDN404NFTStorage().rootERC20;
        if (root == address(0)) revert NotLinked();
    }

    modifier dn404NFTFallback() virtual {
        DN404NFTStorage storage $ = _getDN404NFTStorage();

        uint256 fnSelector = _calldataload(0x00) >> 224;

        // `linkMirrorContract(address)`.
        if (fnSelector == 0x0f4599e5) {
            if ($.deployer != address(0)) {
                if (address(uint160(_calldataload(0x04))) != $.deployer) {
                    revert Unauthorized();
                }
            }
            if ($.rootERC20 != address(0)) revert AlreadyLinked();
            $.rootERC20 = msg.sender;
            /// @solidity memory-safe-assembly
            assembly {
                // `implementsDN404()`.
                mstore(0x00, 0xb7a94eb8)
                if iszero(
                    and(
                        and(eq(mload(0x00), 1), gt(returndatasize(), 0x1f)),
                        staticcall(gas(), caller(), 0x1c, 0x04, 0x00, 0x20)
                    )
                ) {
                    mstore(0x00, 0x8f36fa09) // `CannotLink()`.
                    revert(0x1c, 0x04)
                }
            }
            _return(1);
        }
        // `logTransfer(address,address,uint256)`.
        if (fnSelector == 0xf51ac936) {
            if (msg.sender != $.rootERC20) revert Unauthorized();

            address from = address(uint160(_calldataload(0x04)));
            address to = address(uint160(_calldataload(0x24)));
            uint256 id = _calldataload(0x44);

            emit Transfer(from, to, id);
            _return(1);
        }
        _;
    }

    fallback() external payable virtual dn404NFTFallback {}

    receive() external payable virtual {}

    function _getDN404NFTStorage() internal pure returns (DN404NFTStorage storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            // keccak256(abi.encode(uint256(keccak256("dn404.nft")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := 0xe8cb618a1de8ad2a6a7b358523c369cb09f40cc15da64205134c7e55c6a86700
        }
    }
}
