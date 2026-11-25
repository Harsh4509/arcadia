/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import {
    Claimable,
    Config,
    Epoch,
    ExchangeRate,
    PoolTokens,
    Record,
    RewardAccount,
    ShareAccount
} from "../../../src/core/types/State.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SlotDerivation } from "@openzeppelin/contracts/utils/SlotDerivation.sol";
import { STATE_SLOT, TRANSIENT_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the storage layout of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract StorageSlots_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_storageSlots_RootsMatchErc7201(uint256 pick) public pure {
        // Given: One of the two roots and its ERC-7201 namespace.
        bool isTransient = bound(pick, 0, 1) == 1;
        bytes32 root = isTransient ? TRANSIENT_SLOT : STATE_SLOT;
        string memory namespace = isTransient ? "arcadia.alm.core.transient" : "arcadia.alm.core";

        // When: Deriving the root with OpenZeppelin's ERC-7201 formula.
        bytes32 derived = SlotDerivation.erc7201Slot(namespace);

        // Then: It is the constant the core uses.
        assertEq(root, derived);
    }

    function testFuzz_Success_storageSlots_ConfigWordsReadThroughTheGetters(
        uint256 caps,
        uint256 pauseAndFees,
        uint256 planBounds,
        address feeRecipient
    ) public {
        // Given: The four config words written at B + 0 .. B + 3.
        vm.store(address(almCore), STATE_SLOT, bytes32(caps));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 1), bytes32(pauseAndFees));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 2), bytes32(planBounds));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 3), bytes32(uint256(uint160(feeRecipient))));

        // When: Reading them through the getters.
        Config memory read = coreViewLogic.getConfig(address(almCore));

        // Then: Every field reads back from its bits.
        assertEq(read.totalCap, uint128(caps));
        assertEq(read.perUserCap, uint128(caps >> 128));
        assertEq(read.paused, uint8(pauseAndFees) != 0);
        assertEq(read.protocolEmissionFeeBps, uint16(pauseAndFees >> 8));
        assertEq(read.protocolSwapFeeBps, uint16(pauseAndFees >> 24));
        assertEq(read.twapWindow, uint32(pauseAndFees >> 40));
        assertEq(read.maxSpotFromTwap, uint64(pauseAndFees >> 72));
        assertEq(read.maxSpotFromTrusted, uint64(pauseAndFees >> 136));
        assertEq(read.rewardPoolToken, uint8(pauseAndFees >> 248));
        assertEq(read.maxTwapFromTrusted, uint64(planBounds));
        assertEq(read.maxShortfallBps, uint16(planBounds >> 64));
        assertEq(read.maxSwapCostBps, uint16(planBounds >> 80));
        assertEq(read.minPlanInterval, uint32(planBounds >> 96));
        assertEq(read.rangeCap, uint8(planBounds >> 128));
        assertEq(read.lastPlanAt, uint32(planBounds >> 136));
        assertEq(read.arbBlockNumber, uint8(planBounds >> 168) != 0);
        assertEq(read.feeRecipient, feeRecipient);
    }

    function testFuzz_Success_storageSlots_RewardWordsReadThroughTheGetter(
        uint256 rewardPerShare,
        uint256 claimed,
        uint256 protocolReward,
        uint128 preCredited
    ) public {
        // Given: The four reward words written at B + 4 .. B + 7.
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 4), bytes32(rewardPerShare));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 5), bytes32(claimed));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 6), bytes32(protocolReward));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 7), bytes32(uint256(preCredited)));

        // When: Reading them through the getter.
        (uint128 read0, uint128 read1, uint128 read2, uint128 read3, uint128 read4, uint128 read5, uint128 read6) =
            coreViewLogic.getRewards(address(almCore));

        // Then: Every half reads back.
        assertEq(read0, uint128(rewardPerShare));
        assertEq(read1, uint128(rewardPerShare >> 128));
        assertEq(read2, uint128(claimed));
        assertEq(read3, uint128(claimed >> 128));
        assertEq(read4, uint128(protocolReward));
        assertEq(read5, uint128(protocolReward >> 128));
        assertEq(read6, preCredited);
    }

    function testFuzz_Success_storageSlots_ShareWordsReadThroughTheGetters(
        uint256 supplyPerValueX128,
        uint160 sqrtPriceX96
    ) public {
        // Given: The last exchange rate at B + 9 .. B + 10.
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 9), bytes32(supplyPerValueX128));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 10), bytes32(uint256(sqrtPriceX96)));

        // When: Reading it through the getter.
        ExchangeRate memory rateRead = coreViewLogic.getLastExchangeRate(address(almCore));

        // Then: Every field reads back.
        assertEq(rateRead.supplyPerValueX128, supplyPerValueX128);
        assertEq(rateRead.sqrtPriceX96, sqrtPriceX96);
    }

    function testFuzz_Success_storageSlots_AccountMappingsReadThroughTheGetters(
        address account,
        address operator,
        uint256 rewardWord,
        uint256 shareWord,
        bool approved,
        bool exempt
    ) public {
        // Given: An account's entries in the mappings at B + 8, 13, 14 and 15.
        vm.store(
            address(almCore), keccak256(abi.encode(account, bytes32(uint256(STATE_SLOT) + 8))), bytes32(rewardWord)
        );
        vm.store(
            address(almCore), keccak256(abi.encode(account, bytes32(uint256(STATE_SLOT) + 13))), bytes32(shareWord)
        );
        vm.store(
            address(almCore),
            keccak256(abi.encode(operator, keccak256(abi.encode(account, bytes32(uint256(STATE_SLOT) + 14))))),
            bytes32(uint256(approved ? 1 : 0))
        );
        vm.store(
            address(almCore),
            keccak256(abi.encode(account, bytes32(uint256(STATE_SLOT) + 15))),
            bytes32(uint256(exempt ? 1 : 0))
        );

        // When: Reading them through the getters.
        RewardAccount memory rewardRead = coreViewLogic.getRewardAccount(address(almCore), account);
        ShareAccount memory shareRead = coreViewLogic.getShareAccount(address(almCore), account);

        // Then: Every entry reads back.
        assertEq(rewardRead.rewardPerSharePaid, uint128(rewardWord));
        assertEq(rewardRead.rewardOwed, uint128(rewardWord >> 128));
        assertEq(shareRead.claimableShares, uint128(shareWord));
        assertEq(shareRead.pendingShares, uint128(shareWord >> 128));
        assertEq(coreViewLogic.isOperator(address(almCore), account, operator), approved);
        assertEq(coreViewLogic.isExempt(address(almCore), account), exempt);
    }

    function testFuzz_Success_storageSlots_PoolTokenWordsReadThroughTheGetters(
        uint256 buffers,
        uint256 protocolFees,
        uint256 escrowed
    ) public {
        // Given: The three pool token words written at B + 16 .. B + 18.
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 16), bytes32(buffers));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 17), bytes32(protocolFees));
        vm.store(address(almCore), bytes32(uint256(STATE_SLOT) + 18), bytes32(escrowed));

        // When: Reading them through the getters.
        PoolTokens memory read = coreViewLogic.getPoolTokens(address(almCore));
        (uint128 buffer0, uint128 buffer1) = coreViewLogic.getBuffer(address(almCore));

        // Then: Every half reads back.
        assertEq(read.buffer.amount0, uint128(buffers));
        assertEq(read.buffer.amount1, uint128(buffers >> 128));
        assertEq(read.protocolFees.amount0, uint128(protocolFees));
        assertEq(read.protocolFees.amount1, uint128(protocolFees >> 128));
        assertEq(read.escrowed.amount0, uint128(escrowed));
        assertEq(read.escrowed.amount1, uint128(escrowed >> 128));
        assertEq(buffer0, read.buffer.amount0);
        assertEq(buffer1, read.buffer.amount1);
    }

    function testFuzz_Success_storageSlots_ClaimablePilesReadThroughTheGetters(
        address vault,
        address controller_,
        uint256 depositWord,
        uint256 redeemWord
    ) public {
        // Given: A controller's deposit and redeem piles, at each queue's third mapping.
        uint256 base = uint256(keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20))));
        vm.store(address(almCore), keccak256(abi.encode(controller_, bytes32(base + 3))), bytes32(depositWord));
        vm.store(address(almCore), keccak256(abi.encode(controller_, bytes32(base + 7))), bytes32(redeemWord));

        // When: Reading them through the getters.
        (uint128 depositIn, uint128 depositOut) =
            coreViewLogic.getClaimableDeposit(address(almCore), vault, controller_);
        (uint128 redeemIn, uint128 redeemOut) = coreViewLogic.getClaimableRedeem(address(almCore), vault, controller_);

        // Then: Every half reads back.
        assertEq(depositIn, uint128(depositWord));
        assertEq(depositOut, uint128(depositWord >> 128));
        assertEq(redeemIn, uint128(redeemWord));
        assertEq(redeemOut, uint128(redeemWord >> 128));
    }

    function testFuzz_Success_storageSlots_CheckpointFlagAtT(address caller) public {
        // Given: A core as deployed, and any caller.

        // When: An execution checkpoints.
        vm.prank(caller);
        bytes32 word = almCore.writeCheckpointed();

        // Then: The checkpoint flag sits at T.
        assertEq(word, bytes32(uint256(1)));
    }

    function testFuzz_Success_storageSlots_PairwiseDistinct(uint256 pick) public pure {
        // Given: The state root, the transient slot, the supply slot and the guard slot.
        bytes32[4] memory slots =
            [STATE_SLOT, TRANSIENT_SLOT, Constants.TOTAL_SUPPLY_SLOT, Constants.FALLBACK_GUARD_SLOT];
        pick = bound(pick, 0, 3);

        // When: Comparing them pairwise.
        // Then: No two of them are the same slot, starting at the fuzzed one.
        for (uint256 i; i < slots.length; ++i) {
            for (uint256 j = i + 1; j < slots.length; ++j) {
                assertNotEq(slots[(pick + i) % 4], slots[(pick + j) % 4]);
            }
        }

        // And: None of the others falls inside the 21 slots State spans from B.
        for (uint256 i = 1; i < slots.length; ++i) {
            assertFalse(uint256(slots[i]) >= uint256(STATE_SLOT) && uint256(slots[i]) <= uint256(STATE_SLOT) + 20);
        }
    }

    function testFuzz_Success_storageSlots_NoStateVariables(uint256 pick) public {
        // Given: The build artifacts of the core and its two extensions.
        string[3] memory artifacts = [
            "out/ALMCore.sol/ALMCore.json",
            "out/ALMKeeperExtension.sol/ALMKeeperExtension.json",
            "out/ALMAdminExtension.sol/ALMAdminExtension.json"
        ];
        pick = bound(pick, 0, 2);

        for (uint256 i; i < 3; ++i) {
            // When: Reading the storage layout the compiler reports for each.
            string memory artifact = vm.readFile(artifacts[(pick + i) % 3]);

            // Then: The layout is there and lists no state variable.
            assertTrue(vm.keyExistsJson(artifact, ".storageLayout.storage"));
            assertFalse(vm.keyExistsJson(artifact, ".storageLayout.storage[0]"));
        }
    }

    function testFuzz_Success_storageSlots_NoTransientStateVariables(uint256 pick) public {
        // Given: The build artifacts of the core and its two extensions.
        string[3] memory artifacts = [
            "out/ALMCore.sol/ALMCore.json",
            "out/ALMKeeperExtension.sol/ALMKeeperExtension.json",
            "out/ALMAdminExtension.sol/ALMAdminExtension.json"
        ];
        pick = bound(pick, 0, 2);

        for (uint256 i; i < 3; ++i) {
            // When: Reading the transient storage layout the compiler reports for each.
            string memory artifact = vm.readFile(artifacts[(pick + i) % 3]);

            // Then: The layout is there and lists no transient state variable.
            assertTrue(vm.keyExistsJson(artifact, ".transientStorageLayout.storage"));
            assertFalse(vm.keyExistsJson(artifact, ".transientStorageLayout.storage[0]"));
        }
    }

    function testFuzz_Success_storageSlots_PoolTokens(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1
    ) public {
        // Given: A core as deployed.

        // When: Writing the buffer and the protocol fees.
        almCore.setBuffers(buffer0, buffer1);
        almCore.setFeesOwed(protocolFees0, protocolFees1, 0);

        // Then: B + 16 stores the buffer and B + 17 the fees, the first in the low half.
        assertEq(
            vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 16)), bytes32((uint256(buffer1) << 128) | buffer0)
        );
        assertEq(
            vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 17)),
            bytes32((uint256(protocolFees1) << 128) | protocolFees0)
        );
    }

    function testFuzz_Success_storageSlots_Config(Config memory config) public {
        // Given: A core as deployed.

        // When: Writing the configuration.
        almCore.setConfig(config);

        // Then: B + 0 stores the caps.
        assertEq(vm.load(address(almCore), STATE_SLOT), bytes32((uint256(config.perUserCap) << 128) | config.totalCap));

        // And: B + 1 stores the pause flag, fees, TWAP window, bands and reward slot.
        uint256 word = (config.paused ? 1 : 0) | (uint256(config.protocolEmissionFeeBps) << 8)
            | (uint256(config.protocolSwapFeeBps) << 24) | (uint256(config.twapWindow) << 40)
            | (uint256(config.maxSpotFromTwap) << 72) | (uint256(config.maxSpotFromTrusted) << 136)
            | (uint256(config.windowEnd) << 200) | (uint256(config.rewardPoolToken) << 248);
        assertEq(vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 1)), bytes32(word));

        // And: B + 2 stores the trusted TWAP band, the keeper bounds and the plan clock.
        word = uint256(config.maxTwapFromTrusted) | (uint256(config.maxShortfallBps) << 64)
            | (uint256(config.maxSwapCostBps) << 80) | (uint256(config.minPlanInterval) << 96)
            | (uint256(config.rangeCap) << 128) | (uint256(config.lastPlanAt) << 136)
            | (uint256(config.arbBlockNumber ? 1 : 0) << 168);
        assertEq(vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 2)), bytes32(word));

        // And: B + 3 stores the fee recipient.
        assertEq(
            vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 3)), bytes32(uint256(uint160(config.feeRecipient)))
        );
    }

    function testFuzz_Success_storageSlots_LastPlanAt(Config memory config, uint32 lastPlanAt) public {
        // Given: The keeper bounds that share the plan clock's word.
        almCore.setConfig(config);

        // When: Writing the plan clock.
        almCore.setLastPlanAt(lastPlanAt);

        // Then: B + 2 stores it above the bounds, which keep their values.
        uint256 word = uint256(config.maxTwapFromTrusted) | (uint256(config.maxShortfallBps) << 64)
            | (uint256(config.maxSwapCostBps) << 80) | (uint256(config.minPlanInterval) << 96)
            | (uint256(config.rangeCap) << 128) | (uint256(lastPlanAt) << 136)
            | (uint256(config.arbBlockNumber ? 1 : 0) << 168);
        assertEq(vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 2)), bytes32(word));
    }

    function testFuzz_Success_storageSlots_Ranges(Range memory range) public {
        // Given: A core as deployed.

        // When: Pushing a range.
        almCore.pushRange(range);

        // Then: B + 19 stores the length.
        assertEq(vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 19)), bytes32(uint256(1)));

        // And: The range's two words sit at keccak256(B + 19).
        bytes32 element = keccak256(abi.encode(bytes32(uint256(STATE_SLOT) + 19)));
        uint256 word = uint256(uint24(range.tickLower)) | (uint256(uint24(range.tickUpper)) << 24)
            | (uint256(range.unstakedTokenId) << 48) | (uint256(range.stakedLiquidity) << 128);
        assertEq(vm.load(address(almCore), element), bytes32(word));

        // And: The staked token id and block fill the second.
        word = uint256(range.stakedTokenId) | (uint256(range.stakedBlock) << 80);
        assertEq(vm.load(address(almCore), bytes32(uint256(element) + 1)), bytes32(word));
    }

    function testFuzz_Success_storageSlots_Escrow(uint128 escrowed0, uint128 escrowed1) public {
        // Given: A core as deployed.

        // When: Writing the escrow.
        almCore.setEscrowed(escrowed0, escrowed1);

        // Then: B + 18 stores it, token0 in the low half.
        assertEq(
            vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 18)),
            bytes32((uint256(escrowed1) << 128) | escrowed0)
        );
    }

    function testFuzz_Success_storageSlots_EpochIds(
        address vault,
        uint32 pendingDepositEpoch,
        uint32 lastClearedDepositEpoch,
        uint32 pendingRedeemEpoch,
        uint32 lastClearedRedeemEpoch
    ) public {
        // Given: A core as deployed.

        // When: Writing a vault's pending and last cleared epoch ids of both queues.
        almCore.setPendingEpochs(vault, pendingDepositEpoch, pendingRedeemEpoch);
        almCore.setLastClearedEpochs(vault, lastClearedDepositEpoch, lastClearedRedeemEpoch);

        // Then: Each queue packs them low to high in its first word.
        bytes32 base = keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20)));
        assertEq(
            vm.load(address(almCore), base),
            bytes32(uint256(pendingDepositEpoch) | uint256(lastClearedDepositEpoch) << 32)
        );
        assertEq(
            vm.load(address(almCore), bytes32(uint256(base) + 4)),
            bytes32(uint256(pendingRedeemEpoch) | uint256(lastClearedRedeemEpoch) << 32)
        );

        // And: The deposit ids read back through ALMCoreViewLogic.
        assertEq(coreViewLogic.getPendingDepositEpoch(address(almCore), vault), pendingDepositEpoch);
        assertEq(coreViewLogic.getLastClearedDepositEpoch(address(almCore), vault), lastClearedDepositEpoch);

        // And: The redeem ids read back through ALMCoreViewLogic.
        assertEq(coreViewLogic.getPendingRedeemEpoch(address(almCore), vault), pendingRedeemEpoch);
        assertEq(coreViewLogic.getLastClearedRedeemEpoch(address(almCore), vault), lastClearedRedeemEpoch);
    }

    function testFuzz_Success_storageSlots_Epochs(address vault, uint32 id, Epoch memory deposit, Epoch memory redeem)
        public
    {
        // Given: A core as deployed.

        // When: Writing a deposit and a redeem epoch under the same vault and id.
        almCore.setDepositEpoch(vault, id, deposit);
        almCore.setRedeemEpoch(vault, id, redeem);

        // Then: Each sits in its queue's epochs, base + 1 and base + 5, in one word.
        bytes32 base = keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20)));
        assertEq(
            vm.load(address(almCore), keccak256(abi.encode(uint256(id), bytes32(uint256(base) + 1)))),
            bytes32((uint256(deposit.amountOut) << 128) | deposit.amountIn)
        );
        assertEq(
            vm.load(address(almCore), keccak256(abi.encode(uint256(id), bytes32(uint256(base) + 5)))),
            bytes32((uint256(redeem.amountOut) << 128) | redeem.amountIn)
        );

        // And: Both read back through ALMCoreViewLogic.
        Epoch memory depositRead = coreViewLogic.getDepositEpoch(address(almCore), vault, id);
        Epoch memory redeemRead = coreViewLogic.getRedeemEpoch(address(almCore), vault, id);
        assertEq(abi.encode(depositRead), abi.encode(deposit));
        assertEq(abi.encode(redeemRead), abi.encode(redeem));
    }

    function testFuzz_Success_storageSlots_Records(
        address vault,
        address controller_,
        Record memory deposit,
        Record memory redeem
    ) public {
        // Given: A core as deployed.

        // When: Writing a deposit and a redeem record for one vault and controller.
        almCore.setDepositRecord(vault, controller_, deposit);
        almCore.setRedeemRecord(vault, controller_, redeem);

        // Then: Each sits in its queue's records, base + 2 and base + 6, in one word.
        bytes32 base = keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20)));
        assertEq(
            vm.load(address(almCore), keccak256(abi.encode(controller_, bytes32(uint256(base) + 2)))),
            bytes32((uint256(deposit.pendingShares) << 160) | (uint256(deposit.amountIn) << 32) | deposit.epoch)
        );
        assertEq(
            vm.load(address(almCore), keccak256(abi.encode(controller_, bytes32(uint256(base) + 6)))),
            bytes32((uint256(redeem.pendingShares) << 160) | (uint256(redeem.amountIn) << 32) | redeem.epoch)
        );

        // And: Both read back through ALMCoreViewLogic.
        Record memory depositRead = coreViewLogic.getDepositRecord(address(almCore), vault, controller_);
        Record memory redeemRead = coreViewLogic.getRedeemRecord(address(almCore), vault, controller_);
        assertEq(abi.encode(depositRead), abi.encode(deposit));
        assertEq(abi.encode(redeemRead), abi.encode(redeem));
    }

    function testFuzz_Success_storageSlots_Claimables(address vault, address controller_, Claimable memory claimable)
        public
    {
        // Given: A core as deployed.

        // When: Writing a deposit and a redeem pile for the same vault and controller.
        almCore.setClaimableDeposit(vault, controller_, claimable);
        almCore.setClaimableRedeem(
            vault, controller_, Claimable({ amountIn: claimable.amountOut, amountOut: claimable.amountIn })
        );

        // Then: Each sits in its queue's claimable, base + 3 and base + 7, in one word.
        bytes32 base = keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20)));
        assertEq(
            vm.load(address(almCore), keccak256(abi.encode(controller_, bytes32(uint256(base) + 3)))),
            bytes32((uint256(claimable.amountOut) << 128) | claimable.amountIn)
        );
        assertEq(
            vm.load(address(almCore), keccak256(abi.encode(controller_, bytes32(uint256(base) + 7)))),
            bytes32((uint256(claimable.amountIn) << 128) | claimable.amountOut)
        );

        // And: Both read back through ALMCoreViewLogic, with no record to add.
        (uint128 depositIn, uint128 depositOut) =
            coreViewLogic.getClaimableDeposit(address(almCore), vault, controller_);
        (uint128 redeemIn, uint128 redeemOut) = coreViewLogic.getClaimableRedeem(address(almCore), vault, controller_);
        assertEq(depositIn, claimable.amountIn);
        assertEq(depositOut, claimable.amountOut);
        assertEq(redeemIn, claimable.amountOut);
        assertEq(redeemOut, claimable.amountIn);
    }

    function testFuzz_Success_storageSlots_RewardScalars(
        uint128 rewardPerShare,
        uint128 highWater,
        uint128 claimedCumulative,
        uint128 lastRewardBalance,
        uint128 protocolFees,
        uint128 protocolRewardPerSharePaid
    ) public {
        // Given: A core as deployed.

        // When: Writing the accumulator and the reward accounting.
        almCore.setRewardAccounting(rewardPerShare, highWater, claimedCumulative, lastRewardBalance);
        almCore.setFeesOwed(0, 0, protocolFees);
        almCore.setProtocolRewardSnapshot(protocolRewardPerSharePaid);

        // Then: B + 4 stores the accumulator and its mark, B + 5 the reward accounting.
        assertEq(
            vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 4)),
            bytes32((uint256(highWater) << 128) | rewardPerShare)
        );
        assertEq(
            vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 5)),
            bytes32((uint256(lastRewardBalance) << 128) | claimedCumulative)
        );

        // And: B + 6 stores the protocol's reward token fee and its paid mark.
        assertEq(
            vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 6)),
            bytes32((uint256(protocolRewardPerSharePaid) << 128) | protocolFees)
        );
    }

    function testFuzz_Success_storageSlots_Accounts(address account, uint128 rewardPerSharePaid, uint128 rewardOwed)
        public
    {
        // Given: A core as deployed.

        // When: Writing an account's snapshot and its reward owed.
        almCore.setRewardSnapshot(account, rewardPerSharePaid);
        almCore.setPendingReward(account, rewardOwed);

        // Then: Both share the account's record word, in the mapping at B + 8.
        assertEq(
            vm.load(address(almCore), keccak256(abi.encode(account, bytes32(uint256(STATE_SLOT) + 8)))),
            bytes32((uint256(rewardOwed) << 128) | rewardPerSharePaid)
        );
    }

    function testFuzz_Success_storageSlots_Metadata(string memory name_, string memory symbol_) public {
        // Given: A core as deployed.

        // When: Writing the name and the symbol.
        almCore.setMetadata(name_, symbol_);

        // Then: B + 11 stores the name and B + 12 the symbol, as Solidity strings.
        for (uint256 i; i < 2; ++i) {
            bytes memory raw = bytes(i == 0 ? name_ : symbol_);
            bytes32 slot = bytes32(uint256(STATE_SLOT) + 11 + i);
            if (raw.length < 32) {
                assertEq(vm.load(address(almCore), slot), bytes32(raw) | bytes32(raw.length * 2));
            } else {
                assertEq(vm.load(address(almCore), slot), bytes32(raw.length * 2 + 1));
                uint256 dataSlot = uint256(keccak256(abi.encode(slot)));
                for (uint256 j; j * 32 < raw.length; ++j) {
                    bytes memory chunk = new bytes(32);
                    for (uint256 byteIndex; byteIndex < 32 && j * 32 + byteIndex < raw.length; ++byteIndex) {
                        chunk[byteIndex] = raw[j * 32 + byteIndex];
                    }
                    assertEq(vm.load(address(almCore), bytes32(dataSlot + j)), bytes32(chunk));
                }
            }
        }
    }

    function testFuzz_Success_storageSlots_PendingShares(address account, uint128 claimableShares, uint128 shares)
        public
    {
        // Given: The claimable shares of an account.
        almCore.setClaimableShares(account, claimableShares);

        // When: Writing its pending shares.
        almCore.setPendingShares(account, shares);

        // Then: They sit above the claimable shares in the share record, at B + 13.
        bytes32 record = keccak256(abi.encode(account, bytes32(uint256(STATE_SLOT) + 13)));
        assertEq(vm.load(address(almCore), record), bytes32((uint256(shares) << 128) | claimableShares));
    }

    function testFuzz_Success_storageSlots_IsOperator(address controller_, address operator, bool approved) public {
        // Given: A core as deployed.

        // When: A vault writes an operator approval.
        vm.prank(asyncVault0);
        almCore.setOperator(controller_, operator, approved);

        // Then: It sits in the nested mapping at B + 14.
        bytes32 slot =
            keccak256(abi.encode(operator, keccak256(abi.encode(controller_, bytes32(uint256(STATE_SLOT) + 14)))));
        assertEq(vm.load(address(almCore), slot), bytes32(uint256(approved ? 1 : 0)));
    }

    function testFuzz_Success_storageSlots_IsExempt(address account, bool exempt) public {
        // Given: A core as deployed.

        // When: The factory writes an exemption.
        vm.prank(factory);
        almCore.setCapExempt(account, exempt);

        // Then: It sits in the mapping at B + 15.
        bytes32 slot = keccak256(abi.encode(account, bytes32(uint256(STATE_SLOT) + 15)));
        assertEq(vm.load(address(almCore), slot), bytes32(uint256(exempt ? 1 : 0)));
    }

    function testFuzz_Success_storageSlots_ExchangeRate(uint256 supplyPerValueX128, uint160 sqrtPriceX96) public {
        // Given: A core as deployed.

        // When: Writing the exchange rate.
        almCore.setLastExchangeRate(supplyPerValueX128, sqrtPriceX96);

        // Then: B + 9 stores the supply per value and B + 10 the price.
        assertEq(vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 9)), bytes32(supplyPerValueX128));
        assertEq(vm.load(address(almCore), bytes32(uint256(STATE_SLOT) + 10)), bytes32(uint256(sqrtPriceX96)));
    }
}
