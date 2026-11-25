/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../../utils/Constants.sol";
import { ERC20Mock } from "../../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLib_Fuzz_Test } from "./_SnapshotLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getBurnAmounts" of library "SnapshotLib".
 */
contract GetBurnAmounts_SnapshotLib_Fuzz_Test is SnapshotLib_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getBurnAmounts_CountsTheFeesWhenEveryRangeReleases(
        SnapshotState memory state,
        RangeState memory range,
        uint256 shares
    ) public view {
        // Given: A range around spot in the band, and a burn taking liquidity from it.
        Snapshot memory snapshot = givenValidSnapshot(state, range);
        shares = bound(shares, uint256(state.supply).divUp(snapshot.ranges[0].liquidity), state.supply);

        // When: Calculating the burn's amounts with and without uncollected fees.
        (uint256 amount0, uint256 amount1,) = snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, false);
        (snapshot.fees0, snapshot.fees1) = (0, 0);
        (uint256 base0, uint256 base1,) = snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, false);

        // Then: The fees raise the buffer's share.
        assertEq(
            amount0 - base0,
            (uint256(state.idle0) + state.fees0).fullMulDiv(shares, state.supply)
                - uint256(state.idle0).fullMulDiv(shares, state.supply)
        );
        assertEq(
            amount1 - base1,
            (uint256(state.idle1) + state.fees1).fullMulDiv(shares, state.supply)
                - uint256(state.idle1).fullMulDiv(shares, state.supply)
        );
    }

    function testFuzz_Success_getBurnAmounts_CountsTheFeesWhenARangeKeepsItsLiquidity(
        SnapshotState memory state,
        RangeState memory range,
        uint256 shares
    ) public view {
        // Given: A range around spot, a supply above its liquidity, a burn taking none.
        Snapshot memory snapshot = givenValidSnapshot(state, range);
        snapshot.supply = bound(state.supply, uint256(snapshot.ranges[0].liquidity) + 1, type(uint128).max);
        shares = bound(shares, 1, (snapshot.supply - 1) / snapshot.ranges[0].liquidity);

        // When: Calculating the burn's amounts.
        (uint256 amount0, uint256 amount1,) = snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, false);

        // Then: It releases the shares' part of the buffer and the fees.
        assertEq(amount0, (uint256(state.idle0) + state.fees0) * shares / snapshot.supply);
        assertEq(amount1, (uint256(state.idle1) + state.fees1) * shares / snapshot.supply);
    }

    function testFuzz_Success_getBurnAmounts_TakesTheRangesLiquidityAtThePrice(
        SnapshotState memory state,
        RangeState memory range,
        uint256 shares
    ) public view {
        // Given: A range around a spot price in the band, and any burn.
        Snapshot memory snapshot = givenValidSnapshot(state, range);
        shares = bound(shares, 0, state.supply);

        // When: Calculating the burn's amounts.
        (,, uint256 activeLiquidityDelta) = snapshotLib.getBurnAmounts(snapshot, state.sqrtPriceX96, shares, false);

        // Then: It takes the shares' part of the range's liquidity, rounded down.
        assertEq(activeLiquidityDelta, uint256(snapshot.ranges[0].liquidity).fullMulDiv(shares, state.supply));
    }

    function testFuzz_Success_getBurnAmounts_SpotOnTheLowerTickTradesAsThePool(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault with a range around the price, a burn up to the supply.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 supply = almCore.totalSupply();
        shares = bound(shares, 0, supply);

        // And: Spot parked on the range's lower tick by a downward swap.
        {
            (address tokenIn, address tokenOut, uint256 amountIn) = tradeForTick(pool, range.tickLower);
            ERC20Mock(tokenIn).mint(users.liquidityProvider, 2 * amountIn + 1);
            swapAsActor(
                pool,
                users.liquidityProvider,
                tokenIn,
                tokenOut,
                2 * amountIn + 1,
                TickMath.getSqrtPriceAtTick(range.tickLower)
            );
        }
        assertEq(sqrtPriceX96(pool), TickMath.getSqrtPriceAtTick(range.tickLower));

        // When: Calculating the burn's amounts at spot, for a sale in either direction.
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
        (,, uint256 activeLiquidityDelta) = snapshotLib.getBurnAmounts(snapshot, sqrtPriceX96(pool), shares, zeroForOne);

        // And: The pool makes a small swap in that direction.
        (address swapIn, address swapOut) =
            zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        ERC20Mock(swapIn).mint(users.liquidityProvider, 1000);
        swapAsActor(pool, users.liquidityProvider, swapIn, swapOut, 1000, priceLimit(zeroForOne));

        // Then: The swap trades against the range only when the swap moves up.
        bool trades = pool.liquidity() == uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked;
        assertTrue(trades || pool.liquidity() == poolState.liquidityPool);
        assertEq(trades, !zeroForOne);

        // And: The burn takes the shares' part, rounded down, only from a trading range.
        assertEq(
            activeLiquidityDelta, trades ? (uint256(range.liquidity) + range.liquidityStaked) * shares / supply : 0
        );
    }

    function testFuzz_Success_getBurnAmounts_SpotOnTheUpperTickTradesAsThePool(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault with a range around the price, a burn up to the supply.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 supply = almCore.totalSupply();
        shares = bound(shares, 0, supply);

        // And: Spot parked on the range's upper tick by an upward swap.
        {
            (address tokenIn, address tokenOut, uint256 amountIn) = tradeForTick(pool, range.tickUpper);
            ERC20Mock(tokenIn).mint(users.liquidityProvider, 2 * amountIn + 1);
            swapAsActor(
                pool,
                users.liquidityProvider,
                tokenIn,
                tokenOut,
                2 * amountIn + 1,
                TickMath.getSqrtPriceAtTick(range.tickUpper)
            );
        }
        assertEq(sqrtPriceX96(pool), TickMath.getSqrtPriceAtTick(range.tickUpper));

        // When: Calculating the burn's amounts at spot, for a sale in either direction.
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
        (,, uint256 activeLiquidityDelta) = snapshotLib.getBurnAmounts(snapshot, sqrtPriceX96(pool), shares, zeroForOne);

        // And: The pool makes a small swap in that direction.
        (address swapIn, address swapOut) =
            zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        ERC20Mock(swapIn).mint(users.liquidityProvider, 1000);
        swapAsActor(pool, users.liquidityProvider, swapIn, swapOut, 1000, priceLimit(zeroForOne));

        // Then: The swap trades against the range only when the swap moves down.
        bool trades = pool.liquidity() == uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked;
        assertTrue(trades || pool.liquidity() == poolState.liquidityPool);
        assertEq(trades, zeroForOne);

        // And: The burn takes the shares' part, rounded down, only from a trading range.
        assertEq(
            activeLiquidityDelta, trades ? (uint256(range.liquidity) + range.liquidityStaked) * shares / supply : 0
        );
    }

    function testFuzz_Success_getBurnAmounts_MatchesTheCoresBurn(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory neighbour,
        uint256 amountIn,
        uint16 bps,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault with a range around the price, a real share of the room.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault whose seed holder holds shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);

        // And: A protocol share of the swap fees, and the vault holding the range.
        vm.prank(factory);
        almCore.setProtocolFees(0, uint16(bound(bps, 0, ConfigLib.MAX_FEE_BPS)), users.feeRecipient);
        setRangeState(range);

        // And: A neighbour, and swap fees.
        givenValidRangeState(neighbour, poolState, false);
        setRangeState(neighbour);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // And: A holder's burn that takes liquidity from both ranges.
        uint256 supply = almCore.totalSupply();
        {
            uint256 balance = almCore.balanceOf(users.steward);
            uint256 least = FixedPointMathLib.min(
                positionLiquidity(almCore.getRange(0).unstakedTokenId),
                positionLiquidity(almCore.getRange(1).unstakedTokenId)
            );
            shares = bound(shares, FixedPointMathLib.min(supply.divUp(least), balance), balance);
        }

        // When: Calculating the burn's amounts on the snapshot at spot.
        (uint256 amount0, uint256 amount1,) = snapshotLib.getBurnAmounts(
            snapshotLib.getSnapshot(address(almCore), address(pool), address(this)), sqrtPriceX96(pool), shares, false
        );

        // Then: They equal what a burn through the core releases.
        vm.prank(users.steward);
        (uint256 released0, uint256 released1) = almCore.burn(shares, users.steward, users.steward);
        assertEq(amount0, released0);
        assertEq(amount1, released1);
    }

    function testFuzz_Success_getBurnAmounts_MatchesTheCoresBurnWithARangeUntouched(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory dust,
        uint256 amountIn,
        uint16 bps,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price, a real share of the room.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault whose seed holder holds shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);

        // And: A protocol share of the swap fees, and the vault holding the range.
        vm.prank(factory);
        almCore.setProtocolFees(0, uint16(bound(bps, 0, ConfigLib.MAX_FEE_BPS)), users.feeRecipient);
        setRangeState(range);

        // And: A burn of the seed holder's shares that takes liquidity from the range.
        uint256 supply = almCore.totalSupply();
        shares = bound(
            shares,
            FixedPointMathLib.min(supply.divUp(range.liquidity), almCore.balanceOf(users.steward)),
            almCore.balanceOf(users.steward)
        );

        // And: A dust range at the same ticks the burn takes nothing from, and swap fees.
        (dust.tickLower, dust.tickUpper) = (range.tickLower, range.tickUpper);
        uint256 ceiling =
            FixedPointMathLib.min((supply - 1) / shares, liquidityCeiling(dust.tickLower, dust.tickUpper, 1) / 4);
        dust.liquidity = uint128(bound(dust.liquidity, 1, ceiling));
        dust.liquidityStaked = uint128(bound(dust.liquidityStaked, 0, ceiling - dust.liquidity));
        setRangeState(dust);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // When: Calculating the burn's amounts on the snapshot at spot.
        (uint256 amount0, uint256 amount1,) = snapshotLib.getBurnAmounts(
            snapshotLib.getSnapshot(address(almCore), address(pool), address(this)), sqrtPriceX96(pool), shares, false
        );

        // Then: They equal what a burn through the core releases.
        vm.prank(users.steward);
        (uint256 released0, uint256 released1) = almCore.burn(shares, users.steward, users.steward);
        assertEq(amount0, released0);
        assertEq(amount1, released1);
    }

    function testFuzz_Success_getBurnAmounts_TakesTheLiquidityOfTheRangesAroundThePrice(
        RangeState[4] memory fuzzed,
        uint160 sqrtPriceX96,
        uint128 shares,
        uint128 supply,
        bool zeroForOne
    ) public view {
        // Given: A price in the band, a tick clear of its ends.
        sqrtPriceX96 = uint160(
            bound(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 2),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 2)
            )
        );
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        // And: Two ranges around the price, one wholly above and one wholly below it.
        RangeState[] memory ranges = new RangeState[](4);
        for (uint256 i; i < 4; ++i) {
            ranges[i] = fuzzed[i];
            ranges[i].liquidity = uint128(bound(ranges[i].liquidity, 1, type(uint64).max));
            ranges[i].liquidityStaked = uint128(bound(ranges[i].liquidityStaked, 0, type(uint64).max));
            if (i < 2) {
                ranges[i].tickLower = int24(bound(ranges[i].tickLower, -Constants.BOUND_TICK, tick - 1));
                ranges[i].tickUpper = int24(bound(ranges[i].tickUpper, tick + 1, Constants.BOUND_TICK));
            }
        }
        ranges[2].tickLower = int24(bound(ranges[2].tickLower, tick + 1, Constants.BOUND_TICK - 1));
        ranges[2].tickUpper = int24(bound(ranges[2].tickUpper, ranges[2].tickLower + 1, Constants.BOUND_TICK));
        ranges[3].tickUpper = int24(bound(ranges[3].tickUpper, -Constants.BOUND_TICK + 1, tick - 1));
        ranges[3].tickLower = int24(bound(ranges[3].tickLower, -Constants.BOUND_TICK, ranges[3].tickUpper - 1));

        // And: A supply and at most it in shares.
        supply = uint128(bound(supply, 1, type(uint128).max));
        shares = uint128(bound(shares, 0, supply));
        Snapshot memory snapshot;
        (snapshot.ranges, snapshot.supply) = (pricedOf(ranges), supply);

        // When: Calculating the burn's amounts for a sale in either direction.
        (,, uint256 activeLiquidityDelta) = snapshotLib.getBurnAmounts(snapshot, sqrtPriceX96, shares, zeroForOne);

        // Then: The burned liquidity, rounded down, of the ranges around it only.
        uint256 liquidity0 = uint256(ranges[0].liquidity) + ranges[0].liquidityStaked;
        uint256 liquidity1 = uint256(ranges[1].liquidity) + ranges[1].liquidityStaked;
        assertEq(activeLiquidityDelta, liquidity0 * shares / supply + liquidity1 * shares / supply);
    }
}
