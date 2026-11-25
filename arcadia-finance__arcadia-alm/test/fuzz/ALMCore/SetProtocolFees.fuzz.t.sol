/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { ILeafVoter } from "../../utils/fixtures/metadex/interfaces/ILeafVoter.sol";
import { IMetadexCLGauge } from "../../../src/interfaces/IMetadexCLGauge.sol";
import { ISwapRouter } from "../../utils/fixtures/metadex/interfaces/ISwapRouter.sol";

/**
 * @notice Fuzz tests for the function "setProtocolFees" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast)
contract SetProtocolFees_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error Unreadable();

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setProtocolFees_Unauthorized(
        PoolState memory poolState,
        address caller,
        uint16 protocolEmissionFeeBps,
        uint16 protocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The caller is not the factory.
        vm.assume(caller != factory);

        // When: Calling setProtocolFees().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_InvalidFee_Emission(
        PoolState memory poolState,
        uint16 protocolEmissionFeeBps,
        uint16 protocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The emission fee exceeds the ceiling.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, almCore.MAX_FEE_BPS_() + 1, type(uint16).max));
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_()));

        // And: The factory calls.

        // When: Calling setProtocolFees().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidFee.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_InvalidFee_Both(
        PoolState memory poolState,
        uint16 protocolEmissionFeeBps,
        uint16 protocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Both fees exceed the ceiling.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, almCore.MAX_FEE_BPS_() + 1, type(uint16).max));
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, almCore.MAX_FEE_BPS_() + 1, type(uint16).max));

        // When: The factory calls setProtocolFees().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidFee.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_InvalidFee_Swap(
        PoolState memory poolState,
        uint16 protocolEmissionFeeBps,
        uint16 protocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The swap fee exceeds the ceiling.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 0, almCore.MAX_FEE_BPS_()));
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, almCore.MAX_FEE_BPS_() + 1, type(uint16).max));

        // And: The factory calls.

        // When: Calling setProtocolFees().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidFee.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, newFeeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_InvalidRecipient(
        PoolState memory poolState,
        uint16 protocolEmissionFeeBps,
        uint16 protocolSwapFeeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Both fees are within the ceiling and the recipient is the zero address.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 0, almCore.MAX_FEE_BPS_()));
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_()));

        // And: The factory calls.

        // When: Calling setProtocolFees().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(BaseCore.InvalidRecipient.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, address(0));
    }

    function testFuzz_Revert_setProtocolFees_InvalidRecipient_Core(
        PoolState memory poolState,
        uint16 protocolEmissionFeeBps,
        uint16 protocolSwapFeeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Both fees are within the ceiling and the recipient is the core itself.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 0, almCore.MAX_FEE_BPS_()));
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_()));

        // And: The factory calls.

        // When: Calling setProtocolFees().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(BaseCore.InvalidRecipient.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, address(almCore));
    }

    function testFuzz_Revert_setProtocolFees_GaugeUnreadable(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 protocolEmissionFeeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range whose staked leg is past its penalty window.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A gauge that cannot report what the core earned.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 1, almCore.MAX_FEE_BPS_()));
        vm.mockCallRevert(
            address(gauge),
            abi.encodeWithSelector(IMetadexCLGauge.earned.selector, address(almCore)),
            abi.encodeWithSelector(Unreadable.selector)
        );

        // And: The factory calls.

        // When: Raising the emission fee.
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(Unreadable.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, 0, users.feeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_RewardsPending_PartialPenalty(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 protocolEmissionFeeBps,
        uint256 penaltyRate,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee yet, so any raise is a raise.
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(0, swapFeeBps, users.feeRecipient);

        // And: A partial penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS - 1));

        // And: A seeded vault with a staked range around the price, inside its window.
        givenValidRangeState(range, poolState, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot)) * tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));

        // And: The factory calls.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 1, almCore.MAX_FEE_BPS_()));

        // When: Raising the emission fee.
        // Then: It reverts on the visible part the window keeps at the gauge.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.RewardsPending.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, 0, users.feeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_RewardsPending_FullPenalty(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 protocolEmissionFeeBps,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee yet, so any raise is a raise.
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(0, swapFeeBps, users.feeRecipient);

        // And: A full penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A seeded vault with a staked range around the price, inside its window.
        givenValidRangeState(range, poolState, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot)) * tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        accrueForBlocks(pool, gauge, bound(blocks, 1, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        // And: The factory calls.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 1, almCore.MAX_FEE_BPS_()));

        // When: Raising the emission fee.
        // Then: It reverts on the emissions the window hides.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.RewardsPending.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, 0, users.feeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_RewardsPending_WindowOpenedAfterTheStake(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 protocolEmissionFeeBps,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee yet, so any raise is a raise.
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(0, swapFeeBps, users.feeRecipient);

        // And: A seeded vault with a range around the price staked under no penalty.
        setPenaltyConfig(0, 0);
        givenValidRangeState(range, poolState, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot)) * tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        accrueForBlocks(pool, gauge, bound(blocks, 1, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));

        // And: The gauge now applies a penalty over a window the stake is still inside.
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));

        // And: The factory calls.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 1, almCore.MAX_FEE_BPS_()));

        // When: Raising the emission fee.
        // Then: It reverts on the staked range the window keeps at the gauge.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.RewardsPending.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, 0, users.feeRecipient);
    }

    function testFuzz_Revert_setProtocolFees_ChainNotActiveOrSunset(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 protocolEmissionFeeBps,
        uint256 blocks,
        uint256 emissions,
        uint256 pick
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee yet, so any raise is a raise.
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(0, swapFeeBps, users.feeRecipient);

        // And: A seeded vault with a staked range around the price, outside its window.
        givenValidRangeState(range, poolState, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot)) * tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        accrueForBlocks(pool, gauge, bound(blocks, 1, type(uint32).max), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // And: A chain that is paused or suspended.
        setNotMintableStatus(pick);

        // And: The factory calls.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 1, almCore.MAX_FEE_BPS_()));

        // When: Raising the emission fee.
        // Then: The gauge's claim reverts on the chain status.
        vm.prank(factory);
        vm.expectRevert(ILeafVoter.ChainNotActiveOrSunset.selector);
        almCore.setProtocolFees(protocolEmissionFeeBps, 0, users.feeRecipient);
    }

    function testFuzz_Success_setProtocolFees_RaiseAfterEarnedIsDrained(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 protocolEmissionFeeBps,
        uint256 earned
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with no staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding the range, its seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 floor = almCore.DEAD_SHARES_() + 1;
        uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
        coreState.supply = bound(
            coreState.supply,
            floor,
            FixedPointMathLib.max(FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT), floor)
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: An earned amount that credits the holder, checkpointed.
        uint256 least = FixedPointMathLib.fullMulDivUp(
            FixedPointMathLib.fullMulDivUp(
                FixedPointMathLib.divUp(1e18, almCore.balanceOf(users.steward)), coreState.supply, 1e18
            ),
            almCore.BPS_DENOMINATOR_(),
            almCore.BPS_DENOMINATOR_() - almCore.protocolEmissionFeeBps_()
        );
        earned = bound(
            earned,
            least,
            FixedPointMathLib.max(
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT, FixedPointMathLib.fullMulDiv(coreState.supply, type(uint128).max, 1e18)
                ),
                least
            )
        );
        mockEarned(gauge, address(almCore), earned);
        almCore.checkpoint_();
        uint256 pendingBefore = almCore.getPendingReward(users.steward)
            + FixedPointMathLib.fullMulDiv(
                almCore.balanceOf(users.steward),
                almCore.rewardPerShare_() - almCore.getRewardSnapshot(users.steward),
                1e18
            );
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 1, almCore.MAX_FEE_BPS_()));
        vm.mockCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.claimEmissions.selector), "");

        uint256 lastRewardBalance = almCore.getLastRewardBalance();
        uint256 claimedCumulative = almCore.getClaimedCumulative();
        uint256 received = earned - lastRewardBalance;
        uint256 fee = received * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();

        // When: The earned amount is delivered and the fee is then raised.
        deal(almCore.REWARD_TOKEN_(), address(almCore), earned);
        mockEarned(gauge, address(almCore), 0);
        vm.prank(factory);
        almCore.setProtocolFees(protocolEmissionFeeBps, 0, users.feeRecipient);

        // Then: The delivery is measured and claimed at the old fee.
        assertEq(almCore.getLastRewardBalance(), lastRewardBalance + received);
        assertEq(almCore.getClaimedCumulative(), claimedCumulative + received - fee);

        // And: The credit taken at the old fee is still payable in full.
        assertEq(almCore.protocolEmissionFeeBps_(), protocolEmissionFeeBps);
        assertEq(almCore.getRewardOwed(users.steward), pendingBefore);
        assertEq(almCore.claimEmissions(users.steward), pendingBefore);
    }

    function testFuzz_Success_setProtocolFees(
        PoolState memory poolState,
        uint16 protocolEmissionFeeBps,
        uint16 protocolSwapFeeBps,
        address newFeeRecipient
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Both fees are within the ceiling and the recipient is set.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 0, almCore.MAX_FEE_BPS_()));
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.assume(newFeeRecipient != address(0));
        vm.assume(newFeeRecipient != address(almCore));

        // And: The factory calls.
        vm.prank(factory);

        // When: Calling setProtocolFees().
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.ProtocolFeesSet(protocolEmissionFeeBps, protocolSwapFeeBps, newFeeRecipient);
        almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, newFeeRecipient);

        // Then: Both fees and the recipient are updated.
        assertEq(almCore.protocolEmissionFeeBps_(), protocolEmissionFeeBps);
        assertEq(almCore.protocolSwapFeeBps_(), protocolSwapFeeBps);
        assertEq(almCore.feeRecipient_(), newFeeRecipient);
    }

    function testFuzz_Success_setProtocolFees_AtTheCeiling(PoolState memory poolState, address newFeeRecipient) public {
        // Given: A pool with depth at a fuzzed price, and a recipient.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(newFeeRecipient != address(0));
        vm.assume(newFeeRecipient != address(almCore));

        // When: The factory sets both fees at the ceiling.
        uint16 ceiling = uint16(almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(ceiling, ceiling, newFeeRecipient);

        // Then: Both fees are the ceiling.
        assertEq(almCore.protocolEmissionFeeBps_(), almCore.MAX_FEE_BPS_());
        assertEq(almCore.protocolSwapFeeBps_(), almCore.MAX_FEE_BPS_());
    }

    function testFuzz_Success_setProtocolFees_RaiseAfterTheWindowCloses(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 protocolEmissionFeeBps,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: No emission fee yet, so any raise is a raise.
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(0, swapFeeBps, users.feeRecipient);

        // And: A full penalty over a fuzzed window.
        minStakeBlocks = bound(minStakeBlocks, 2, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A seeded vault with a staked range around the price, inside its window.
        givenValidRangeState(range, poolState, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot)) * tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        accrueForBlocks(pool, gauge, bound(blocks, 1, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));

        // And: The window has closed.
        closePenaltyWindow(gauge);

        // And: The factory calls.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 1, almCore.MAX_FEE_BPS_()));

        // When: Raising the emission fee.
        vm.prank(factory);
        almCore.setProtocolFees(protocolEmissionFeeBps, 0, users.feeRecipient);

        // Then: Nothing is hidden or earned at the gauge any more.
        assertEq(almCore.getPreCredited(), 0);
        assertEq(gauge.earned(address(almCore), almCore.stakedTokenIds()), 0);

        // And: The new fee is in force.
        assertEq(almCore.protocolEmissionFeeBps_(), protocolEmissionFeeBps);
    }

    function testFuzz_Success_setProtocolFees_SwapFeeChangeCollectsAtTheOldFee(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        uint16 oldFeeBps,
        uint16 newFeeBps,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A protocol share of every collection.
        oldFeeBps = uint16(bound(oldFeeBps, 0, almCore.MAX_FEE_BPS_()));
        uint16 emissionFeeBps = almCore.protocolEmissionFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(emissionFeeBps, oldFeeBps, users.feeRecipient);

        // And: A range around spot with no staked leg.
        givenValidRangeState(range, poolState, false, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot)) * tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;
        range.liquidity = uint128(
            bound(
                range.liquidity,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding the range, which has earned swap fees.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        amountIn = feeEarningTrade(pool, range.liquidity, amountIn, zeroForOne);
        (zeroForOne ? token0 : token1).mint(users.liquidityProvider, amountIn);
        vm.startPrank(users.liquidityProvider);
        (zeroForOne ? token0 : token1).approve(address(SWAP_ROUTER), amountIn);
        SWAP_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: zeroForOne ? address(token0) : address(token1),
                tokenOut: zeroForOne ? address(token1) : address(token0),
                tickSpacing: poolState.tickSpacing,
                recipient: users.liquidityProvider,
                deadline: vm.getBlockTimestamp(),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: priceLimit(zeroForOne)
            })
        );
        vm.stopPrank();
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        (uint256 gross0, uint256 gross1) = positionFees(pool, range.unstakedTokenId);

        // And: The factory calls with a different swap fee.
        newFeeBps = uint16(bound(newFeeBps, 0, almCore.MAX_FEE_BPS_() - 1));
        if (newFeeBps >= oldFeeBps) ++newFeeBps;

        // When: Changing the swap fee.
        vm.prank(factory);
        almCore.setProtocolFees(emissionFeeBps, newFeeBps, users.feeRecipient);

        // Then: The earned fees were collected and split at the old fee.
        uint256 fee0 = gross0 * oldFeeBps / almCore.BPS_DENOMINATOR_();
        uint256 fee1 = gross1 * oldFeeBps / almCore.BPS_DENOMINATOR_();
        assertEq(almCore.getProtocolFees0(), fee0);
        assertEq(almCore.getProtocolFees1(), fee1);
        assertEq(almCore.bufferAmount0(), buffer0Before + gross0 - fee0);
        assertEq(almCore.bufferAmount1(), buffer1Before + gross1 - fee1);

        // And: The new fee is in force.
        assertEq(almCore.protocolSwapFeeBps_(), newFeeBps);
    }

    function testFuzz_Success_setProtocolFees_RaisesOverAForeignStake(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a staked range around the price.
        givenValidRangeState(range, poolState, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot)) * tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A stranger stakes their own position naming the vault as its factory.
        (uint256 foreign,) = mintPosition(
            pool, users.liquidityProvider, range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY
        );
        vm.startPrank(users.liquidityProvider);
        POSITION_MANAGER.approve(address(gauge), foreign);
        gauge.depositFor(foreign, address(almCore));
        vm.stopPrank();

        assertTrue(gauge.stakedContains(address(almCore), foreign));
        vm.roll(vm.getBlockNumber() + 100);

        // And: Emissions the stranger's position accrues, which the vault never claims.
        addEmissionsToGaugeCL(pool, gauge, bound(emissions, 2, Constants.MAX_EMISSIONS));

        // When: The factory raises the emission fee.
        uint16 raised = uint16(almCore.MAX_FEE_BPS_());
        vm.prank(factory);
        almCore.setProtocolFees(raised, 0, address(this));

        // Then: It goes through.
        assertEq(almCore.protocolEmissionFeeBps_(), raised);
        assertEq(almCore.feeRecipient_(), address(this));
    }

    function testFuzz_Success_setProtocolFees_RaiseClaimsTheEarnedAtTheOldFeeWhileTheChainMints(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint16 protocolEmissionFeeBps,
        uint16 newProtocolEmissionFeeBps,
        uint256 blocks,
        uint256 emissions,
        uint256 pick
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee below the ceiling.
        protocolEmissionFeeBps = uint16(bound(protocolEmissionFeeBps, 0, almCore.MAX_FEE_BPS_() - 1));
        uint16 swapFeeBps = almCore.protocolSwapFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(protocolEmissionFeeBps, swapFeeBps, users.feeRecipient);

        // And: A seeded vault with a staked range around the price, outside its window.
        givenValidRangeState(range, poolState, false);
        {
            int24 tickSpacing = poolState.tickSpacing;
            int24 band = bandTick(tickSpacing) / tickSpacing;
            int24 spot = poolState.tickCurrent / tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
            range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot)) * tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 1, band - 1)) * tickSpacing;
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
            range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        accrueForBlocks(pool, gauge, bound(blocks, 1, type(uint32).max), bound(emissions, 1, Constants.MAX_EMISSIONS));

        // And: A chain that is active or sunset.
        setMintableStatus(pick);
        uint256[] memory tokenIds = almCore.stakedTokenIds();
        uint256 earned = gauge.earned(address(almCore), tokenIds);
        uint256 fee = earned * protocolEmissionFeeBps / almCore.BPS_DENOMINATOR_();
        uint256 lastRewardBalance = almCore.getLastRewardBalance();
        uint256 claimedCumulative = almCore.getClaimedCumulative();
        uint256 protocolFees = almCore.getProtocolFeesReward();

        // And: The factory calls.
        newProtocolEmissionFeeBps =
            uint16(bound(newProtocolEmissionFeeBps, uint256(protocolEmissionFeeBps) + 1, almCore.MAX_FEE_BPS_()));

        // When: Raising the emission fee.
        vm.prank(factory);
        almCore.setProtocolFees(newProtocolEmissionFeeBps, 0, users.feeRecipient);

        // Then: The core received everything the gauge owed it.
        assertEq(gauge.earned(address(almCore), tokenIds), 0);
        assertEq(almCore.getLastRewardBalance(), lastRewardBalance + earned);

        // And: It was split at the old fee before the raise.
        assertEq(almCore.getClaimedCumulative(), claimedCumulative + earned - fee);
        assertEq(almCore.getProtocolFeesReward(), protocolFees + fee);
        assertEq(almCore.protocolEmissionFeeBps_(), newProtocolEmissionFeeBps);
    }
}
