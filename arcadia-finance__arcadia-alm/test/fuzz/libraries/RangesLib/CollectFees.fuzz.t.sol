/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "collectFees" of library "RangesLib".
 */
// forge-lint: disable-next-item(calls-loop, uninitialized-local, unsafe-typecast)
contract CollectFees_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_collectFees_CollectsEveryPosition(
        PoolState memory poolState,
        RangeState memory range,
        uint256 amountIn,
        uint16 feeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: Two ranges around the price, real shares of the room, that earned fees.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        pushRangeOf(range);
        RangeState memory neighbour = RangeState({
            index: 0,
            tickLower: range.tickLower - poolState.tickSpacing,
            tickUpper: range.tickUpper,
            liquidity: range.liquidity,
            liquidityStaked: 0,
            unstakedTokenId: 0,
            stakedTokenId: 0
        });
        pushRangeOf(neighbour);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // And: A protocol share of every collection.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        rangesLib.setProtocolSwapFeeBps(feeBps);

        // And: Each range's fees from fee growth.
        (uint256 first0,) = positionFees(pool, rangesLib.getRange(0).unstakedTokenId);
        (uint256 second0,) = positionFees(pool, rangesLib.getRange(1).unstakedTokenId);

        // When: Collecting every unstaked leg at once.
        (TokenDelta fees,,) = rangesLib.collectFees(sqrtPriceX96(pool));

        // Then: Both ranges' fees are returned before the protocol share.
        assertEq(int256(fees.amount0()), int256(first0 + second0));

        // And: No protocol fee accrues.
        assertEq(rangesLib.getPoolTokens().protocolFees.amount0, 0);

        // And: Neither range has anything left to collect.
        (fees,,) = rangesLib.collectFees(sqrtPriceX96(pool));
        assertEq(int256(fees.amount0()), 0);
    }

    function testFuzz_Success_collectFees_NoRanges(PoolState memory poolState, uint160 sqrtPriceX96) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: No ranges, and a price anywhere the pool can reach.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Collecting every unstaked side.
        (TokenDelta fees, uint256 amount0, uint256 amount1) = rangesLib.collectFees(sqrtPriceX96);

        // Then: Nothing is collected and there is no principal.
        assertEq(int256(fees.amount0()), 0);
        assertEq(int256(fees.amount1()), 0);
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    function testFuzz_Success_collectFees_SkipsARangeHoldingNoLiquidity(
        PoolState memory poolState,
        RangeState memory held,
        uint160 sqrtPriceX96
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range that holds no liquidity on either side.
        givenValidRangeState(held, poolState, false);
        (held.liquidity, held.liquidityStaked) = (0, 0);
        pushRangeOf(held);

        // And: A price anywhere the pool can reach.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Collecting every unstaked side.
        (TokenDelta fees, uint256 amount0, uint256 amount1) = rangesLib.collectFees(sqrtPriceX96);

        // Then: Nothing is collected, no protocol fee accrues, and no principal is added.
        assertEq(int256(fees.amount0()), 0);
        assertEq(int256(fees.amount1()), 0);
        assertEq(rangesLib.getPoolTokens().protocolFees.amount0, 0);
        assertEq(rangesLib.getPoolTokens().protocolFees.amount1, 0);
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    function testFuzz_Success_collectFees_SkipsARangeWithNoUnstakedLiquidity(
        PoolState memory poolState,
        uint160 sqrtPriceX96,
        RangeState memory held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range with nothing on its unstaked side, liquidity on its staked side.
        givenValidRangeState(held, poolState, false);
        held.liquidity = 0;
        held.liquidityStaked = uint128(
            bound(
                held.liquidityStaked,
                1,
                liquidityCeiling(held.tickLower, held.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(held);
        (int24 lower, int24 upper, uint128 staked) = (held.tickLower, held.tickUpper, held.liquidityStaked);

        // And: A price anywhere the pool can reach.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Collecting every unstaked side.
        (TokenDelta fees, uint256 amount0, uint256 amount1) = rangesLib.collectFees(sqrtPriceX96);

        // Then: Nothing is collected and no protocol fee accrues.
        assertEq(int256(fees.amount0()), 0);
        assertEq(int256(fees.amount1()), 0);
        assertEq(rangesLib.getPoolTokens().protocolFees.amount0, 0);
        assertEq(rangesLib.getPoolTokens().protocolFees.amount1, 0);

        // And: The staked side's principal is counted, rounded down.
        (uint256 expected0, uint256 expected1) = amountsRoundedDown(sqrtPriceX96, lower, upper, staked);
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
    }

    function testFuzz_Success_collectFees_SumsBothSidesOfARange(
        PoolState memory poolState,
        RangeState memory range,
        uint160 sqrtPriceX96
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range holding liquidity on both sides.
        givenValidRangeState(range, poolState, false);
        pushRangeOf(range);

        // And: A price anywhere the pool can reach.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Collecting every unstaked side.
        (, uint256 amount0, uint256 amount1) = rangesLib.collectFees(sqrtPriceX96);

        // Then: The principal is the two sides taken together, rounded down.
        (uint256 expected0, uint256 expected1) = amountsRoundedDown(
            sqrtPriceX96, range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
    }

    function testFuzz_Success_collectFees_SumsThePrincipalOfEveryRange(
        PoolState memory poolState,
        uint160 sqrtPriceX96,
        RangeState memory first,
        RangeState memory second
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: Two staked ranges with drained unstaked sides.
        givenValidRangeState(first, poolState, false);
        first.liquidity = 0;
        first.liquidityStaked = uint128(
            bound(
                first.liquidityStaked,
                1,
                liquidityCeiling(first.tickLower, first.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(first);
        givenValidRangeState(second, poolState, false);
        second.liquidity = 0;
        second.liquidityStaked = uint128(
            bound(
                second.liquidityStaked,
                1,
                liquidityCeiling(second.tickLower, second.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(second);

        // And: A price anywhere the pool can reach.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));

        // When: Collecting every unstaked side.
        (, uint256 amount0, uint256 amount1) = rangesLib.collectFees(sqrtPriceX96);

        // Then: The principal is both ranges' amounts, rounded down.
        (uint256 first0, uint256 first1) =
            amountsRoundedDown(sqrtPriceX96, first.tickLower, first.tickUpper, first.liquidityStaked);
        (uint256 second0, uint256 second1) =
            amountsRoundedDown(sqrtPriceX96, second.tickLower, second.tickUpper, second.liquidityStaked);
        assertEq(amount0, first0 + second0);
        assertEq(amount1, first1 + second1);
    }
}
