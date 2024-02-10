// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface I404Fungible {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function tokenURI(uint256 id) external view returns (string memory);

    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 id) external view returns (address);

    function totalSupply() external view returns (uint256);

    function transferFromNFT(address from, address to, uint256 id, address msgSender) external;

    function approveNFT(address spender, uint256 id, address msgSender)
        external
        returns (address);

    function setApprovalForAll(address operator, bool approved, address msgSender) external;
}

contract DN404NonFungibleShadow {
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

    error TokenDoesNotExist();

    error TransferToNonERC721ReceiverImplementer();

    uint256 private constant _WAD = 1000000000000000000;

    I404Fungible public immutable FUNGIBLE_SISTER_CONTRACT;

    constructor() {
        // todo more flexible way to set fungible counterpart to allow for predeploys
        FUNGIBLE_SISTER_CONTRACT = I404Fungible(msg.sender);
    }

    function name() public view virtual returns (string memory) {
        return FUNGIBLE_SISTER_CONTRACT.name();
    }

    function symbol() public view virtual returns (string memory) {
        return FUNGIBLE_SISTER_CONTRACT.symbol();
    }

    function tokenURI(uint256 id) public view virtual returns (string memory) {
        return FUNGIBLE_SISTER_CONTRACT.tokenURI(id);
    }

    function totalSupply() public view returns (uint256) {
        return FUNGIBLE_SISTER_CONTRACT.totalSupply() / _WAD;
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        return FUNGIBLE_SISTER_CONTRACT.balanceOf(owner) / _WAD;
    }

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = FUNGIBLE_SISTER_CONTRACT.ownerOf(id);

        if (owner == address(0)) revert TokenDoesNotExist();
    }

    function approve(address spender, uint256 id) public virtual returns (bool) {
        address owner = FUNGIBLE_SISTER_CONTRACT.approveNFT(spender, id, msg.sender);

        emit Approval(owner, spender, id);
        return true;
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        emit ApprovalForAll(msg.sender, operator, approved);

        return FUNGIBLE_SISTER_CONTRACT.setApprovalForAll(operator, approved, msg.sender);
    }

    function transferFrom(address from, address to, uint256 id) public virtual {
        FUNGIBLE_SISTER_CONTRACT.transferFromNFT(from, to, id, msg.sender);
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

    function logTransfer(address from, address to, uint256 id) external {
        if (msg.sender != address(FUNGIBLE_SISTER_CONTRACT)) revert Unauthorized();

        emit Transfer(from, to, id);
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
