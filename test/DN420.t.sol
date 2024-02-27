// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
// import {DN404, MockDN404} from "./utils/mocks/MockDN404.sol";
// import {DN404Mirror} from "../src/DN404Mirror.sol";
// import {LibClone} from "solady/utils/LibClone.sol";
// import {LibSort} from "solady/utils/LibSort.sol";

contract DN420Test is SoladyTest {
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

    function testDNBatchLogsEmit() public {
        _DNBatchLogs memory p = _batchLogsMalloc(3);
        _batchLogsAppend(p, 170);
        _batchLogsAppend(p, 187);
        _batchLogsAppend(p, 204);
        _batchLogsEmit(p, address(111), address(222));
    }

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
            // Copy the `amounts`.
            mstore(add(m, 0x20), add(0x40, returndatasize()))
            o := add(o, returndatasize())
            // Store the length of `amounts`.
            mstore(o, mload(ids))
            let end := add(o, returndatasize())
            for { o := add(o, 0x20) } iszero(eq(o, end)) { o := add(0x20, o) } { mstore(o, 1) }
            // Emit a {TransferBatch} event.
            log4(
                m,
                sub(o, m),
                _TRANSFER_BATCH_EVENT_SIGNATURE,
                caller(),
                shr(96, shl(96, from)),
                shr(96, shl(96, to))
            )
        }
    }
}
