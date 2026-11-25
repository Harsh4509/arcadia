/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { MetadexPositionValue_Fuzz_Test } from "./_MetadexPositionValue.fuzz.t.sol";
import { TokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "fees" of library "MetadexPositionValue".
 */
// forge-lint: disable-next-item(unused-return)
contract Fees_MetadexPositionValue_Fuzz_Test is MetadexPositionValue_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_fees_NoSwapsLeaveNothingOwed(PoolState memory poolState, RangeState memory range) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A position that no swap has crossed.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool,
            users.liquidityProvider,
            address(positionManagerLogic),
            range.tickLower,
            range.tickUpper,
            range.liquidity
        );

        // When: Reading what it has accrued.
        (uint256 fee0, uint256 fee1) = positionValue.fees(address(pool), address(POSITION_MANAGER), tokenId);

        // Then: It has accrued nothing.
        assertEq(fee0, 0);
        assertEq(fee1, 0);
    }

    function testFuzz_Success_fees_MatchesWhatCollectPaysOut(
        PoolState memory poolState,
        RangeState memory range,
        uint256 amountIn,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A range around spot.
        int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
        int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
        range.tickLower = int24(bound(range.tickLower, -band + 1, compressed)) * poolState.tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper, compressed + 1, band - 1)) * poolState.tickSpacing;

        // And: A position on it, and a swap across it that leaves fees behind.
        givenValidRangeState(range, poolState, false);
        (uint256 tokenId,) = mintPositionFor(
            pool,
            users.liquidityProvider,
            address(positionManagerLogic),
            range.tickLower,
            range.tickUpper,
            range.liquidity
        );
        (address tokenIn, address tokenOut) =
            zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        swapInPool(
            pool,
            users.liquidityProvider,
            tokenIn,
            tokenOut,
            feeEarningTrade(pool, range.liquidity, amountIn, zeroForOne)
        );

        // When: Reading what it has accrued.
        (uint256 fee0, uint256 fee1) = positionValue.fees(address(pool), address(POSITION_MANAGER), tokenId);

        // Then: It is exactly what collecting the position pays out.
        TokenDelta gross = positionManagerLogic.collect(tokenId);
        assertEq(int256(fee0), int256(gross.amount0()));
        assertEq(int256(fee1), int256(gross.amount1()));
    }

    function testFuzz_Success_fees_AddsNewFeesToWhatIsOwed(
        PoolState memory poolState,
        RangeState memory range,
        uint256 amountIn,
        uint256 secondAmountIn,
        uint128 decreased,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A caller of the library on the pool's tokens and tick spacing.
        deployPositionManagerLogic();

        // And: A band-wide position deeper than the others, its fees collected once.
        int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing - 1;
        range.tickLower = -band * poolState.tickSpacing;
        range.tickUpper = band * poolState.tickSpacing;
        range.liquidity = uint128(
            bound(
                range.liquidity,
                FixedPointMathLib.max(Constants.MIN_FUZZED_LIQUIDITY, uint256(poolState.liquidityPool) + 1),
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        (uint256 tokenId,) = mintPositionFor(
            pool,
            users.liquidityProvider,
            address(positionManagerLogic),
            range.tickLower,
            range.tickUpper,
            range.liquidity
        );
        (address tokenIn, address tokenOut) =
            zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        swapInPool(
            pool,
            users.liquidityProvider,
            tokenIn,
            tokenOut,
            feeEarningTrade(pool, range.liquidity, amountIn, zeroForOne)
        );
        positionManagerLogic.collect(tokenId);

        // And: Part of it decreased to the others' depth, a second swap the same way.
        decreased = uint128(bound(decreased, 1, range.liquidity - poolState.liquidityPool));
        positionManagerLogic.decreaseLiquidity(tokenId, decreased, 0, 0);
        secondAmountIn = feeEarningTrade(pool, range.liquidity - decreased, secondAmountIn, zeroForOne);
        swapInPool(pool, users.liquidityProvider, tokenIn, tokenOut, secondAmountIn);

        // When: Reading what it has accrued.
        (uint256 fee0, uint256 fee1) = positionValue.fees(address(pool), address(POSITION_MANAGER), tokenId);

        // Then: It is exactly what collecting the position pays out.
        TokenDelta gross = positionManagerLogic.collect(tokenId);
        assertEq(int256(fee0), int256(gross.amount0()));
        assertEq(int256(fee1), int256(gross.amount1()));
    }
}
