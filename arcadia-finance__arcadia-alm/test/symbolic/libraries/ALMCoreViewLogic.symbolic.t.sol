/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import {
    Claimable,
    Config,
    Epoch,
    Queue,
    Record,
    RewardAccount,
    ShareAccount
} from "../../../src/core/types/State.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { STATE_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TokenAmounts } from "../../../src/core/types/TokenDelta.sol";

/**
 * @notice Symbolic tests for the storage word decoders of library "ALMCoreViewLogic".
 */
contract Layout_ALMCoreViewLogic_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                 STORAGE
    ////////////////////////////////////////////////////////////// */

    Claimable internal claimable;
    Config internal config;
    Epoch internal epoch;
    Queue internal queue;
    Record internal record;
    RewardAccount internal rewardAccount;
    ShareAccount internal shareAccount;
    TokenAmounts internal tokenAmounts;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_getConfig_ReadsEveryFieldOfTheCompilerPacking(Config memory stored) public {
        // Given: Any config, stored by the compiler and served as the config words.
        config = stored;
        uint256 slot;
        assembly ("memory-safe") {
            slot := config.slot
        }
        bytes32[] memory words = new bytes32[](4);
        words[0] = vm.load(address(this), bytes32(slot));
        words[1] = vm.load(address(this), bytes32(slot + 1));
        words[2] = vm.load(address(this), bytes32(slot + 2));
        words[3] = vm.load(address(this), bytes32(slot + 3));
        vm.mockCall(
            address(this),
            abi.encodeWithSignature("extsload(bytes32,uint256)", STATE_SLOT, uint256(4)),
            abi.encode(words)
        );

        // When: Reading the config.
        Config memory read = ALMCoreViewLogic.getConfig(IALMCore(address(this)));

        // Then: Every field comes back as it was stored.
        assertEq(read.totalCap, stored.totalCap);
        assertEq(read.perUserCap, stored.perUserCap);
        assertEq(read.paused, stored.paused);
        assertEq(read.protocolEmissionFeeBps, stored.protocolEmissionFeeBps);
        assertEq(read.protocolSwapFeeBps, stored.protocolSwapFeeBps);
        assertEq(read.twapWindow, stored.twapWindow);
        assertEq(read.maxSpotFromTwap, stored.maxSpotFromTwap);
        assertEq(read.maxSpotFromTrusted, stored.maxSpotFromTrusted);
        assertEq(read.windowEnd, stored.windowEnd);
        assertEq(read.rewardPoolToken, stored.rewardPoolToken);
        assertEq(read.maxTwapFromTrusted, stored.maxTwapFromTrusted);
        assertEq(read.maxShortfallBps, stored.maxShortfallBps);
        assertEq(read.maxSwapCostBps, stored.maxSwapCostBps);
        assertEq(read.minPlanInterval, stored.minPlanInterval);
        assertEq(read.rangeCap, stored.rangeCap);
        assertEq(read.lastPlanAt, stored.lastPlanAt);
        assertEq(read.arbBlockNumber, stored.arbBlockNumber);
        assertEq(read.feeRecipient, stored.feeRecipient);
    }

    function prove_getLastClearedDepositEpoch_ReadsTheCompilerPacking(
        address vault,
        uint32 pendingEpoch,
        uint32 lastClearedEpoch
    ) public {
        // Given: Any epoch ids, stored by the compiler and served as the queue word.
        (queue.pendingEpoch, queue.lastClearedEpoch) = (pendingEpoch, lastClearedEpoch);
        uint256 slot;
        assembly ("memory-safe") {
            slot := queue.slot
        }
        vm.mockCall(
            address(this),
            abi.encodeWithSignature("extsload(bytes32)"),
            abi.encode(vm.load(address(this), bytes32(slot)))
        );

        // When: Reading the pending and the last cleared epoch.
        // Then: Both come back as they were stored.
        assertEq(ALMCoreViewLogic.getPendingDepositEpoch(IALMCore(address(this)), vault), pendingEpoch);
        assertEq(ALMCoreViewLogic.getLastClearedDepositEpoch(IALMCore(address(this)), vault), lastClearedEpoch);
    }

    function prove_decodeRecord_RoundTripsTheStoredWord(Record memory stored) public {
        // Given: Any record, stored by the compiler.
        record = stored;
        uint256 slot;
        assembly ("memory-safe") {
            slot := record.slot
        }

        // When: Decoding its storage word.
        (uint32 epoch_, uint128 amountIn, uint96 pendingShares) =
            ALMCoreViewLogic.decodeRecord(vm.load(address(this), bytes32(slot)));

        // Then: Every field comes back as it was stored.
        assertEq(epoch_, stored.epoch);
        assertEq(amountIn, stored.amountIn);
        assertEq(pendingShares, stored.pendingShares);
    }

    function prove_decodeWord_RoundTripsEveryPairOfHalves(
        Epoch memory storedEpoch,
        Claimable memory storedClaimable,
        TokenAmounts memory storedTokenAmounts,
        RewardAccount memory storedRewardAccount,
        ShareAccount memory storedShareAccount
    ) public {
        // Given: Any struct of two uint128 halves, stored by the compiler.
        (epoch, claimable, tokenAmounts) = (storedEpoch, storedClaimable, storedTokenAmounts);
        (rewardAccount, shareAccount) = (storedRewardAccount, storedShareAccount);
        bytes32[] memory slots = new bytes32[](5);
        assembly ("memory-safe") {
            mstore(add(slots, 0x20), epoch.slot)
            mstore(add(slots, 0x40), claimable.slot)
            mstore(add(slots, 0x60), tokenAmounts.slot)
            mstore(add(slots, 0x80), rewardAccount.slot)
            mstore(add(slots, 0xa0), shareAccount.slot)
        }

        // When: Decoding each storage word into its struct.
        Epoch memory readEpoch;
        Claimable memory readClaimable;
        TokenAmounts memory readTokenAmounts;
        RewardAccount memory readRewardAccount;
        ShareAccount memory readShareAccount;
        (readEpoch.amountIn, readEpoch.amountOut) = ALMCoreViewLogic.decodeWord(vm.load(address(this), slots[0]));
        (readClaimable.amountIn, readClaimable.amountOut) =
            ALMCoreViewLogic.decodeWord(vm.load(address(this), slots[1]));
        (readTokenAmounts.amount0, readTokenAmounts.amount1) =
            ALMCoreViewLogic.decodeWord(vm.load(address(this), slots[2]));
        (readRewardAccount.rewardPerSharePaid, readRewardAccount.rewardOwed) =
            ALMCoreViewLogic.decodeWord(vm.load(address(this), slots[3]));
        (readShareAccount.claimableShares, readShareAccount.pendingShares) =
            ALMCoreViewLogic.decodeWord(vm.load(address(this), slots[4]));

        // Then: Every field comes back as it was stored.
        assertEq(readEpoch.amountIn, storedEpoch.amountIn);
        assertEq(readEpoch.amountOut, storedEpoch.amountOut);
        assertEq(readClaimable.amountIn, storedClaimable.amountIn);
        assertEq(readClaimable.amountOut, storedClaimable.amountOut);
        assertEq(readTokenAmounts.amount0, storedTokenAmounts.amount0);
        assertEq(readTokenAmounts.amount1, storedTokenAmounts.amount1);
        assertEq(readRewardAccount.rewardPerSharePaid, storedRewardAccount.rewardPerSharePaid);
        assertEq(readRewardAccount.rewardOwed, storedRewardAccount.rewardOwed);
        assertEq(readShareAccount.claimableShares, storedShareAccount.claimableShares);
        assertEq(readShareAccount.pendingShares, storedShareAccount.pendingShares);
    }

    function prove_decodePauseAndDeviation_ReadsTheCompilerPacking(Config memory stored) public {
        // Given: Any config, stored by the compiler.
        config = stored;
        uint256 slot;
        assembly ("memory-safe") {
            slot := config.slot
        }

        // When: Decoding the pause flag and the TWAP band from the pause and fees word.
        (bool paused, uint64 maxSpotFromTwap) =
            ALMCoreViewLogic.decodePauseAndDeviation(uint256(vm.load(address(this), bytes32(slot + 1))));

        // Then: Both come back as they were stored.
        assertEq(paused, stored.paused);
        assertEq(maxSpotFromTwap, stored.maxSpotFromTwap);
    }

    function prove_getTwapWindow_ReadsTheCompilerPacking(Config memory stored) public {
        // Given: Any config, stored by the compiler, served as the pause and fees word.
        config = stored;
        uint256 slot;
        assembly ("memory-safe") {
            slot := config.slot
        }
        vm.mockCall(
            address(this),
            abi.encodeWithSignature(
                "extsload(bytes32)", ALMCoreViewLogic.memberSlot(ALMCoreViewLogic.PAUSE_AND_FEES_OFFSET)
            ),
            abi.encode(vm.load(address(this), bytes32(slot + 1)))
        );

        // When: Reading the TWAP window.
        // Then: It comes back as it was stored.
        assertEq(ALMCoreViewLogic.getTwapWindow(IALMCore(address(this))), stored.twapWindow);
    }

    function prove_getMaxSwapCostBps_ReadsTheCompilerPacking(Config memory stored) public {
        // Given: Any config, stored by the compiler and served as the plan bounds word.
        config = stored;
        uint256 slot;
        assembly ("memory-safe") {
            slot := config.slot
        }
        vm.mockCall(
            address(this),
            abi.encodeWithSignature(
                "extsload(bytes32)", ALMCoreViewLogic.memberSlot(ALMCoreViewLogic.PLAN_BOUNDS_OFFSET)
            ),
            abi.encode(vm.load(address(this), bytes32(slot + 2)))
        );

        // When: Reading the max swap cost.
        // Then: It comes back as it was stored.
        assertEq(ALMCoreViewLogic.getMaxSwapCostBps(IALMCore(address(this))), stored.maxSwapCostBps);
    }
}
