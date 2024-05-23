// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./utils/SoladyTest.sol";
import {DN420, MockDN420} from "./utils/mocks/MockDN420.sol";
import {LibSort} from "solady/utils/LibSort.sol";
import {LibPRNG} from "solady/utils/LibPRNG.sol";

interface IERC1155 {
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function balanceOfBatch(address[] calldata owners, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

abstract contract ERC1155TokenReceiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}

contract ERC1155Recipient is ERC1155TokenReceiver {
    address public operator;
    address public from;
    uint256 public id;
    uint256 public amount;
    bytes public mintData;

    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _amount,
        bytes calldata _data
    ) public override returns (bytes4) {
        operator = _operator;
        from = _from;
        id = _id;
        amount = _amount;
        mintData = _data;

        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    address public batchOperator;
    address public batchFrom;
    uint256[] internal _batchIds;
    uint256[] internal _batchAmounts;
    bytes public batchData;

    event LogBytes(bytes b);

    function batchIds() external view returns (uint256[] memory) {
        return _batchIds;
    }

    function batchAmounts() external view returns (uint256[] memory) {
        return _batchAmounts;
    }

    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        bytes calldata _data
    ) external override returns (bytes4) {
        batchOperator = _operator;
        batchFrom = _from;
        _batchIds = _ids;
        _batchAmounts = _amounts;
        batchData = _data;
        emit LogBytes(_data);
        return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
    }
}

contract RevertingERC1155Recipient is ERC1155TokenReceiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        public
        pure
        override
        returns (bytes4)
    {
        revert(string(abi.encodePacked(ERC1155TokenReceiver.onERC1155Received.selector)));
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert(string(abi.encodePacked(ERC1155TokenReceiver.onERC1155BatchReceived.selector)));
    }
}

contract WrongReturnDataERC1155Recipient is ERC1155TokenReceiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        public
        pure
        override
        returns (bytes4)
    {
        return 0xCAFEBEEF;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return 0xCAFEBEEF;
    }
}

contract NonERC1155Recipient {}

contract DN420Test is SoladyTest {
    using LibPRNG for *;

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    event SkipNFTSet(address indexed target, bool status);

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] amounts
    );

    uint256 internal constant _WAD = 10 ** 18;

    MockDN420 dn;

    address internal constant _ALICE = address(111);
    address internal constant _BOB = address(222);

    function setUp() public {
        dn = new MockDN420();
    }

    function testFindOwnedIds() public {
        dn.initializeDN420(0, address(this));
        assertEq(dn.findOwnedIds(_ALICE, 0, 0), new uint256[](0));
        assertEq(dn.findOwnedIds(_ALICE, 0, 1), new uint256[](0));
        assertEq(dn.findOwnedIds(_ALICE, 0, 10), new uint256[](0));

        dn.mint(_ALICE, 1 * _WAD);
        dn.mint(_BOB, 1 * _WAD);
        dn.mint(_ALICE, 1 * _WAD);
        dn.mint(_BOB, 1 * _WAD);

        assertEq(dn.findOwnedIds(_ALICE, 0, 0), new uint256[](0));
        uint256[] memory expectedIds;
        expectedIds = new uint256[](2);
        expectedIds[0] = 1;
        expectedIds[1] = 3;
        assertEq(dn.findOwnedIds(_ALICE, 0, 10), expectedIds);

        expectedIds = new uint256[](1);
        expectedIds[0] = 3;
        assertEq(dn.findOwnedIds(_ALICE, 3, 4), expectedIds);
        assertEq(dn.findOwnedIds(_ALICE, 3, 3), new uint256[](0));
        assertEq(dn.findOwnedIds(_ALICE, 4, 4), new uint256[](0));

        assertEq(dn.exists(0), false);
        assertEq(dn.exists(1), true);
        assertEq(dn.exists(2), true);
        assertEq(dn.exists(3), true);
        assertEq(dn.exists(4), true);
        assertEq(dn.exists(5), false);
    }

    struct _TestTemps {
        address from;
        uint88 aliceAux;
        uint88 fromAux;
        uint256[] aliceIds;
        uint256[] bobIds;
        uint256[] ids;
        uint256[] oriIds;
        uint256 balanceBefore;
        uint256 id;
        address[] owners;
        uint256[] expectedBalances;
    }

    function testERC1155Methods(uint256) public {
        dn.initializeDN420(10 * _WAD, address(this));
        unchecked {
            for (uint256 i; i < 3; ++i) {
                dn.transfer(_ALICE, 1 * _WAD);
                dn.transfer(_BOB, 1 * _WAD);
            }
        }
        vm.prank(_ALICE);
        dn.setApprovalForAll(address(this), true);

        uint88 aliceAux = uint88(_random());
        dn.setAux(_ALICE, aliceAux);
        _testERC1155Methods();
        _testERC1155Methods2();
        _testERC1155Methods3();
        assertEq(dn.getAux(_ALICE), aliceAux);
    }

    function _testERC1155Methods() internal {
        if (_random() % 2 == 0) {
            _TestTemps memory t;
            t.owners = new address[](11);
            t.ids = new uint256[](11);
            t.expectedBalances = new uint256[](11);
            unchecked {
                for (uint256 i; i <= 10; ++i) {
                    t.ids[i] = i;
                }
                if (_random() % 2 == 0) {
                    LibPRNG.PRNG memory prng;
                    prng.state = _random();
                    prng.shuffle(t.ids);
                }
                for (uint256 i; i <= 10; ++i) {
                    uint256 r = _random() % 4;
                    if (r == 0) {
                        t.owners[i] = _ALICE;
                    } else if (r == 1) {
                        t.owners[i] = _BOB;
                    } else {
                        t.owners[i] = address(this);
                    }
                    t.expectedBalances[i] = dn.owns(t.owners[i], t.ids[i]) ? 1 : 0;
                    assertEq(
                        IERC1155(address(dn)).balanceOf(t.owners[i], t.ids[i]),
                        t.expectedBalances[i]
                    );
                }
            }
            assertEq(IERC1155(address(dn)).balanceOfBatch(t.owners, t.ids), t.expectedBalances);
        }
    }

    function _testERC1155Methods2() internal {
        if (_random() % 2 == 0) {
            _TestTemps memory t;
            t.aliceIds = dn.findOwnedIds(_ALICE);
            t.bobIds = dn.findOwnedIds(_BOB);
            t.ids = t.aliceIds;
            t.id = t.ids[_random() % t.ids.length];
            assertEq(IERC1155(address(dn)).balanceOf(_ALICE, t.id), 1);
            assertEq(IERC1155(address(dn)).balanceOf(_BOB, t.id), 0);
            assertEq(dn.balanceOf(_ALICE), t.aliceIds.length * _WAD);
            assertEq(dn.balanceOf(_BOB), t.bobIds.length * _WAD);
            if (_random() % 16 == 0) {
                vm.expectRevert(DN420.InvalidNFTAmount.selector);
                IERC1155(address(dn)).safeTransferFrom(_ALICE, _BOB, t.id, _invalidAmount(), "");
            }
            vm.expectEmit(true, true, true, true);
            if (_random() % 2 == 0) {
                emit Transfer(_ALICE, _BOB, _WAD);
            } else {
                emit TransferSingle(address(this), _ALICE, _BOB, t.id, 1);
            }
            IERC1155(address(dn)).safeTransferFrom(_ALICE, _BOB, t.id, 1, "");
            assertEq(dn.balanceOf(_ALICE), (t.aliceIds.length - 1) * _WAD);
            assertEq(dn.balanceOf(_BOB), (t.bobIds.length + 1) * _WAD);
            assertEq(IERC1155(address(dn)).balanceOf(_ALICE, t.id), 0);
            assertEq(IERC1155(address(dn)).balanceOf(_BOB, t.id), 1);
            assertEq(
                IERC1155(address(dn)).balanceOfBatch(_filled(1, _ALICE), _filled(1, t.id)),
                _filled(1, 0)
            );
            assertEq(
                IERC1155(address(dn)).balanceOfBatch(_filled(1, _BOB), _filled(1, t.id)),
                _filled(1, 1)
            );
            return;
        }
    }

    function _testERC1155Methods3() internal {
        if (_random() % 2 == 0) {
            _TestTemps memory t;
            t.aliceIds = dn.findOwnedIds(_ALICE);
            t.bobIds = dn.findOwnedIds(_BOB);
            t.ids = _randomSampleWithoutReplacements(t.aliceIds);
            assertEq(dn.balanceOf(_ALICE), t.aliceIds.length * _WAD);
            assertEq(dn.balanceOf(_BOB), t.bobIds.length * _WAD);
            unchecked {
                for (uint256 i; i < t.ids.length; ++i) {
                    assertEq(IERC1155(address(dn)).balanceOf(_ALICE, t.ids[i]), 1);
                    assertEq(IERC1155(address(dn)).balanceOf(_BOB, t.ids[i]), 0);
                }
            }
            if (_random() % 16 == 0 && t.ids.length != 0) {
                vm.expectRevert(DN420.InvalidNFTAmount.selector);
                IERC1155(address(dn)).safeBatchTransferFrom(
                    _ALICE, _BOB, t.ids, _filled(t.ids.length, _invalidAmount()), ""
                );
                vm.expectRevert(DN420.ArrayLengthsMismatch.selector);
                IERC1155(address(dn)).safeBatchTransferFrom(
                    _ALICE, _BOB, t.ids, _filled(_invalidLength(t.ids.length), 1), ""
                );
            }
            if (_random() % 2 == 0) {
                vm.expectEmit(true, true, true, true);
                emit Transfer(_ALICE, _BOB, t.ids.length * _WAD);
            } else if (t.ids.length != 0) {
                vm.expectEmit(true, true, true, true);
                emit TransferBatch(address(this), _ALICE, _BOB, t.ids, _filled(t.ids.length, 1));
            }
            IERC1155(address(dn)).safeBatchTransferFrom(
                _ALICE, _BOB, t.ids, _filled(t.ids.length, 1), ""
            );
            unchecked {
                for (uint256 i; i < t.ids.length; ++i) {
                    assertEq(IERC1155(address(dn)).balanceOf(_ALICE, t.ids[i]), 0);
                    assertEq(IERC1155(address(dn)).balanceOf(_BOB, t.ids[i]), 1);
                }
            }
            assertEq(dn.balanceOf(_ALICE), (t.aliceIds.length - t.ids.length) * _WAD);
            assertEq(dn.balanceOf(_BOB), (t.bobIds.length + t.ids.length) * _WAD);
            assertEq(
                IERC1155(address(dn)).balanceOfBatch(_filled(t.ids.length, _ALICE), t.ids),
                _filled(t.ids.length, 0)
            );
            assertEq(
                IERC1155(address(dn)).balanceOfBatch(_filled(t.ids.length, _BOB), t.ids),
                _filled(t.ids.length, 1)
            );
            if (_random() % 32 == 0) {
                vm.expectRevert(DN420.ArrayLengthsMismatch.selector);
                IERC1155(address(dn)).balanceOfBatch(
                    _filled(t.ids.length, _BOB), _filled(_invalidLength(t.ids.length), 0)
                );
            }
        }
    }

    function testERC1155MethodsSelfTransfers(uint256) public {
        dn.initializeDN420(10 * _WAD, address(this));
        for (uint256 i; i < 3; ++i) {
            dn.transfer(_ALICE, 1 * _WAD);
        }

        vm.prank(_ALICE);
        dn.setApprovalForAll(address(this), true);

        uint88 aliceAux = uint88(_random());
        dn.setAux(_ALICE, aliceAux);
        _testERC1155MethodsSelfTransfers();
        _testERC1155MethodsSelfTransfers2();
        assertEq(dn.getAux(_ALICE), aliceAux);
    }

    function _testERC1155MethodsSelfTransfers() internal {
        _TestTemps memory t;
        t.aliceIds = dn.findOwnedIds(_ALICE);
        if (_random() % 2 == 0) {
            t.id = t.aliceIds[_random() % t.aliceIds.length];
            if (_random() % 16 == 0) {
                vm.expectRevert(DN420.InvalidNFTAmount.selector);
                IERC1155(address(dn)).safeTransferFrom(_ALICE, _ALICE, t.id, _invalidAmount(), "");
            }
            vm.expectEmit(true, true, true, true);
            if (_random() % 2 == 0) {
                emit Transfer(_ALICE, _ALICE, _WAD);
            } else {
                emit TransferSingle(address(this), _ALICE, _ALICE, t.id, 1);
            }
            IERC1155(address(dn)).safeTransferFrom(_ALICE, _ALICE, t.id, 1, "");
            assertEq(IERC1155(address(dn)).balanceOf(_ALICE, t.id), 1);
            assertEq(
                IERC1155(address(dn)).balanceOfBatch(_filled(t.aliceIds.length, _ALICE), t.aliceIds),
                _filled(t.aliceIds.length, 1)
            );
            assertEq(dn.balanceOf(_ALICE), t.aliceIds.length * _WAD);
        }
    }

    function _testERC1155MethodsSelfTransfers2() internal {
        _TestTemps memory t;
        t.aliceIds = dn.findOwnedIds(_ALICE);
        if (_random() % 2 == 0) {
            t.ids = _randomSampleWithoutReplacements(t.aliceIds);
            if (_random() % 16 == 0 && t.ids.length != 0) {
                vm.expectRevert(DN420.InvalidNFTAmount.selector);
                IERC1155(address(dn)).safeBatchTransferFrom(
                    _ALICE, _ALICE, t.ids, _filled(t.ids.length, _invalidAmount()), ""
                );
            }
            if (_random() % 2 == 0) {
                vm.expectEmit(true, true, true, true);
                emit Transfer(_ALICE, _ALICE, t.ids.length * _WAD);
            } else if (t.ids.length != 0) {
                vm.expectEmit(true, true, true, true);
                emit TransferBatch(address(this), _ALICE, _ALICE, t.ids, _filled(t.ids.length, 1));
            }
            IERC1155(address(dn)).safeBatchTransferFrom(
                _ALICE, _ALICE, t.ids, _filled(t.ids.length, 1), ""
            );
            for (uint256 i; i < t.ids.length; ++i) {
                assertEq(IERC1155(address(dn)).balanceOf(_ALICE, t.ids[i]), 1);
            }
            assertEq(
                IERC1155(address(dn)).balanceOfBatch(_filled(t.aliceIds.length, _ALICE), t.aliceIds),
                _filled(t.aliceIds.length, 1)
            );
            assertEq(dn.balanceOf(_ALICE), t.aliceIds.length * _WAD);
        }
    }

    function _invalidLength(uint256 n) internal returns (uint256 result) {
        do {
            result = _random() % 512;
        } while (result == n);
    }

    function _invalidAmount() internal returns (uint256 result) {
        do {
            result = _random();
        } while (result == 1);
    }

    function _randomSampleWithoutReplacements(uint256[] memory a)
        internal
        returns (uint256[] memory result)
    {
        result = LibSort.copy(a);
        if (result.length != 0) {
            LibPRNG.PRNG memory prng;
            prng.state = _random();
            prng.shuffle(result);
            uint256 n = _random() % result.length;
            /// @solidity memory-safe-assembly
            assembly {
                mstore(result, n)
            }
        }
    }

    function _randomSampleWithReplacements(uint256[] memory a)
        internal
        returns (uint256[] memory result)
    {
        uint256 n = _bound(_random(), 0, a.length);
        result = new uint256[](n);
        unchecked {
            for (uint256 i; i < n; ++i) {
                result[i] = a[_random() % a.length];
            }
        }
    }

    function _filled(uint256 n, uint256 a) internal pure returns (uint256[] memory result) {
        unchecked {
            result = new uint256[](n);
            for (uint256 i; i < n; ++i) {
                result[i] = a;
            }
        }
    }

    function _filled(uint256 n, address a) internal pure returns (address[] memory result) {
        unchecked {
            result = new address[](n);
            for (uint256 i; i < n; ++i) {
                result[i] = a;
            }
        }
    }

    struct _TestMixedTemps {
        address from;
        address to;
        uint256 amount;
        uint256 balance;
        uint256 nftBalance;
        uint256[] fromIds;
        uint256[] allIds;
        uint256[] ids;
        uint256[] idsCopy;
        uint256 numExists;
        uint256 maxId;
        uint256 end;
    }

    function _sampleAddress(address[] memory addresses) internal returns (address) {
        unchecked {
            return addresses[_random() % addresses.length];
        }
    }

    function _maxOwnedTokenId(address[] memory addresses) internal view returns (uint256 result) {
        unchecked {
            uint256 upTo = dn.totalSupply() * (addresses.length + 2) / _WAD + 2048;
            for (uint256 i; i < addresses.length; ++i) {
                uint256 id = dn.maxOwnedTokenId(addresses[i], upTo);
                if (id > result) result = id;
            }
        }
    }

    function _findAndCheckOwnedIds(address a) internal returns (uint256[] memory ids) {
        unchecked {
            ids = dn.findOwnedIds(a);
            assertEq(ids.length, dn.ownedCount(a));
            assertLe(ids.length, dn.balanceOf(a) / _WAD);
        }
    }

    function _findAndCheckAllOwnedIds(address[] memory addresses)
        internal
        returns (uint256[] memory allIds)
    {
        unchecked {
            for (uint256 i; i < addresses.length; ++i) {
                uint256[] memory ids = _findAndCheckOwnedIds(addresses[i]);
                // Might not be sorted.
                LibSort.sort(ids);
                assertEq(LibSort.intersection(allIds, ids).length, 0);
                allIds = LibSort.union(allIds, ids);
            }
            for (uint256 i; i < allIds.length; ++i) {
                assertTrue(dn.exists(allIds[i]));
            }
        }
        assertLe(allIds.length, dn.totalSupply() / _WAD);
    }

    function _checkBalanceSum(address[] memory addresses) internal {
        unchecked {
            uint256 balanceSum;
            for (uint256 i; i < addresses.length; ++i) {
                balanceSum += dn.balanceOf(addresses[i]);
            }
            assertEq(balanceSum, dn.totalSupply());
        }
    }

    function _countNumExists(uint256 maxId) internal view returns (uint256 numExists) {
        unchecked {
            for (uint256 i; i <= maxId; ++i) {
                if (dn.exists(i)) ++numExists;
            }
        }
    }

    function _maybeCheckInvariants(address[] memory addresses) internal {
        if (_random() % 32 == 0) {
            _checkBalanceSum(addresses);
        }
        if (_random() % 16 == 0) {
            _TestMixedTemps memory t;
            unchecked {
                t.allIds = _findAndCheckAllOwnedIds(addresses);
                if (t.allIds.length != 0) {
                    t.maxId = t.allIds[t.allIds.length - 1];
                    assertEq(t.maxId, _maxOwnedTokenId(addresses));
                    assertEq(t.allIds.length, _countNumExists(t.maxId));
                    t.end = t.maxId + (_random() % 32) * (_random() % 32);
                    for (uint256 i = t.maxId + 1; i <= t.end; ++i) {
                        assertFalse(dn.exists(i));
                    }
                }
            }
        }
    }

    function _mintOrMintNext(address to, uint256 amount) internal {
        if (_random() % 2 == 0) {
            dn.mint(to, amount);
        } else {
            dn.mintNext(to, amount);
        }
    }

    function _randomizeConfigurations(address[] memory addresses) internal {
        if (_random() % 4 == 0) {
            dn.setUseDirectTransfersIfPossible(_random() % 2 == 0);
        }
        if (_random() % 8 == 0) {
            unchecked {
                uint256 n = dn.totalSupply() / _WAD * 4 + 1;
                vm.prank(_sampleAddress(addresses));
                dn.setOwnedCheckpoint(_random() % n);
            }
        }
        if (_random() % 4 == 0) {
            vm.prank(_sampleAddress(addresses));
            dn.setSkipNFT(_random() & 1 == 0);
        }
    }

    function _checkAfterNFTTransfer(_TestMixedTemps memory t) internal {
        assertEq(dn.ownedCount(t.from), t.nftBalance);
        assertEq(dn.balanceOf(t.from), t.balance);
        t.idsCopy = dn.findOwnedIds(t.from);
        LibSort.sort(t.idsCopy);
        LibSort.sort(t.fromIds);
        assertEq(t.idsCopy, t.fromIds);
    }

    function _doDirectNFTTransfer(address[] memory addresses) internal {
        _TestMixedTemps memory t;
        if (_random() % 4 == 0) {
            t.from = _sampleAddress(addresses);
            t.to = _sampleAddress(addresses);
            t.fromIds = dn.findOwnedIds(t.from);
            if (t.fromIds.length == 0) return;
            uint256 id = t.fromIds[_random() % t.fromIds.length];
            if (t.to == t.from) {
                t.balance = dn.balanceOf(t.from);
                t.nftBalance = dn.ownedCount(t.from);
                vm.prank(t.from);
                dn.safeTransferFromNFT(t.from, t.to, id);
                _checkAfterNFTTransfer(t);
                return;
            }
            vm.prank(t.from);
            dn.safeTransferFromNFT(t.from, t.to, id);
        }
    }

    function _doDirectNFTBatchTransfer(address[] memory addresses) internal {
        _TestMixedTemps memory t;
        if (_random() % 4 == 0) {
            t.from = _sampleAddress(addresses);
            t.to = _sampleAddress(addresses);
            t.fromIds = dn.findOwnedIds(t.from);
            if (t.to == t.from) {
                if (_random() % 2 == 0) {
                    t.ids = _randomSampleWithReplacements(t.fromIds);
                } else {
                    t.ids = _randomSampleWithoutReplacements(t.fromIds);
                }
                t.balance = dn.balanceOf(t.from);
                t.nftBalance = dn.ownedCount(t.from);
                vm.prank(t.from);
                dn.safeBatchTransferFromNFTs(t.from, t.to, t.ids);
                _checkAfterNFTTransfer(t);
                return;
            }
            if (_random() % 2 == 0) {
                t.ids = _randomSampleWithReplacements(t.fromIds);
                t.idsCopy = LibSort.copy(t.ids);
                LibSort.sort(t.idsCopy);
                LibSort.uniquifySorted(t.idsCopy);
                if (t.idsCopy.length < t.ids.length) {
                    vm.prank(t.from);
                    vm.expectRevert(DN420.TransferFromIncorrectOwner.selector);
                    dn.safeBatchTransferFromNFTs(t.from, t.to, t.ids);
                } else {
                    vm.prank(t.from);
                    dn.safeBatchTransferFromNFTs(t.from, t.to, t.ids);
                }
                return;
            }
            t.ids = _randomSampleWithoutReplacements(t.fromIds);
            vm.prank(t.from);
            dn.safeBatchTransferFromNFTs(t.from, t.to, t.ids);
        }
    }

    function _doTransfer(address[] memory addresses) internal {
        _TestMixedTemps memory t;
        if (_random() % 16 > 0) {
            t.from = _sampleAddress(addresses);
            t.to = _sampleAddress(addresses);

            t.amount = _bound(_random(), 0, dn.balanceOf(t.from));
            vm.prank(t.from);
            dn.transfer(t.to, t.amount);
        }
    }

    function _doBurnAndMint(address[] memory addresses) internal {
        _TestMixedTemps memory t;
        if (_random() % 4 == 0) {
            t.from = _sampleAddress(addresses);
            t.to = _sampleAddress(addresses);

            t.amount = _bound(_random(), 0, dn.balanceOf(t.from));
            if (_random() % 2 == 0) {
                _mintOrMintNext(t.to, t.amount);
                _maybeCheckInvariants(addresses);
                _randomizeConfigurations(addresses);
                dn.burn(t.from, t.amount);
                _maybeCheckInvariants(addresses);
            } else {
                dn.burn(t.from, t.amount);
                _maybeCheckInvariants(addresses);
                _randomizeConfigurations(addresses);
                _mintOrMintNext(t.to, t.amount);
                _maybeCheckInvariants(addresses);
            }
        }
    }

    function testMixed(uint256) public {
        uint256 n = _random() % 8 == 0 ? _bound(_random(), 0, 512) : _bound(_random(), 0, 16);
        dn.initializeDN420(n * _WAD, address(333));

        address[] memory addresses = new address[](3);
        addresses[0] = address(111);
        addresses[1] = address(222);
        addresses[2] = address(333);

        do {
            _randomizeConfigurations(addresses);

            if (_random() % 2 == 0) {
                _doBurnAndMint(addresses);
            } else {
                _doTransfer(addresses);
            }

            _maybeCheckInvariants(addresses);
            _randomizeConfigurations(addresses);

            if (_random() % 2 == 0) {
                _doDirectNFTTransfer(addresses);
            } else {
                _doDirectNFTBatchTransfer(addresses);
            }

            _maybeCheckInvariants(addresses);
        } while (_random() % 8 > 0);

        if (_random() % 4 == 0) {
            for (uint256 i; i != addresses.length; ++i) {
                address a = addresses[i];
                vm.prank(a);
                dn.setSkipNFT(false);
                uint256 amount = dn.balanceOf(a);
                vm.prank(a);
                dn.transfer(a, amount);
                assertEq(dn.ownedCount(a), dn.balanceOf(a) / _WAD);
            }
        }
        _maybeCheckInvariants(addresses);

        if (_random() % 32 == 0) {
            for (uint256 i; i != addresses.length; ++i) {
                address a = addresses[i];
                vm.prank(a);
                dn.setSkipNFT(true);
                uint256 amount = dn.balanceOf(a);
                vm.prank(a);
                dn.transfer(a, amount);
                assertEq(dn.ownedCount(a), 0);
            }
        }
        _maybeCheckInvariants(addresses);
    }

    function testMintToZeroReverts(uint256) public {
        dn.initializeDN420(0, address(this));
        vm.expectRevert(DN420.TransferToZeroAddress.selector);
        dn.mint(address(0), _bound(_random(), _WAD, 10 * _WAD), _randomBytes());
    }

    function testMintNext() public {
        dn.initializeDN420(10 * _WAD, address(this));
        dn.mintNext(_ALICE, 10 * _WAD);
        for (uint256 i = 11; i <= 20; ++i) {
            assertEq(dn.owns(_ALICE, i), true);
        }

        vm.prank(_ALICE);
        dn.transfer(_BOB, 10 * _WAD);

        dn.mintNext(_ALICE, 10 * _WAD);
        for (uint256 i = 21; i <= 30; ++i) {
            assertEq(dn.owns(_ALICE, i), true);
        }
    }

    function testMintToRevertingERC155RecipientReverts(uint256) public {
        dn.initializeDN420(0, address(this));
        address to = address(new RevertingERC1155Recipient());
        vm.prank(to);
        dn.setSkipNFT(false);
        if (_random() % 32 == 0) {
            dn.mint(to, _bound(_random(), 0, _WAD - 1), _randomBytes());
        } else if (_random() % 2 == 0) {
            vm.expectRevert(abi.encodePacked(ERC1155TokenReceiver.onERC1155BatchReceived.selector));
            if (_random() % 2 == 0) {
                dn.mint(to, _bound(_random(), _WAD, 10 * _WAD), _randomBytes());
            } else {
                dn.mintNext(to, _bound(_random(), _WAD, 10 * _WAD), _randomBytes());
            }
        } else {
            dn.mint(_ALICE, _WAD);
            vm.prank(_ALICE);
            dn.setApprovalForAll(address(this), true);
            assertEq(dn.owns(_ALICE, 1), true);
            vm.expectRevert(abi.encodePacked(ERC1155TokenReceiver.onERC1155Received.selector));
            vm.prank(_ALICE);
            dn.safeTransferFromNFT(_ALICE, to, 1, _randomBytes());
        }
    }

    function testMintToNonERC155RecipientReverts(uint256) public {
        dn.initializeDN420(0, address(this));
        address to = address(new NonERC1155Recipient());
        vm.prank(to);
        dn.setSkipNFT(false);
        if (_random() % 32 == 0) {
            dn.mint(to, _bound(_random(), 0, _WAD - 1), _randomBytes());
        } else if (_random() % 2 == 0) {
            vm.expectRevert(DN420.TransferToNonERC1155ReceiverImplementer.selector);
            if (_random() % 2 == 0) {
                dn.mint(to, _bound(_random(), _WAD, 10 * _WAD), _randomBytes());
            } else {
                dn.mintNext(to, _bound(_random(), _WAD, 10 * _WAD), _randomBytes());
            }
        } else if (_random() % 2 == 0) {
            dn.mint(_ALICE, _WAD);
            vm.prank(_ALICE);
            dn.setApprovalForAll(address(this), true);
            assertEq(dn.owns(_ALICE, 1), true);
            vm.expectRevert(DN420.TransferToNonERC1155ReceiverImplementer.selector);
            vm.prank(_ALICE);
            dn.safeTransferFromNFT(_ALICE, to, 1, _randomBytes());
        }
    }

    function testSafeTransferFromToERC1155Recipient(uint256) public {
        dn.initializeDN420(0, address(this));
        ERC1155Recipient to = new ERC1155Recipient();
        bytes memory transferData = _randomBytes();

        dn.mint(_ALICE, 3 * _WAD);
        uint256[] memory ids = dn.findOwnedIds(_ALICE);
        uint256 id = ids[_random() % ids.length];

        if (_random() % 2 == 0) {
            vm.prank(_ALICE);
            if (_random() % 2 == 0) {
                dn.safeTransferFromNFT(_ALICE, address(to), id, transferData);
            } else {
                IERC1155(address(dn)).safeTransferFrom(_ALICE, address(to), id, 1, transferData);
            }
            assertEq(to.operator(), _ALICE);
        } else {
            vm.prank(_ALICE);
            dn.setApprovalForAll(address(this), true);
            if (_random() % 2 == 0) {
                dn.safeTransferFromNFT(_ALICE, address(to), id, transferData);
            } else {
                IERC1155(address(dn)).safeTransferFrom(_ALICE, address(to), id, 1, transferData);
            }
            assertEq(to.operator(), address(this));
        }
        assertEq(to.from(), _ALICE);
        assertEq(to.id(), id);
        assertEq(to.amount(), 1);
        assertEq(to.mintData(), transferData);
    }

    function testSafeBatchTransferFromToERC1155Recipient(uint256) public {
        dn.initializeDN420(0, address(this));
        ERC1155Recipient to = new ERC1155Recipient();
        bytes memory transferData = _randomBytes();

        dn.mint(_ALICE, 3 * _WAD);

        uint256[] memory ids = dn.findOwnedIds(_ALICE);

        if (_random() % 2 == 0) {
            vm.prank(_ALICE);
            if (_random() % 2 == 0) {
                dn.safeBatchTransferFromNFTs(_ALICE, address(to), ids, transferData);
            } else {
                IERC1155(address(dn)).safeBatchTransferFrom(
                    _ALICE, address(to), ids, _filled(ids.length, 1), transferData
                );
            }
            assertEq(to.batchOperator(), _ALICE);
        } else {
            vm.prank(_ALICE);
            dn.setApprovalForAll(address(this), true);
            if (_random() % 2 == 0) {
                dn.safeBatchTransferFromNFTs(_ALICE, address(to), ids, transferData);
            } else {
                IERC1155(address(dn)).safeBatchTransferFrom(
                    _ALICE, address(to), ids, _filled(ids.length, 1), transferData
                );
            }
            assertEq(to.batchOperator(), address(this));
        }
        assertEq(to.batchFrom(), _ALICE);
        assertEq(to.batchIds(), ids);
        assertEq(to.batchAmounts(), _filled(ids.length, 1));
        assertEq(to.batchData(), transferData);
    }

    function testTransferFromToERC1155Recipient(uint256) public {
        dn.initializeDN420(0, address(this));
        ERC1155Recipient from = new ERC1155Recipient();
        ERC1155Recipient to = new ERC1155Recipient();

        vm.prank(address(from));
        dn.setSkipNFT(false);
        vm.prank(address(to));
        dn.setSkipNFT(false);

        uint256[] memory ids = new uint256[](3);
        for (uint256 i; i < 3; ++i) {
            ids[i] = 1 + i;
        }
        if (_random() % 2 == 0) {
            dn.mint(address(from), ids.length * _WAD);
        } else {
            dn.mintNext(address(from), ids.length * _WAD);
        }
        assertEq(from.batchOperator(), address(this));
        assertEq(from.batchFrom(), address(0));
        assertEq(from.batchIds(), ids);
        assertEq(from.batchAmounts(), _filled(ids.length, 1));

        if (_random() % 2 == 0) {
            vm.prank(address(from));
            dn.approve(address(this), type(uint256).max);
            dn.transferFrom(address(from), address(to), ids.length * _WAD);

            assertEq(to.batchOperator(), address(this));
            assertEq(to.batchFrom(), address(0));
            assertEq(to.batchIds(), ids);
            assertEq(to.batchAmounts(), _filled(ids.length, 1));
        } else {
            dn.setUseDirectTransfersIfPossible(true);
            vm.prank(address(from));
            dn.approve(address(this), type(uint256).max);
            dn.transferFrom(address(from), address(to), ids.length * _WAD);

            uint256[] memory reversedIds = LibSort.copy(ids);
            LibSort.reverse(reversedIds);
            assertEq(to.batchOperator(), address(this));
            assertEq(to.batchFrom(), address(from));
            assertEq(to.batchIds(), reversedIds);
            assertEq(to.batchAmounts(), _filled(ids.length, 1));
        }
    }

    function testTransferMixedReverts(uint256) public {
        dn.initializeDN420(0, address(this));

        _TestTemps memory t;
        t.from = _randomNonZeroAddress();
        dn.mint(t.from, _bound(_random(), 1, 10) * _WAD, "");

        dn.setAux(t.from, t.fromAux = uint88(_random()));
        _testTransferMixedReverts(t);
        _testTransferMixedReverts2(t);
        _testTransferMixedReverts3(t);
        assertEq(dn.getAux(t.from), t.fromAux);
    }

    function _testTransferMixedReverts(_TestTemps memory t) internal {
        uint256 amount = dn.balanceOf(t.from);
        if (_random() % 4 == 0) {
            vm.expectRevert(DN420.TransferToZeroAddress.selector);
            dn.mint(address(0), _random(), "");
            vm.expectRevert(DN420.TransferToZeroAddress.selector);
            dn.mintNext(address(0), _random(), "");
            vm.expectRevert(DN420.TransferToZeroAddress.selector);
            dn.transfer(address(0), amount);
            vm.prank(t.from);
            dn.approve(address(this), type(uint256).max);
            vm.expectRevert(DN420.TransferToZeroAddress.selector);
            dn.transferFrom(t.from, address(0), amount);
            address to = _randomNonZeroAddress();
            dn.transferFrom(t.from, to, amount);
            vm.prank(to);
            dn.transfer(t.from, amount);
        }

        if (_random() % 4 == 0) {
            address by;
            if (_random() % 8 > 0) by = _random() % 2 == 0 ? t.from : _randomNonZeroAddress();
            address to = _randomNonZeroAddress();
            if (by == address(0) || by == t.from) {
                _safeTransferFromNFT(by, t.from, to, 1);
            } else if (_random() % 2 == 0) {
                vm.prank(t.from);
                dn.setApprovalForAll(by, true);
                _safeTransferFromNFT(by, t.from, to, 1);
                vm.prank(t.from);
                dn.setApprovalForAll(by, false);
            } else {
                vm.expectRevert(DN420.NotOwnerNorApproved.selector);
                _safeTransferFromNFT(by, t.from, to, 1);
            }
            if (dn.owns(to, 1)) {
                vm.prank(to);
                _safeTransferFromNFT(to, to, t.from, 1);
            }
        }
    }

    function _testTransferMixedReverts2(_TestTemps memory t) internal {
        if (_random() % 4 == 0) {
            uint256 id = _bound(_random(), 0, 256);
            while (dn.owns(t.from, id)) id = _bound(_random(), 0, 256);
            vm.expectRevert(DN420.TransferFromIncorrectOwner.selector);
            _safeTransferFromNFT(t.from, t.from, _randomNonZeroAddress(), id);
        }

        while (_random() % 4 == 0) {
            address to = _randomNonZeroAddress();
            while (t.from == to) to = _randomNonZeroAddress();
            t.ids = dn.findOwnedIds(t.from);
            if (t.ids.length < 2) break;
            t.ids[0] = t.ids[_bound(_random(), 1, t.ids.length - 1)];
            vm.expectRevert(DN420.TransferFromIncorrectOwner.selector);
            dn.safeBatchTransferFromNFTs(t.from, t.from, to, t.ids);
        }
    }

    function _testTransferMixedReverts3(_TestTemps memory t) internal {
        if (_random() % 2 == 0) {
            address to = _random() % 2 == 0 ? t.from : _randomNonZeroAddress();
            t.ids = dn.findOwnedIds(t.from);
            t.ids[0] = _bound(_random(), 0, 256);
            while (dn.owns(t.from, t.ids[0])) t.ids[0] = _bound(_random(), 0, 256);
            vm.expectRevert(DN420.TransferFromIncorrectOwner.selector);
            dn.safeBatchTransferFromNFTs(t.from, t.from, to, t.ids);
            dn.safeBatchTransferFromNFTs(t.from, t.from, to, dn.findOwnedIds(t.from));
            dn.safeBatchTransferFromNFTs(to, to, t.from, dn.findOwnedIds(to));

            if (_random() % 2 == 0) {
                t.ids = dn.findOwnedIds(t.from);
                LibSort.sort(t.ids);
                t.oriIds = t.ids;
                t.ids = LibSort.union(t.ids, _randomSampleWithoutReplacements(t.ids));
                if (t.ids.length > t.oriIds.length) {
                    if (t.from != to) {
                        vm.expectRevert(DN420.TransferFromIncorrectOwner.selector);
                        dn.safeBatchTransferFromNFTs(t.from, t.from, to, t.ids);
                    } else if (_random() % 2 == 0) {
                        t.balanceBefore = dn.balanceOf(t.from);
                        dn.safeBatchTransferFromNFTs(t.from, t.from, to, t.ids);
                        assertEq(dn.balanceOf(t.from), t.balanceBefore);
                    } else {
                        t.oriIds = dn.findOwnedIds(t.from);
                        dn.safeBatchTransferFromNFTs(t.from, t.from, to, t.ids);
                        assertEq(dn.findOwnedIds(t.from), t.oriIds);
                    }
                } else {
                    dn.safeBatchTransferFromNFTs(t.from, t.from, to, t.ids);
                    dn.safeBatchTransferFromNFTs(to, to, t.from, t.ids);
                }
            }
        }
    }

    function _safeTransferFromNFT(address by, address from, address to, uint256 id) internal {
        if (_random() % 2 == 0) {
            dn.safeTransferFromNFT(by, from, to, id);
        } else {
            dn.safeBatchTransferFromNFTs(by, from, to, _filled(1, id));
        }
    }

    function _randomBytes() internal returns (bytes memory b) {
        uint256 r = _random();
        /// @solidity memory-safe-assembly
        assembly {
            b := mload(0x40)
            mstore(b, mod(r, 65))
            let t := add(b, 0x20)
            mstore(t, r)
            mstore(add(b, 0x40), keccak256(t, 0x20))
            mstore(0x40, add(b, 0x60))
        }
    }
}
