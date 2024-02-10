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

    error AlreadyLinked();

    error NotLinked();

    error TransferToNonERC721ReceiverImplementer();

    uint256 private constant _WAD = 1000000000000000000;

    struct DN404NFTStorage {
        address sisterERC20;
        address deployer;
    }

    constructor() {
        // For non-proxies, we will store the deployer so that only the deployer can 
        // link the sister contract.
        _getDN404NFTStorage().deployer = msg.sender;
    }

    function name() public view virtual returns (string memory) {
        return I404Fungible(sisterERC20()).name();
    }

    function symbol() public view virtual returns (string memory) {
        return I404Fungible(sisterERC20()).symbol();
    }

    function tokenURI(uint256 id) public view virtual returns (string memory) {
        return I404Fungible(sisterERC20()).tokenURI(id);
    }

    function totalSupply() public view returns (uint256) {
        return I404Fungible(sisterERC20()).totalSupply() / _WAD;
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        return I404Fungible(sisterERC20()).balanceOf(owner) / _WAD;
    }

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = I404Fungible(sisterERC20()).ownerOf(id);

        if (owner == address(0)) revert TokenDoesNotExist();
    }

    function approve(address spender, uint256 id) public virtual {
        address owner = I404Fungible(sisterERC20()).approveNFT(spender, id, msg.sender);

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        emit ApprovalForAll(msg.sender, operator, approved);

        return I404Fungible(sisterERC20()).setApprovalForAll(operator, approved, msg.sender);
    }

    function transferFrom(address from, address to, uint256 id) public virtual {
        I404Fungible(sisterERC20()).transferFromNFT(from, to, id, msg.sender);
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

    function _returnTrue() private pure {
        uint256 zero; // To prevent a compiler bug.
        /// @solidity memory-safe-assembly
        assembly {
            mstore(zero, 0x01)
            return(zero, 0x20)
        }
    }

    function sisterERC20() public view returns (address sister) {
        sister = _getDN404NFTStorage().sisterERC20;
        if (sister == address(0)) revert NotLinked();
    }

    modifier dn404NFTFallback() virtual {
        DN404NFTStorage storage $ = _getDN404NFTStorage();

        uint256 fnSelector = _calldataload(0x00) >> 224;

        // `linkSisterContract(address)`.
        if (fnSelector == 0x847aab98) {
            if ($.deployer != address(0)) {
                if (address(uint160(_calldataload(0x04))) != $.deployer)
                    revert Unauthorized();
            }
            if ($.sisterERC20 != address(0)) revert AlreadyLinked();
            $.sisterERC20 = msg.sender;    
            _returnTrue();
        }

        // `logTransfer(address,address,uint256)`.
        if (fnSelector == 0xf51ac936) {
            if (msg.sender != $.sisterERC20) revert Unauthorized();

            address from = address(uint160(_calldataload(0x04)));
            address to = address(uint160(_calldataload(0x24)));
            uint256 id = _calldataload(0x44);

            emit Transfer(from, to, id);
            _returnTrue();
        }
        _;
    }

    fallback() external payable virtual dn404NFTFallback {}

    receive() external payable virtual {}

    function _getDN404NFTStorage() internal pure returns (DN404NFTStorage storage $) {
        assembly {
            // keccak256(abi.encode(uint256(keccak256("dn404.nft")) - 1)) & ~bytes32(uint256(0xff))
            $.slot := 0xe8cb618a1de8ad2a6a7b358523c369cb09f40cc15da64205134c7e55c6a86700
        }
    }
}
