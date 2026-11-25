/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { MetadexSwapMath_Fuzz_Test } from "./_MetadexSwapMath.fuzz.t.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { SwapMath } from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "computeSwapStep" of library "MetadexSwapMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ComputeSwapStep_MetadexSwapMath_Fuzz_Test is MetadexSwapMath_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(MetadexSwapMath_Fuzz_Test) {
        MetadexSwapMath_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_computeSwapStep_EqualsSlipstream(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) public {
        // Given: Two reachable prices, any liquidity and amount, and a fee below 100%.
        sqrtPriceCurrentX96 = uint160(bound(sqrtPriceCurrentX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        sqrtPriceTargetX96 = uint160(bound(sqrtPriceTargetX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1));
        feePips = uint24(bound(feePips, 0, SwapMath.MAX_SWAP_FEE - 1));

        // When: Computing the step with the port.
        try metadexSwapMath.computeSwapStep(
            sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, amountRemaining, feePips
        ) returns (
            uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount
        ) {
            // Then: Slipstream's own step returns the same four values.
            (uint160 next, uint256 stepIn, uint256 stepOut, uint256 stepFee) = slipstreamSwapMath.computeSwapStep(
                sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, amountRemaining, feePips
            );
            assertEq(sqrtPriceNextX96, next);
            assertEq(amountIn, stepIn);
            assertEq(amountOut, stepOut);
            assertEq(feeAmount, stepFee);
        } catch {
            // Then: Slipstream's own step reverts too.
            vm.expectRevert();
            slipstreamSwapMath.computeSwapStep(
                sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, amountRemaining, feePips
            );
        }
    }

    function testFuzz_Success_computeSwapStep_EqualsSlipstreamForAnExactOutputShortOfTheTarget(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountOut,
        uint24 feePips,
        bool zeroForOne
    ) public view {
        // Given: Band prices a step gap apart, high liquidity, a fee below 100%.
        sqrtPriceCurrentX96 = uint160(
            bound(
                sqrtPriceCurrentX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK) + Constants.MIN_STEP_SQRT_PRICE_GAP,
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK) - Constants.MIN_STEP_SQRT_PRICE_GAP
            )
        );
        sqrtPriceTargetX96 = zeroForOne
            ? uint160(
                bound(
                    sqrtPriceTargetX96,
                    TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                    sqrtPriceCurrentX96 - Constants.MIN_STEP_SQRT_PRICE_GAP
                )
            )
            : uint160(
                bound(
                    sqrtPriceTargetX96,
                    sqrtPriceCurrentX96 + Constants.MIN_STEP_SQRT_PRICE_GAP,
                    TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
                )
            );
        liquidity = uint128(bound(liquidity, Constants.MIN_HIGH_LIQUIDITY, type(uint128).max));
        feePips = uint24(bound(feePips, 0, SwapMath.MAX_SWAP_FEE - 1));

        // And: An exact output of 1 wei to less than the whole step's.
        uint256 stepOut = zeroForOne
            ? SqrtPriceMath.getAmount1Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, false)
            : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, false);
        amountOut = bound(amountOut, 1, stepOut - 1);

        // When: Computing the step with the port.
        (, bytes memory step) = address(metadexSwapMath)
            .staticcall(
                abi.encodeCall(
                    metadexSwapMath.computeSwapStep,
                    (sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, -int256(amountOut), feePips)
                )
            );

        // Then: Slipstream's own step returns the same four values.
        (, bytes memory slipstreamStep) = address(slipstreamSwapMath)
            .staticcall(
                abi.encodeCall(
                    slipstreamSwapMath.computeSwapStep,
                    (sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, -int256(amountOut), feePips)
                )
            );
        assertEq(step, slipstreamStep);
    }

    function testFuzz_Success_computeSwapStep_EqualsSlipstreamForAnExactOutputOfTheWholeStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountOut,
        uint24 feePips,
        bool zeroForOne
    ) public view {
        // Given: Band prices a step gap apart, high liquidity, a fee below 100%.
        sqrtPriceCurrentX96 = uint160(
            bound(
                sqrtPriceCurrentX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK) + Constants.MIN_STEP_SQRT_PRICE_GAP,
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK) - Constants.MIN_STEP_SQRT_PRICE_GAP
            )
        );
        sqrtPriceTargetX96 = zeroForOne
            ? uint160(
                bound(
                    sqrtPriceTargetX96,
                    TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                    sqrtPriceCurrentX96 - Constants.MIN_STEP_SQRT_PRICE_GAP
                )
            )
            : uint160(
                bound(
                    sqrtPriceTargetX96,
                    sqrtPriceCurrentX96 + Constants.MIN_STEP_SQRT_PRICE_GAP,
                    TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
                )
            );
        liquidity = uint128(bound(liquidity, Constants.MIN_HIGH_LIQUIDITY, type(uint128).max));
        feePips = uint24(bound(feePips, 0, SwapMath.MAX_SWAP_FEE - 1));

        // And: An exact output of exactly the whole step's.
        amountOut = zeroForOne
            ? SqrtPriceMath.getAmount1Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, false)
            : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, false);

        // When: Computing the step with the port.
        (, bytes memory step) = address(metadexSwapMath)
            .staticcall(
                abi.encodeCall(
                    metadexSwapMath.computeSwapStep,
                    (sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, -int256(amountOut), feePips)
                )
            );

        // Then: Slipstream's own step returns the same four values.
        (, bytes memory slipstreamStep) = address(slipstreamSwapMath)
            .staticcall(
                abi.encodeCall(
                    slipstreamSwapMath.computeSwapStep,
                    (sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, -int256(amountOut), feePips)
                )
            );
        assertEq(step, slipstreamStep);
    }
}
