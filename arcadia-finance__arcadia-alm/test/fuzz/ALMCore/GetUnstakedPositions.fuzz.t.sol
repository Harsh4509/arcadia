/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { Plan } from "../../utils/Plan.sol";
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";

/**
 * @notice Fuzz tests for the function "getUnstakedPositions" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unused-return)
contract GetUnstakedPositions_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getUnstakedPositions_Reentrancy(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The core's lock is held.
        almCore.lock_();

        // When: Calling getUnstakedPositions().
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        almCore.getUnstakedPositions();
    }

    function testFuzz_Success_getUnstakedPositions_FeeGrowthNetOfTheProtocolShare(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        uint16 feeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price without a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Swap fees the range earned, under a protocol share.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // And: What the position earned from the pool's fee growth since its last update.
        (uint256 gross0, uint256 gross1) = positionFees(pool, almCore.getRange(0).unstakedTokenId);

        // When: Reading the uncollected fees.
        (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();

        // Then: They are what the position earned, net of the protocol share.
        assertEq(fees0, gross0 - gross0 * feeBps / almCore.BPS_DENOMINATOR_());
        assertEq(fees1, gross1 - gross1 * feeBps / almCore.BPS_DENOMINATOR_());
    }

    function testFuzz_Success_getUnstakedPositions_GrowthOnTheDonatedLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        uint256 donation,
        uint16 feeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price without a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A third party added liquidity to the range's position.
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));

        // And: Swap fees the position then earned, under a protocol share.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );
        (uint256 gross0, uint256 gross1) = positionFees(pool, range.unstakedTokenId);
        assertGt(gross0 + gross1, 0);

        // When: Reading the uncollected fees.
        (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();

        // Then: They are the whole position's fees, net of the protocol share.
        assertEq(fees0, gross0 - gross0 * feeBps / almCore.BPS_DENOMINATOR_());
        assertEq(fees1, gross1 - gross1 * feeBps / almCore.BPS_DENOMINATOR_());
    }

    function testFuzz_Success_getUnstakedPositions_UnchangedByAThirdPartyPoke(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 donation,
        uint256 poke,
        uint256 amountIn,
        uint16 feeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price without a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A third party added liquidity to the range's position.
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));

        // And: Swap fees the position then earned, under a protocol share.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );
        (uint256 before0, uint256 before1,) = almCore.getUnstakedPositions();

        // When: A third party pokes the position by adding liquidity to it.
        donateToRange(range, uint128(bound(poke, 1, range.liquidity)));

        // Then: The uncollected fees did not move.
        (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
        assertEq(fees0, before0);
        assertEq(fees1, before1);
    }

    function testFuzz_Success_getUnstakedPositions_ReturnsEveryUnstakedSidesLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second,
        uint256 donation
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding two ranges, the second's unstaked side drained.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(second, poolState, false);
        setRangeState(second);
        runPlan(Plan.init().decreaseLiquidity(second.index, second.unstakedTokenId, Sentinels.RANGE_LIQUIDITY, 0, 0));

        // And: A third party added liquidity to the first range's position.
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));

        // When: Reading the uncollected fees.
        (,, uint128[] memory positionLiquidities) = almCore.getUnstakedPositions();

        // Then: Each unstaked side's liquidity is the position's.
        assertEq(positionLiquidities.length, 2);
        assertEq(positionLiquidities[0], positionLiquidity(range.unstakedTokenId));
        assertGt(positionLiquidities[0], range.liquidity);
        assertEq(positionLiquidities[1], 0);
    }

    function testFuzz_Success_getUnstakedPositions_NoRangesIsZero(
        PoolState memory poolState,
        CoreState memory coreState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a buffer and no ranges.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, 0, 0, 0);
        setCoreState(coreState);

        // When: Reading the uncollected fees.
        (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();

        // Then: There are none.
        assertEq(fees0, 0);
        assertEq(fees1, 0);
    }
}
