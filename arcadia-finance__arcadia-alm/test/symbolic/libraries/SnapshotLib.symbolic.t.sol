/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPosition } from "../../../src/vaults/types/EquivalentPosition.sol";
import { EquivalentPositionMath } from "../../../src/vaults/libraries/math/EquivalentPositionMath.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { Snapshot, SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { SnapshotLibExtension } from "../../utils/extensions/SnapshotLibExtension.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { stdError } from "@forge-std/StdError.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Symbolic tests for the library "SnapshotLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract SnapshotLib_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                 STORAGE
    ////////////////////////////////////////////////////////////// */

    Range[] internal ranges;

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    SnapshotLibExtension internal snapshotLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        snapshotLib = new SnapshotLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function oneRange(
        uint128 liquidity,
        uint128 unstakedLiquidity,
        uint160 lower,
        uint160 upper,
        uint128 idle0,
        uint128 idle1,
        uint256 supply
    ) internal pure returns (Snapshot memory snapshot) {
        snapshot.ranges = new PricedRange[](1);
        snapshot.ranges[0] = PricedRange(liquidity, unstakedLiquidity, lower, upper);
        (snapshot.buffer0, snapshot.buffer1, snapshot.supply) = (idle0, idle1, supply);
        snapshot.core = IALMCore(address(0));
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getSwapCostLimit_ZeroForOne_IsAtMostThePrice(
        uint256 sqrtPriceX96,
        uint256 fee,
        uint256 maxSwapCostBps
    ) public pure {
        // Given: A pool price, a pool fee below one and a max swap cost below one.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(fee < 1e6 && maxSwapCostBps < 10_000);

        // When: Taking the limit of a swap of token0.
        // Then: It is at most the price.
        assertLe(SnapshotLib.getSwapCostLimit(sqrtPriceX96, fee, maxSwapCostBps, true), sqrtPriceX96);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getSwapCostLimit_OneForZero_IsAtLeastThePriceWhenTheBandFitsUint160(
        uint256 sqrtPriceX96,
        uint256 fee,
        uint256 maxSwapCostBps
    ) public pure {
        // Given: A price, fee < one, max swap cost < one with its band in uint160.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(fee < 1e6 && maxSwapCostBps < 10_000);
        vm.assume(sqrtPriceX96 * (1e18 + maxSwapCostBps * 100 * 5e11) / 1e18 <= type(uint160).max);

        // When: Taking the limit of a swap of token1.
        // Then: It is at least the price.
        assertGe(SnapshotLib.getSwapCostLimit(sqrtPriceX96, fee, maxSwapCostBps, false), sqrtPriceX96);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getSwapCostLimit_WithoutACostAboveTheFeeIsThePrice(
        uint256 sqrtPriceX96,
        uint256 fee,
        uint256 maxSwapCostBps,
        bool zeroForOne
    ) public pure {
        // Given: A pool price and a max swap cost within the pool fee.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(fee < 1e6 && maxSwapCostBps * 100 <= fee);

        // When: Taking the limit of a swap in either direction.
        // Then: It is the price.
        assertEq(SnapshotLib.getSwapCostLimit(sqrtPriceX96, fee, maxSwapCostBps, zeroForOne), sqrtPriceX96);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmounts_OfNoSharesTakeNothing(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1,
        uint256 supply,
        bool zeroForOne
    ) public pure {
        // Given: One range < 2^128, product >= 2^96, idle tokens, a supply and a price.
        vm.assume(lower >= TickMath.MIN_SQRT_PRICE && lower < upper && upper <= type(uint128).max);
        vm.assume(uint256(lower) * upper >= 1 << 96 && supply != 0);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        Snapshot memory snapshot = oneRange(liquidity, 0, lower, upper, idle0, idle1, supply);

        // When: Taking what a mint of no shares takes.
        (uint256 amountIn, uint256 amountOut, uint256 activeLiquidityDelta) =
            SnapshotLib.getMintAmounts(snapshot, sqrtPriceX96, 0, zeroForOne);

        // Then: Nothing.
        assertEq(amountIn, 0);
        assertEq(amountOut, 0);
        assertEq(activeLiquidityDelta, 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmounts_AreAtLeastTheBurnAmounts(
        uint128 liquidity,
        uint128 unstakedLiquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1,
        uint256 shares,
        uint256 supply
    ) public pure {
        // Given: Range <= 1, product >= 2^96, L < 2^63, idle, uint128 mint, price <= 1.
        vm.assume(lower >= TickMath.MIN_SQRT_PRICE && lower < upper && upper <= 1 << 96 && liquidity < 1 << 63);
        vm.assume(uint256(lower) * upper >= 1 << 96 && unstakedLiquidity <= liquidity && shares <= supply);
        vm.assume(supply != 0 && supply <= type(uint128).max);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= 1 << 96);
        Snapshot memory snapshot = oneRange(liquidity, unstakedLiquidity, lower, upper, idle0, idle1, supply);

        // When: Taking what a mint of the shares takes and what a burn of them releases.
        (uint256 mintIn, uint256 mintOut,) = SnapshotLib.getMintAmounts(snapshot, sqrtPriceX96, shares, true);
        (uint256 burnIn, uint256 burnOut,) = SnapshotLib.getBurnAmounts(snapshot, sqrtPriceX96, shares, true);

        // Then: The mint takes at least what the burn releases, in both tokens.
        assertGe(mintIn, burnIn);
        assertGe(mintOut, burnOut);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmounts_AboveTheRange_ExceedTheBurnAmountsByAtMostTheRounding(
        uint128 liquidity,
        uint128 unstakedLiquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle1,
        uint256 shares,
        uint256 supply
    ) public pure {
        // Given: Range < 2^128, product >= 2^96, idle token1, uint128 mint, price above.
        vm.assume(lower >= TickMath.MIN_SQRT_PRICE && lower < upper && upper <= sqrtPriceX96);
        vm.assume(sqrtPriceX96 <= type(uint128).max && uint256(lower) * upper >= 1 << 96);
        vm.assume(unstakedLiquidity <= liquidity && shares <= supply && supply != 0 && supply <= type(uint128).max);
        Snapshot memory snapshot = oneRange(liquidity, unstakedLiquidity, lower, upper, 0, idle1, supply);

        // When: Taking what a mint of the shares takes and a burn releases, in token1.
        (, uint256 mint1,) = SnapshotLib.getMintAmounts(snapshot, sqrtPriceX96, shares, true);
        (, uint256 burn1,) = SnapshotLib.getBurnAmounts(snapshot, sqrtPriceX96, shares, true);

        // Then: The mint takes at most the burn's token1 plus the rounding.
        assertLe(mint1, burn1 + SnapshotLib.getRounding(snapshot, sqrtPriceX96, false));
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getBurnAmounts_OfNoSharesReleaseNothing(
        uint128 liquidity,
        uint128 unstakedLiquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1,
        uint256 supply,
        bool zeroForOne
    ) public pure {
        // Given: One range <= one, liquidity < 2^63, idle tokens, supply, price <= one.
        vm.assume(lower >= TickMath.MIN_SQRT_PRICE && lower < upper && upper <= 1 << 96 && liquidity < 1 << 63);
        vm.assume(unstakedLiquidity <= liquidity && supply != 0);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= 1 << 96);
        Snapshot memory snapshot = oneRange(liquidity, unstakedLiquidity, lower, upper, idle0, idle1, supply);

        // When: Taking what a burn of no shares releases.
        (uint256 amountIn, uint256 amountOut, uint256 activeLiquidityDelta) =
            SnapshotLib.getBurnAmounts(snapshot, sqrtPriceX96, 0, zeroForOne);

        // Then: Nothing.
        assertEq(amountIn, 0);
        assertEq(amountOut, 0);
        assertEq(activeLiquidityDelta, 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getBurnAmounts_NeverExceedTheCoresAmounts(
        uint128 liquidity,
        uint128 unstakedLiquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1,
        uint256 shares,
        uint256 supply
    ) public pure {
        // Given: Range <= one, liquidity < 2^63, idle tokens, uint128 burn, price <= one.
        vm.assume(lower >= TickMath.MIN_SQRT_PRICE && lower < upper && upper <= 1 << 96 && liquidity < 1 << 63);
        vm.assume(unstakedLiquidity <= liquidity && shares <= supply && supply != 0 && supply <= type(uint128).max);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= 1 << 96);
        Snapshot memory snapshot = oneRange(liquidity, unstakedLiquidity, lower, upper, idle0, idle1, supply);

        // When: Taking what a burn of the shares releases and what the core holds.
        (uint256 burn0, uint256 burn1,) = SnapshotLib.getBurnAmounts(snapshot, sqrtPriceX96, shares, true);
        (uint256 amount0, uint256 amount1) = SnapshotLib.getAmountsAt(snapshot, sqrtPriceX96);

        // Then: The burn releases at most what the core holds, in both tokens.
        assertLe(burn0, amount0);
        assertLe(burn1, amount1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintShares_AboveTheRange_TheMintOfItsSharesIsCoveredByTheBalances(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle1,
        uint256 supply,
        uint256 amount1
    ) public pure {
        // Given: Range < 2^128 under price, product >= 2^96, idle token1, token1 < 2^127.
        vm.assume(lower >= TickMath.MIN_SQRT_PRICE && lower < upper && upper <= sqrtPriceX96);
        vm.assume(sqrtPriceX96 <= type(uint128).max && uint256(lower) * upper >= 1 << 96);
        vm.assume(supply != 0 && supply <= type(uint128).max && amount1 < 1 << 127);
        Snapshot memory snapshot = oneRange(liquidity, 0, lower, upper, 0, idle1, supply);

        // When: Taking the shares the balance mints, and what their mint takes.
        uint256 shares = SnapshotLib.getMintShares(snapshot, sqrtPriceX96, 0, amount1, true);
        (uint256 mint0, uint256 mint1,) = SnapshotLib.getMintAmounts(snapshot, sqrtPriceX96, shares, true);

        // Then: The mint takes no token0 and at most the token1 balance.
        assertEq(mint0, 0);
        assertLe(mint1, amount1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintShares_BelowTheRange_TheMintOfItsSharesIsCoveredByTheBalances(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint256 supply,
        uint256 amount0
    ) public pure {
        // Given: Range < 2^128 over price, lower >= 2^48, idle token0, token0 < 2^127.
        vm.assume(lower >= 1 << 48 && lower < upper && upper <= type(uint128).max);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= lower);
        vm.assume(supply != 0 && supply <= type(uint128).max && amount0 < 1 << 127);
        Snapshot memory snapshot = oneRange(liquidity, 0, lower, upper, idle0, 0, supply);

        // When: Taking the shares the balance mints, liquidity in uint128, mint's take.
        uint256 shares = SnapshotLib.getMintShares(snapshot, sqrtPriceX96, amount0, 0, true);
        vm.assume(liquidity == 0 || shares <= type(uint128).max * supply / liquidity);
        (uint256 mint0, uint256 mint1,) = SnapshotLib.getMintAmounts(snapshot, sqrtPriceX96, shares, true);

        // Then: The mint takes at most the token0 balance and no token1.
        assertLe(mint0, amount0);
        assertEq(mint1, 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintShares_WithoutLiquidity_TheMintOfItsSharesIsCoveredWithItsCarriedFee(
        uint64 idle0,
        uint64 supply,
        uint160 sqrtPriceX96,
        uint64 amount0
    ) public pure {
        // Given: Range without liquidity, idle token0, supply, price >= one, a balance.
        vm.assume(supply != 0 && sqrtPriceX96 >= 1 << 96 && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        Snapshot memory snapshot = oneRange(0, 0, 1 << 96, 1 << 97, idle0, 0, supply);

        // When: Taking the shares the balance mints as tokenIn, for any share count.
        uint256 shares = SnapshotLib.getMintShares(snapshot, sqrtPriceX96, amount0, 0, true);

        // Then: Their idle token0 plus carried fee wei, rounded up, is at most balance.
        uint256 pull = (uint256(idle0) + 1) * shares / supply;
        if ((uint256(idle0) + 1) * shares % supply != 0) ++pull;
        assertLe(pull, amount0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintShares_WithoutRanges_TheTokenOutLegBindsWhenTheTokenInCoversTheRatio(
        uint64 idle0,
        uint64 idle1,
        uint64 supply,
        uint160 sqrtPriceX96,
        uint64 amount0,
        uint64 amount1
    ) public pure {
        // Given: Idle only, a supply, a price, token0 net of rounding covers idle ratio.
        vm.assume(idle0 != 0 && idle1 != 0 && supply != 0 && amount0 != 0);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(uint256(amount0 - 1) * idle1 >= uint256(amount1) * idle0);
        Snapshot memory snapshot;
        (snapshot.buffer0, snapshot.buffer1, snapshot.supply) = (idle0, idle1, supply);

        // When: Taking the shares the balances mint with token0 as tokenIn.
        uint256 shares = SnapshotLib.getMintShares(snapshot, sqrtPriceX96, amount0, amount1, true);

        // Then: Token1 binds: shares are token1 net of rounding over the idle token1.
        assertEq(shares, uint256(amount1 == 0 ? 0 : amount1 - 1) * supply / idle1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getRounding_NeverFallsAlongTheSwap(uint160 sqrtPriceX96, uint160 sqrtPriceTargetX96, bool zeroForOne)
        public
        pure
    {
        // Given: One range, a pool price and a step target in the swap's direction.
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(sqrtPriceTargetX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceTargetX96 <= TickMath.MAX_SQRT_PRICE);
        vm.assume(zeroForOne ? sqrtPriceTargetX96 <= sqrtPriceX96 : sqrtPriceTargetX96 >= sqrtPriceX96);
        Snapshot memory snapshot = oneRange(0, 0, 0, 0, 0, 0, 1);

        // When: Taking tokenIn's rounding at the price and at the target.
        // Then: The target's is at least the price's.
        assertGe(
            SnapshotLib.getRounding(snapshot, sqrtPriceTargetX96, zeroForOne),
            SnapshotLib.getRounding(snapshot, sqrtPriceX96, zeroForOne)
        );
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmounts_OfTheSupply_Token1InExceedsThePositionByAtMostThree(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle1
    ) public pure {
        // Given: One range < 2^128, idle token1, a one-share supply and a price < 2^128.
        vm.assume(lower >= TickMath.MIN_SQRT_PRICE && lower < upper && upper <= type(uint128).max);
        vm.assume(sqrtPriceX96 >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= type(uint128).max);
        Snapshot memory snapshot = oneRange(liquidity, 0, lower, upper, 0, idle1, 1);

        // When: Taking a whole-supply mint's token1 cost, and the equivalent position's.
        (uint256 cost,,) = SnapshotLib.getMintAmounts(snapshot, sqrtPriceX96, 1, false);
        (uint256 held,) = EquivalentPositionMath.amountsAt(
            SnapshotLib.getPosition(snapshot, sqrtPriceX96, false), sqrtPriceX96, false
        );

        // Then: The cost exceeds the position by at most the fee wei, ceiling and floor.
        assertLe(cost, held + 3);
    }

    function prove_idle_SucceedsIffBothSumsFit(uint256 buffer0, uint256 buffer1, uint256 fees0, uint256 fees1)
        public
        view
    {
        // Given: Any buffer and uncollected fees.
        Snapshot memory snapshot;
        (snapshot.buffer0, snapshot.buffer1, snapshot.fees0, snapshot.fees1) = (buffer0, buffer1, fees0, fees1);
        bool fits = buffer0 <= type(uint256).max - fees0 && buffer1 <= type(uint256).max - fees1;

        // When: Taking the idle tokens.
        (bool success, bytes memory result) =
            address(snapshotLib).staticcall(abi.encodeCall(SnapshotLibExtension.idle, (snapshot)));

        // Then: It succeeds iff both sums fit, and is the buffer plus the fees.
        assertEq(success, fits);
        if (success) {
            (uint256 idle0, uint256 idle1) = abi.decode(result, (uint256, uint256));
            assertEq(idle0, buffer0 + fees0);
            assertEq(idle1, buffer1 + fees1);
        } else {
            assertEq(result, stdError.arithmeticError);
        }
    }

    function prove_getAmountsAt_WithoutRangesIsTheIdleTokens(
        uint256 buffer0,
        uint256 buffer1,
        uint256 fees0,
        uint256 fees1,
        uint160 sqrtPriceX96
    ) public pure {
        // Given: No ranges, a buffer and uncollected fees whose sums fit, and any price.
        vm.assume(buffer0 <= type(uint256).max - fees0 && buffer1 <= type(uint256).max - fees1);
        Snapshot memory snapshot;
        (snapshot.buffer0, snapshot.buffer1, snapshot.fees0, snapshot.fees1) = (buffer0, buffer1, fees0, fees1);

        // When: Taking the tokens the core holds at the price.
        (uint256 amount0, uint256 amount1) = SnapshotLib.getAmountsAt(snapshot, sqrtPriceX96);

        // Then: They are the buffer plus the fees.
        assertEq(amount0, buffer0 + fees0);
        assertEq(amount1, buffer1 + fees1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getAmountsAt_OneRange_AddsThePoolsAmountsToTheIdleTokens(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1
    ) public pure {
        // Given: One range between pool prices, uint128 idle tokens and any price.
        vm.assume(lower >= TickMath.MIN_SQRT_PRICE && lower < upper && upper <= TickMath.MAX_SQRT_PRICE);
        Snapshot memory snapshot = oneRange(liquidity, 0, lower, upper, idle0, idle1, 0);
        (uint160 sqrtPriceAX96, uint160 sqrtPriceBX96) =
            sqrtPriceX96 <= lower ? (lower, upper) : sqrtPriceX96 < upper ? (sqrtPriceX96, upper) : (upper, upper);
        uint256 expected0 = SqrtPriceMath.getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, false);
        (sqrtPriceAX96, sqrtPriceBX96) =
            sqrtPriceX96 <= lower ? (lower, lower) : sqrtPriceX96 < upper ? (lower, sqrtPriceX96) : (lower, upper);
        uint256 expected1 = SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, false);

        // When: Taking the tokens the core holds at the price.
        (uint256 amount0, uint256 amount1) = SnapshotLib.getAmountsAt(snapshot, sqrtPriceX96);

        // Then: They are the pool's rounded down amounts plus the idle tokens.
        assertEq(amount0, expected0 + idle0);
        assertEq(amount1, expected1 + idle1);
    }

    function prove_getPosition_WithoutRangesHoldsTheIdleTokens(
        uint256 buffer0,
        uint256 buffer1,
        uint256 fees0,
        uint256 fees1,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) public pure {
        // Given: No ranges, a buffer and fees below 2^254 each, and any price.
        vm.assume(buffer0 < 1 << 254 && buffer1 < 1 << 254 && fees0 < 1 << 254 && fees1 < 1 << 254);
        Snapshot memory snapshot;
        (snapshot.buffer0, snapshot.buffer1, snapshot.fees0, snapshot.fees1) = (buffer0, buffer1, fees0, fees1);

        // When: Taking the equivalent position.
        EquivalentPosition memory position = SnapshotLib.getPosition(snapshot, sqrtPriceX96, zeroForOne);

        // Then: It holds the buffer plus the fees only, bounded by the extreme price.
        assertEq(position.liquidity, 0);
        assertEq(position.unstakedLiquidity, 0);
        assertEq(position.constant0, -int256(buffer0 + fees0));
        assertEq(position.constant1, -int256(buffer1 + fees1));
        assertEq(position.sqrtPriceBound, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1);
    }

    function prove_decodePricedRanges_PricesTheStoredRange(Range memory stored, uint128 unstakedLiquidity) public {
        // Given: A stored range of valid ticks, and an unstaked liquidity that fits.
        vm.assume(stored.tickLower >= TickMath.MIN_TICK && stored.tickLower <= TickMath.MAX_TICK);
        vm.assume(stored.tickUpper >= TickMath.MIN_TICK && stored.tickUpper <= TickMath.MAX_TICK);
        vm.assume(unstakedLiquidity <= type(uint128).max - stored.stakedLiquidity);
        ranges.push(stored);
        uint256 rangesSlot;
        assembly ("memory-safe") {
            rangesSlot := ranges.slot
        }
        uint256 base = uint256(keccak256(abi.encode(rangesSlot)));
        bytes32[] memory words = new bytes32[](2);
        words[0] = vm.load(address(this), bytes32(base));
        words[1] = vm.load(address(this), bytes32(base + 1));
        uint128[] memory positionLiquidity = new uint128[](1);
        positionLiquidity[0] = unstakedLiquidity;

        // When: Decoding its two storage words with its unstaked liquidity.
        PricedRange[] memory decoded = SnapshotLib.decodePricedRanges(words, positionLiquidity);

        // Then: It holds both sides' liquidity, the unstaked one's, its ticks' prices.
        assertEq(decoded.length, 1);
        assertEq(decoded[0].liquidity, uint256(unstakedLiquidity) + stored.stakedLiquidity);
        assertEq(decoded[0].unstakedLiquidity, unstakedLiquidity);
        assertEq(decoded[0].sqrtPriceLowerX96, TickMath.getSqrtPriceAtTick(stored.tickLower));
        assertEq(decoded[0].sqrtPriceUpperX96, TickMath.getSqrtPriceAtTick(stored.tickUpper));
    }
}
