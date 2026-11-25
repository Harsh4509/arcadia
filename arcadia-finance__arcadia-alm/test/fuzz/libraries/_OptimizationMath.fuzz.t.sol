/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { Fuzz_Test } from "../Fuzz.t.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { MetadexTickBitmap } from "../../../src/shared/libraries/vendored/MetadexTickBitmap.sol";
import { PoolLogic } from "../../../src/shared/libraries/logic/PoolLogic.sol";
import { PoolMock } from "../../utils/mocks/PoolMock.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { Snapshot } from "../../../src/vaults/types/Snapshot.sol";
import { SnapshotLibExtension } from "../../utils/extensions/SnapshotLibExtension.sol";
import { StepComputations, SwapState } from "../../../src/vaults/types/SwapState.sol";
import { SwapMath } from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "OptimizationMath" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract OptimizationMath_Fuzz_Test is Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The mock core, with no protocol swap fee and the widest max swap cost.
    address internal constant MOCK_CORE = address(uint160(uint256(keccak256("core"))));

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    struct MintState {
        uint160 sqrtPriceX96;
        uint128 liquidity;
        uint128 supply;
        uint64 idle0;
        uint64 idle1;
        uint24 fee;
        bool zeroForOne;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    SnapshotLibExtension internal snapshotLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        snapshotLib = new SnapshotLibExtension();

        vm.etch(MOCK_CORE, hex"00");
        vm.mockCall(MOCK_CORE, abi.encodeWithSignature("extsload(bytes32)"), abi.encode(bytes32(0)));
        mockMaxSwapCostBps(MOCK_CORE, ConfigLib.BPS_DENOMINATOR);
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function givenValidRangeAroundSpot(RangeState memory range, uint160 sqrtPriceX96) internal pure {
        // And: A range a tick clear around spot, in the band, its liquidity a uint128.
        int24 tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        range.tickLower = int24(bound(range.tickLower, -Constants.BOUND_TICK, tick - 1));
        range.tickUpper = int24(bound(range.tickUpper, tick + 2, Constants.BOUND_TICK));
        range.liquidity = uint128(bound(range.liquidity, 1, type(uint64).max));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, type(uint64).max));
    }

    function givenValidState(MintState memory state, RangeState memory range, bool otherLiquidity) internal pure {
        // And: A spot in the band, a supply, a fee, and a range around spot in the pool.
        state.sqrtPriceX96 = uint160(
            bound(
                state.sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK + 1),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK - 2)
            )
        );
        state.supply = uint128(bound(state.supply, 1, type(uint64).max));
        state.fee = uint24(bound(state.fee, 0, Constants.MAX_POOL_FEE));
        givenValidRangeAroundSpot(range, state.sqrtPriceX96);

        // And: With other liquidity, as much more and the fuzzed liquidity floor.
        uint256 rangeLiquidity = uint256(range.liquidity) + range.liquidityStaked;
        state.liquidity = uint128(
            bound(
                state.liquidity,
                otherLiquidity ? 2 * rangeLiquidity + Constants.MIN_FUZZED_LIQUIDITY : rangeLiquidity,
                type(uint128).max
            )
        );
    }

    function snapshotOf(
        PricedRange[] memory ranges,
        uint256 idle0,
        uint256 idle1,
        uint256 supply,
        uint160 sqrtPriceX96,
        uint24 fee
    ) internal pure returns (Snapshot memory snapshot) {
        snapshot = Snapshot({
            buffer0: idle0,
            buffer1: idle1,
            fees0: 0,
            fees1: 0,
            supply: supply,
            sqrtPriceX96: sqrtPriceX96,
            tick: TickMath.getTickAtSqrtPrice(sqrtPriceX96),
            fee: fee,
            core: IALMCore(MOCK_CORE),
            ranges: ranges
        });
    }

    function poolOf(int24 tickSpacing, uint128 liquidity, PricedRange[] memory ranges) internal returns (address pool) {
        // A pool with the liquidity at spot, its ticks at the ranges' edges.
        PoolMock mock = new PoolMock(tickSpacing, liquidity);
        for (uint256 i; i < ranges.length; ++i) {
            if (ranges[i].liquidity == 0) continue;
            mock.addLiquidityNet(TickMath.getTickAtSqrtPrice(ranges[i].sqrtPriceLowerX96), int128(ranges[i].liquidity));
            mock.addLiquidityNet(TickMath.getTickAtSqrtPrice(ranges[i].sqrtPriceUpperX96), -int128(ranges[i].liquidity));
        }
        pool = address(mock);
    }

    function swap(
        Snapshot memory snapshot,
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) internal view returns (uint160 sqrtPriceX96, uint256 amountIn, uint256 amountOut) {
        // The pool's swap, step by step to each tick or word end, exact in when negative.
        SwapState memory state;
        (state.sqrtPriceX96, state.tick, state.fee, state.liquidity) =
        (snapshot.sqrtPriceX96, snapshot.tick, snapshot.fee, PoolMock(pool).liquidity());
        while (amountSpecified != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;
            (step.tickNext, step.initialized) = MetadexTickBitmap.nextInitializedTickWithinOneWord(
                pool, state.tick, PoolMock(pool).tickSpacing(), zeroForOne
            );
            if (step.tickNext < TickMath.MIN_TICK) step.tickNext = TickMath.MIN_TICK;
            else if (step.tickNext > TickMath.MAX_TICK) step.tickNext = TickMath.MAX_TICK;
            step.sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(step.tickNext);
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                SwapMath.getSqrtPriceTarget(zeroForOne, step.sqrtPriceNextX96, sqrtPriceLimitX96),
                state.liquidity,
                amountSpecified,
                state.fee
            );
            (amountIn, amountOut) = (amountIn + step.amountIn + step.feeAmount, amountOut + step.amountOut);
            amountSpecified = amountSpecified < 0
                ? amountSpecified + int256(step.amountIn + step.feeAmount)
                : amountSpecified - int256(step.amountOut);
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityNet = PoolLogic.liquidityNet(pool, step.tickNext);
                    state.liquidity = zeroForOne
                        ? uint128(int128(state.liquidity) - liquidityNet)
                        : uint128(int128(state.liquidity) + liquidityNet);
                }
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            }
        }
        sqrtPriceX96 = state.sqrtPriceX96;
    }
}
