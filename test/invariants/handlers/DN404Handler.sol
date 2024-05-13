// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../utils/SoladyTest.sol";
import {MockDN404} from "../../utils/mocks/MockDN404.sol";
import {MockDN404CustomUnit} from "../../utils/mocks/MockDN404CustomUnit.sol";
import {DN404Mirror} from "../../../src/DN404Mirror.sol";
import {DN404} from "../../../src/DN404.sol";

contract DN404Handler is SoladyTest {
    uint256 private constant _WAD = 1000000000000000000;
    uint256 private constant START_SLOT =
        0x0000000000000000000000000000000000000000000000a20d6e21d0e5255308;
    uint8 internal constant _ADDRESS_DATA_SKIP_NFT_FLAG = 1 << 1;

    MockDN404CustomUnit dn404;
    DN404Mirror mirror;

    address user0 = vm.addr(uint256(keccak256("User0")));
    address user1 = vm.addr(uint256(keccak256("User1")));
    address user2 = vm.addr(uint256(keccak256("User2")));
    address user3 = vm.addr(uint256(keccak256("User3")));
    address user4 = vm.addr(uint256(keccak256("User4")));
    address user5 = vm.addr(uint256(keccak256("User5")));

    address[6] actors;

    mapping(address => uint256) public nftsOwned;

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    // Avoid stack-to-deep errors.
    struct BeforeAfter {
        uint256 fromBalanceBefore;
        uint256 toBalanceBefore;
        uint256 totalSupplyBefore;
        uint256 totalNFTSupplyBefore;
        uint256 fromNFTBalanceBefore;
        uint256 toNFTBalanceBefore;
        uint256 fromAuxBefore;
        uint256 toAuxBefore;
        uint256 fromBalanceAfter;
        uint256 toBalanceAfter;
        uint256 totalSupplyAfter;
        uint256 totalNFTSupplyAfter;
        uint256 fromNFTBalanceAfter;
        uint256 toNFTBalanceAfter;
        uint256 fromAuxAfter;
        uint256 toAuxAfter;
    }

    constructor(MockDN404CustomUnit _dn404) {
        dn404 = _dn404;
        mirror = DN404Mirror(payable(dn404.mirrorERC721()));

        actors[0] = user0;
        actors[1] = user1;
        actors[2] = user2;
        actors[3] = user3;
        actors[4] = user4;
        actors[5] = user5;

        vm.prank(user0);
        dn404.approve(user0, type(uint256).max);

        vm.prank(user1);
        dn404.approve(user1, type(uint256).max);

        vm.prank(user2);
        dn404.approve(user2, type(uint256).max);

        vm.prank(user3);
        dn404.approve(user3, type(uint256).max);

        vm.prank(user4);
        dn404.approve(user4, type(uint256).max);

        vm.prank(user5);
        dn404.approve(user5, type(uint256).max);
    }

    function randomAddress(uint256 seed) private view returns (address) {
        return actors[_bound(seed, 0, actors.length - 1)];
    }

    struct ApproveTemps {
        address owner;
        address spender;
        uint256 ownerAuxBefore;
        uint256 ownerAuxAfter;
        uint256 spenderAuxBefore;
        uint256 spenderAuxAfter;
    }

    function approve(uint256 ownerIndexSeed, uint256 spenderIndexSeed, uint256 amount) public {
        ApproveTemps memory t;
        // PRE-CONDITIONS
        t.owner = randomAddress(ownerIndexSeed);
        t.spender = randomAddress(spenderIndexSeed);
        t.ownerAuxBefore = dn404.getAux(t.owner);
        t.spenderAuxBefore = dn404.getAux(t.spender);

        if (t.owner == t.spender) return;

        // ACTION
        vm.startPrank(t.owner);
        dn404.approve(t.spender, amount);

        // POST-CONDITIONS
        t.ownerAuxAfter = dn404.getAux(t.owner);
        t.spenderAuxAfter = dn404.getAux(t.spender);

        assertEq(dn404.allowance(t.owner, t.spender), amount, "Allowance != Amount");
        // Assert auxiliary data is unchanged.
        assertEq(t.ownerAuxBefore, t.ownerAuxAfter, "owner auxiliary data has changed");
        assertEq(t.spenderAuxBefore, t.spenderAuxAfter, "spender auxiliary data has changed");
    }

    struct TransferTemps {
        address sender;
        address from;
        address to;
        uint256 numNFTBurns;
        uint256 numNFTMints;
        uint256 n;
        uint256[] burnedIds;
        bool success;
        uint256 id;
    }

    function transfer(uint256 fromIndexSeed, uint256 toIndexSeed, uint256 amount) public {
        TransferTemps memory t;
        // PRE-CONDITIONS
        t.from = randomAddress(fromIndexSeed);
        t.to = randomAddress(toIndexSeed);
        amount = _bound(amount, 0, dn404.balanceOf(t.from));
        vm.startPrank(t.from);

        BeforeAfter memory beforeAfter;
        beforeAfter.fromBalanceBefore = dn404.balanceOf(t.from);
        beforeAfter.toBalanceBefore = dn404.balanceOf(t.to);
        beforeAfter.totalSupplyBefore = dn404.totalSupply();
        beforeAfter.toAuxBefore = dn404.getAux(t.to);

        t.numNFTBurns = _zeroFloorSub(
            mirror.balanceOf(t.from), (beforeAfter.fromBalanceBefore - amount) / dn404.unit()
        );
        t.numNFTMints = _zeroFloorSub(
            (beforeAfter.toBalanceBefore + amount) / dn404.unit(), mirror.balanceOf(t.to)
        );
        t.n = _min(mirror.balanceOf(t.from), _min(t.numNFTBurns, t.numNFTMints));
        t.burnedIds = dn404.burnedPool();

        // ACTION
        vm.recordLogs();
        (t.success,) =
            address(dn404).call(abi.encodeWithSelector(DN404.transfer.selector, t.to, amount));

        // POST-CONDITIONS
        if (t.success) {
            _checkPostTransferInvariants(beforeAfter, t, amount);
        }
    }

    function transferFrom(
        uint256 senderIndexSeed,
        uint256 fromIndexSeed,
        uint256 toIndexSeed,
        uint256 amount
    ) public {
        TransferTemps memory t;
        // PRE-CONDITIONS
        t.sender = randomAddress(senderIndexSeed);
        t.from = randomAddress(fromIndexSeed);
        t.to = randomAddress(toIndexSeed);
        amount = _bound(amount, 0, dn404.balanceOf(t.from));
        vm.startPrank(t.sender);

        BeforeAfter memory beforeAfter;
        beforeAfter.fromBalanceBefore = dn404.balanceOf(t.from);
        beforeAfter.toBalanceBefore = dn404.balanceOf(t.to);
        beforeAfter.totalSupplyBefore = dn404.totalSupply();
        beforeAfter.toAuxBefore = dn404.getAux(t.to);

        t.numNFTBurns = _zeroFloorSub(
            mirror.balanceOf(t.from), (beforeAfter.fromBalanceBefore - amount) / dn404.unit()
        );
        t.numNFTMints = _zeroFloorSub(
            (beforeAfter.toBalanceBefore + amount) / dn404.unit(), mirror.balanceOf(t.to)
        );
        t.n = _min(mirror.balanceOf(t.from), _min(t.numNFTBurns, t.numNFTMints));
        t.burnedIds = dn404.burnedPool();

        if (dn404.allowance(t.from, t.sender) < amount) {
            t.sender = t.from;
            vm.startPrank(t.sender);
        }

        // ACTION
        vm.recordLogs();
        (t.success,) = address(dn404).call(
            abi.encodeWithSelector(DN404.transferFrom.selector, t.from, t.to, amount)
        );

        // POST-CONDITIONS
        if (t.success) {
            _checkPostTransferInvariants(beforeAfter, t, amount);
        }
    }

    function _checkPostTransferInvariants(
        BeforeAfter memory beforeAfter,
        TransferTemps memory t,
        uint256 amount
    ) internal {
        unchecked {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i = 0; i < logs.length; i++) {
                if (
                    i < logs.length
                        && logs[i].topics[0] == keccak256("Transfer(address,address,uint256)")
                ) {
                    // Grab minted ID from logs.
                    if (logs[i].topics.length > 3) t.id = uint256(logs[i].topics[3]);
                    if (t.n > 0 && t.from != t.to) {
                        for (uint256 j = 0; j < t.burnedIds.length; j++) {
                            // Assert direct transfers do not overlap with burned pool.
                            if (dn404.useDirectTransfersIfPossible() && i < t.n) {
                                assertNotEq(
                                    t.burnedIds[j], t.id, "transfer direct went over burned ids"
                                );
                            }
                        }
                    }
                    // Assert approval for id has been reset during transfer.
                    if (mirror.ownerAt(t.id) != address(0)) {
                        assertEq(mirror.getApproved(t.id), address(0));
                    }
                }
            }
        }

        nftsOwned[t.from] -= _zeroFloorSub(
            nftsOwned[t.from], (beforeAfter.fromBalanceBefore - amount) / dn404.unit()
        );
        if (!dn404.getSkipNFT(t.to)) {
            if (t.from == t.to) beforeAfter.toBalanceBefore -= amount;
            nftsOwned[t.to] += _zeroFloorSub(
                (beforeAfter.toBalanceBefore + amount) / dn404.unit(), nftsOwned[t.to]
            );
        }

        beforeAfter.fromBalanceAfter = dn404.balanceOf(t.from);
        beforeAfter.toBalanceAfter = dn404.balanceOf(t.to);
        beforeAfter.totalSupplyAfter = dn404.totalSupply();
        beforeAfter.toAuxAfter = dn404.getAux(t.to);

        // Assert balance updates between addresses are valid.
        if (t.from != t.to) {
            assertEq(
                beforeAfter.fromBalanceAfter + amount,
                beforeAfter.fromBalanceBefore,
                "balance after + amount != balance before"
            );
            assertEq(
                beforeAfter.toBalanceAfter,
                beforeAfter.toBalanceBefore + amount,
                "balance after != balance before + amount"
            );
        } else {
            assertEq(
                beforeAfter.fromBalanceAfter,
                beforeAfter.fromBalanceBefore,
                "balance after != balance before"
            );
        }

        // Assert totalSupply stays the same.
        assertEq(
            beforeAfter.totalSupplyBefore,
            beforeAfter.totalSupplyAfter,
            "total supply before != total supply after"
        );
        // Assert auxiliary data is unchanged.
        assertEq(beforeAfter.toAuxBefore, beforeAfter.toAuxAfter, "auxiliary data has changed");
    }

    struct MintTemps {
        address to;
        bool success;
        uint256 transferCounter;
        uint256 head;
        uint256 tail;
    }

    function mint(uint256 toIndexSeed, uint256 amount) public {
        MintTemps memory t;
        // PRE-CONDITIONS
        t.to = randomAddress(toIndexSeed);
        amount = _bound(amount, 0, 100e18);

        BeforeAfter memory beforeAfter;
        beforeAfter.toBalanceBefore = dn404.balanceOf(t.to);
        beforeAfter.totalSupplyBefore = dn404.totalSupply();
        beforeAfter.totalNFTSupplyBefore = mirror.totalSupply();
        beforeAfter.toNFTBalanceBefore = dn404.balanceOfNFT(t.to);
        beforeAfter.toAuxBefore = dn404.getAux(t.to);

        // ACTION
        vm.recordLogs();
        (t.success,) =
            address(dn404).call(abi.encodeWithSelector(MockDN404.mint.selector, t.to, amount)); // mint(to, amount);

        // POST-CONDITIONS
        if (t.success) {
            beforeAfter.toBalanceAfter = dn404.balanceOf(t.to);
            beforeAfter.totalSupplyAfter = dn404.totalSupply();
            beforeAfter.totalNFTSupplyAfter = mirror.totalSupply();
            beforeAfter.toAuxAfter = dn404.getAux(t.to);

            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint256 i = 0; i < logs.length; i++) {
                if (
                    i < logs.length
                        && logs[i].topics[0] == keccak256("Transfer(address,address,uint256)")
                ) {
                    t.transferCounter += 1;
                    assertEq(
                        address(uint160(uint256(logs[i].topics[1]))),
                        address(0),
                        "from address does not match event"
                    );
                    assertEq(
                        address(uint160(uint256(logs[i].topics[2]))),
                        t.to,
                        "to address does not match event"
                    );
                    if (logs[i].topics.length > 3) {
                        assertEq(
                            mirror.ownerAt(uint256(logs[i].topics[3])),
                            t.to,
                            "to address does not own minted id"
                        );
                    }
                }
            }

            if (!dn404.getSkipNFT(t.to)) {
                nftsOwned[t.to] = (beforeAfter.toBalanceBefore + amount) / dn404.unit();
                assertEq(dn404.tokensOf(t.to).length, nftsOwned[t.to], "owned != len(tokensOf)");
                // Assert that number of (Transfer events - 1) should match the loop iterations to mint an NFT in `mint`.
                // Subtract by 1 because one of the Transfer events is for the ERC20 transfer.
                assertEq(
                    t.transferCounter - 1,
                    _zeroFloorSub(
                        (beforeAfter.toBalanceAfter / dn404.unit()), beforeAfter.toNFTBalanceBefore
                    ),
                    "# of times transfer emitted != mint loop iterations"
                );
            }

            _checkPostMintInvariants(beforeAfter, amount);
        }
    }

    function mintNext(uint256 toIndexSeed, uint256 amount) public {
        MintTemps memory t;
        // PRE-CONDITIONS
        t.to = randomAddress(toIndexSeed);
        amount = _bound(amount, 0, 100e18);

        BeforeAfter memory beforeAfter;
        beforeAfter.toBalanceBefore = dn404.balanceOf(t.to);
        beforeAfter.totalSupplyBefore = dn404.totalSupply();
        beforeAfter.totalNFTSupplyBefore = mirror.totalSupply();
        beforeAfter.toNFTBalanceBefore = dn404.balanceOfNFT(t.to);
        beforeAfter.toAuxBefore = dn404.getAux(t.to);

        // ACTION
        vm.recordLogs();
        dn404.mintNext(t.to, amount);

        // POST-CONDITIONS
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("Transfer(address,address,uint256)")) {
                t.transferCounter += 1;
                assertEq(
                    address(uint160(uint256(logs[i].topics[1]))),
                    address(0),
                    "from address does not match event"
                );
                assertEq(
                    address(uint160(uint256(logs[i].topics[2]))),
                    t.to,
                    "to address does not match event"
                );
                if (logs[i].topics.length > 3) {
                    assertEq(
                        mirror.ownerAt(uint256(logs[i].topics[3])),
                        t.to,
                        "to address does not own minted id"
                    );
                }
            }
        }

        beforeAfter.toBalanceAfter = dn404.balanceOf(t.to);
        beforeAfter.totalSupplyAfter = dn404.totalSupply();
        beforeAfter.totalNFTSupplyAfter = mirror.totalSupply();
        beforeAfter.toAuxAfter = dn404.getAux(t.to);

        if (!dn404.getSkipNFT(t.to)) {
            nftsOwned[t.to] = (beforeAfter.toBalanceBefore + amount) / dn404.unit();
            assertEq(dn404.tokensOf(t.to).length, nftsOwned[t.to], "owned != len(tokensOf)");
            assertEq(
                t.transferCounter - 1,
                _zeroFloorSub(
                    (beforeAfter.toBalanceAfter / dn404.unit()), beforeAfter.toNFTBalanceBefore
                ),
                "# of times transfer emitted != mint loop iterations"
            );
        }
        // If NFT was minted, ensure burned pool head and tail are 0.
        if (t.transferCounter > 1) {
            (t.head, t.tail) = dn404.burnedPoolHeadTail();
            assertTrue(t.head == 0 && t.tail == 0, "Head or Tail != 0");
        }

        _checkPostMintInvariants(beforeAfter, amount);
    }

    function _checkPostMintInvariants(BeforeAfter memory beforeAfter, uint256 amount) internal {
        // Assert user balance increased by minted amount.
        assertEq(
            beforeAfter.toBalanceAfter,
            beforeAfter.toBalanceBefore + amount,
            "balance after != balance before + amount"
        );
        // Assert totalSupply increased by minted amount.
        assertEq(
            beforeAfter.totalSupplyBefore + amount,
            beforeAfter.totalSupplyAfter,
            "supply after != supply before + amount"
        );
        // Assert totalNFTSupply is at least equal to prior state before mint.
        assertGe(
            beforeAfter.totalNFTSupplyAfter,
            beforeAfter.totalNFTSupplyBefore,
            "nft supply after < nft supply before"
        );
        // Assert auxiliary data is unchanged.
        assertEq(beforeAfter.toAuxBefore, beforeAfter.toAuxAfter, "auxiliary data has changed");
    }

    struct BurnTemps {
        address from;
        uint256 fromBalanceBefore;
        uint256 totalSupplyBefore;
        uint256 fromNFTBalanceBefore;
        uint256 totalNFTSupplyBefore;
        uint256 fromAuxBefore;
        uint256 numToBurn;
        uint256[] tokensAfter;
        uint256 totalSupplyAfter;
        uint256 fromNFTBalanceAfter;
        uint256 totalNFTSupplyAfter;
        uint256 fromAuxAfter;
    }

    function burn(uint256 fromIndexSeed, uint256 amount) public {
        BurnTemps memory t;
        // PRE-CONDITIONS
        t.from = randomAddress(fromIndexSeed);
        vm.startPrank(t.from);
        amount = _bound(amount, 0, dn404.balanceOf(t.from));

        t.fromBalanceBefore = dn404.balanceOf(t.from);
        t.totalSupplyBefore = dn404.totalSupply();
        t.fromNFTBalanceBefore = mirror.balanceOf(t.from);
        t.totalNFTSupplyBefore = mirror.totalSupply();
        t.fromAuxBefore = dn404.getAux(t.from);

        // ACTION
        dn404.burn(t.from, amount);

        // POST-CONDITIONS
        t.numToBurn =
            _zeroFloorSub(nftsOwned[t.from], (t.fromBalanceBefore - amount) / dn404.unit());
        nftsOwned[t.from] -= t.numToBurn;

        t.tokensAfter = dn404.tokensOf(t.from);
        t.totalSupplyAfter = dn404.totalSupply();
        t.fromNFTBalanceAfter = mirror.balanceOf(t.from);
        t.totalNFTSupplyAfter = mirror.totalSupply();
        t.fromAuxAfter = dn404.getAux(t.from);
        // Assert user tokensOf was reduced by numToBurn.
        assertEq(t.tokensAfter.length, nftsOwned[t.from], "owned != len(tokensOf)");
        // Assert totalSupply decreased by burned amount.
        assertEq(
            t.totalSupplyBefore,
            t.totalSupplyAfter + amount,
            "supply before != supply after + amount"
        );
        // Assert NFT balance decreased by numToBurn.
        assertEq(
            t.fromNFTBalanceBefore,
            t.fromNFTBalanceAfter + t.numToBurn,
            "NFT balance did not decrease appropriately"
        );
        // Assert totalNFTSupply is at most equal to prior state before mint.
        assertLe(
            t.totalNFTSupplyAfter, t.totalNFTSupplyBefore, "nft supply after > nft supply before"
        );
        // Assert auxiliary data is unchanged.
        assertEq(t.fromAuxBefore, t.fromAuxAfter, "auxiliary data has changed");
    }

    function setSkipNFT(uint256 actorIndexSeed, bool status) public {
        // PRE-CONDITIONS
        address actor = randomAddress(actorIndexSeed);
        uint256 actorAuxBefore = dn404.getAux(actor);

        // ACTION
        vm.startPrank(actor);
        dn404.setSkipNFT(status);

        // POST-CONDITIONS
        bool isSkipNFT = dn404.getSkipNFT(actor);
        uint256 actorAuxAfter = dn404.getAux(actor);
        // Assert skipNFT status is appropriately set.
        assertEq(isSkipNFT, status, "isSKipNFT != status");
        // Assert auxiliary data is unchanged.
        assertEq(actorAuxBefore, actorAuxAfter, "auxiliary data has changed");
    }

    struct ApproveNFTTemps {
        address owner;
        address spender;
        address approvedSpenderMirror;
        address approvedSpenderDN;
        uint256 ownerAuxBefore;
        uint256 spenderAuxBefore;
        address ownerAfter;
        uint256 ownerAuxAfter;
        uint256 spenderAuxAfter;
    }

    function approveNFT(uint256 ownerIndexSeed, uint256 spenderIndexSeed, uint256 id) public {
        ApproveNFTTemps memory t;
        // PRE-CONDITIONS
        t.owner = randomAddress(ownerIndexSeed);
        t.spender = randomAddress(spenderIndexSeed);

        if (mirror.ownerAt(id) == address(0)) return;
        if (mirror.ownerAt(id) != t.owner) {
            t.owner = mirror.ownerAt(id);
        }
        t.ownerAuxBefore = dn404.getAux(t.owner);
        t.spenderAuxBefore = dn404.getAux(t.spender);

        // ACTION
        vm.startPrank(t.owner);
        mirror.approve(t.spender, id);

        // POST-CONDITIONS
        t.approvedSpenderMirror = mirror.getApproved(id);
        t.approvedSpenderDN = dn404.getApproved(id);
        t.ownerAfter = mirror.ownerAt(id);
        t.ownerAuxAfter = dn404.getAux(t.owner);
        t.spenderAuxAfter = dn404.getAux(t.spender);
        // Assert approved spender is requested spender.
        assertEq(t.approvedSpenderMirror, t.spender, "spender != approved spender mirror");
        assertEq(t.approvedSpenderDN, t.spender, "spender != approved spender DN");
        // Assert that owner of ID did not change.
        assertEq(t.owner, t.ownerAfter, "owner changed on approval");
        // Assert auxiliary data is unchanged.
        assertEq(t.ownerAuxBefore, t.ownerAuxAfter, "owner auxiliary data has changed");
        assertEq(t.spenderAuxBefore, t.spenderAuxAfter, "spender auxiliary data has changed");
    }

    struct SetApprovalForAllTemps {
        address owner;
        address spender;
        uint256 ownerAuxBefore;
        uint256 spenderAuxBefore;
        bool approvedForAll;
        uint256 ownerAuxAfter;
        uint256 spenderAuxAfter;
    }

    function setApprovalForAll(
        uint256 ownerIndexSeed,
        uint256 spenderIndexSeed,
        uint256 id,
        bool approval
    ) public {
        id = id; // Silence unused variable warning.
        SetApprovalForAllTemps memory t;
        // PRE-CONDITIONS
        t.owner = randomAddress(ownerIndexSeed);
        t.spender = randomAddress(spenderIndexSeed);
        t.ownerAuxBefore = dn404.getAux(t.owner);
        t.spenderAuxBefore = dn404.getAux(t.spender);

        // ACTION
        vm.startPrank(t.owner);
        mirror.setApprovalForAll(t.spender, approval);

        // POST-CONDITIONS
        t.approvedForAll = mirror.isApprovedForAll(t.owner, t.spender);
        t.ownerAuxAfter = dn404.getAux(t.owner);
        t.spenderAuxAfter = dn404.getAux(t.spender);
        // Assert approval status is updated correctly.
        assertEq(t.approvedForAll, approval, "approved for all != approval");
        // Assert auxiliary data is unchanged.
        assertEq(t.ownerAuxBefore, t.ownerAuxAfter, "owner auxiliary data has changed");
        assertEq(t.spenderAuxBefore, t.spenderAuxAfter, "spender auxiliary data has changed");
    }

    struct TransferFromNFTTemps {
        address sender;
        address from;
        address to;
        uint256[] tokensFromAfter;
        uint256[] tokensToAfter;
    }

    function transferFromNFT(
        uint256 senderIndexSeed,
        uint256 fromIndexSeed,
        uint256 toIndexSeed,
        uint32 id
    ) public {
        TransferFromNFTTemps memory t;
        // PRE-CONDITIONS
        t.sender = randomAddress(senderIndexSeed);
        t.from = randomAddress(fromIndexSeed);
        t.to = randomAddress(toIndexSeed);

        if (mirror.ownerAt(id) == address(0)) return;
        if (mirror.getApproved(id) != t.sender || mirror.isApprovedForAll(t.from, t.sender)) {
            t.sender = t.from;
        }
        if (mirror.ownerAt(id) != t.from) {
            t.from = mirror.ownerAt(id);
            t.sender = t.from;
        }

        BeforeAfter memory beforeAfter;
        beforeAfter.fromBalanceBefore = dn404.balanceOf(t.from);
        beforeAfter.toBalanceBefore = dn404.balanceOf(t.to);
        beforeAfter.totalNFTSupplyBefore = mirror.totalSupply();
        beforeAfter.fromAuxBefore = dn404.getAux(t.from);
        beforeAfter.toAuxBefore = dn404.getAux(t.to);

        // ACTION
        vm.startPrank(t.sender);
        mirror.transferFrom(t.from, t.to, id);

        // POST-CONDITIONS
        --nftsOwned[t.from];
        ++nftsOwned[t.to];

        t.tokensFromAfter = dn404.tokensOf(t.from);
        t.tokensToAfter = dn404.tokensOf(t.to);
        beforeAfter.fromBalanceAfter = dn404.balanceOf(t.from);
        beforeAfter.toBalanceAfter = dn404.balanceOf(t.to);
        beforeAfter.totalNFTSupplyAfter = mirror.totalSupply();
        beforeAfter.fromAuxAfter = dn404.getAux(t.from);
        beforeAfter.toAuxAfter = dn404.getAux(t.to);

        // Assert length matches internal tracking.
        assertEq(t.tokensFromAfter.length, nftsOwned[t.from], "Owned != len(tokensOfFrom)");
        assertEq(t.tokensToAfter.length, nftsOwned[t.to], "Owned != len(tokensOfTo)");
        // Assert token balances for `from` and `to` was updated.
        if (t.from != t.to) {
            assertEq(
                beforeAfter.fromBalanceBefore,
                beforeAfter.fromBalanceAfter + dn404.unit(),
                "before != after + unit"
            );
            assertEq(
                beforeAfter.toBalanceAfter,
                beforeAfter.toBalanceBefore + dn404.unit(),
                "after != before + unit"
            );
        } else {
            assertEq(beforeAfter.fromBalanceBefore, beforeAfter.fromBalanceAfter, "before != after");
            assertEq(beforeAfter.toBalanceAfter, beforeAfter.toBalanceBefore, "after != before");
        }
        // Assert `to` address owns the transferred NFT.
        assertEq(mirror.ownerAt(id), t.to, "to != ownerOf");
        // Assert totalNFTSupply is unchanged.
        assertEq(
            beforeAfter.totalNFTSupplyBefore,
            beforeAfter.totalNFTSupplyAfter,
            "total supply before != total supply after"
        );
        // Assert that approval is reset on transfer.
        assertEq(mirror.getApproved(id), address(0));
        // Assert auxiliary data is unchanged.
        assertEq(
            beforeAfter.fromAuxBefore, beforeAfter.fromAuxAfter, "from auxiliary data has changed"
        );
        assertEq(beforeAfter.toAuxBefore, beforeAfter.toAuxAfter, "to auxiliary data has changed");
    }

    function _zeroFloorSub(uint256 x, uint256 y) private pure returns (uint256 z) {
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

    function setUseExistsLookup(bool value) public {
        dn404.setUseExistsLookup(value);
    }

    function setUseDirectTransfersIfPossible(bool value) public {
        dn404.setUseDirectTransfersIfPossible(value);
    }

    function setAddToBurnedPool(bool value) public {
        dn404.setAddToBurnedPool(value);
    }

    function setUnit(uint256 value) public {
        value = _bound(value, 1e16, 1e20);
        dn404.setUnit(value);
    }

    function setAux(address target, uint88 value) public {
        dn404.setAux(target, value);
    }
}
