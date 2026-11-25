/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ALMCoreViewLogic } from "../../core/libraries/logic/ALMCoreViewLogic.sol";
import { CLMath } from "../../shared/libraries/math/CLMath.sol";
import { EquivalentPosition } from "./EquivalentPosition.sol";
import { EquivalentPositionMath } from "../libraries/math/EquivalentPositionMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../interfaces/IALMCore.sol";
import { IMetadexCLPool } from "../../interfaces/IMetadexCLPool.sol";
import { PricedRange } from "./PricedRange.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice What a core holds: its buffer, its uncollected fees, its supply and its ranges, with the pool's price and tick.
 */
struct Snapshot {
    uint256 buffer0;
    uint256 buffer1;
    uint256 fees0;
    uint256 fees1;
    uint256 supply;
    uint160 sqrtPriceX96;
    int24 tick;
    uint24 fee;
    IALMCore core;
    PricedRange[] ranges;
}

/**
 * @title Snapshot Library.
 * @author Pragma Labs
 * @notice Reads a core's snapshot and converts between aLP shares and token amounts at a price.
 */
// forge-lint: disable-next-item(uninitialized-local, unsafe-typecast, unused-return)
library SnapshotLib {
    using ALMCoreViewLogic for IALMCore;
    using ALMCoreViewLogic for bytes32[];
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                               SNAPSHOT
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice What a core holds, read once: buffer, uncollected fees, supply and priced ranges, with the pool's price and tick.
     * @param core The core.
     * @param pool The Metadex CL pool.
     * @param vault The vault whose swap the pool's fee is read for.
     * @return snapshot The core's snapshot.
     */
    function getSnapshot(IALMCore core, address pool, address vault) internal view returns (Snapshot memory snapshot) {
        uint128[] memory positionLiquidity;
        (snapshot.fees0, snapshot.fees1, positionLiquidity) = core.getUnstakedPositions();
        (snapshot.buffer0, snapshot.buffer1) = core.getBuffer();
        snapshot.ranges = decodePricedRanges(core.readRangeWords(), positionLiquidity);
        snapshot.supply = core.totalSupply();
        (snapshot.sqrtPriceX96, snapshot.tick,,,,) = IMetadexCLPool(pool).slot0();
        IMetadexCLPool.SwapParams memory swapParams;
        swapParams.caller = vault;
        snapshot.fee = IMetadexCLPool(pool).beforeSwapFee(swapParams);
        snapshot.core = core;
    }

    /**
     * @notice The share of its swap fees the core's unstaked liquidity keeps, net of the pool's levy and the protocol's share.
     * @param snapshot The core's snapshot.
     * @param pool The Metadex CL pool.
     * @return feeShare The share, with 10 decimals precision.
     */
    function getFeeShare(Snapshot memory snapshot, address pool) internal view returns (uint256 feeShare) {
        uint256 pauseAndFees =
            uint256(snapshot.core.extsload(ALMCoreViewLogic.memberSlot(ALMCoreViewLogic.PAUSE_AND_FEES_OFFSET)));
        // Unchecked: the unstaked fee is at most 1e6 and the protocol's share at most 5000 bps.
        unchecked {
            feeShare = (1e6 - uint256(IMetadexCLPool(pool).unstakedFee()))
                * (1e4 - uint256(uint16(pauseAndFees >> ALMCoreViewLogic.SWAP_FEE_BPS_SHIFT)));
        }
    }

    /**
     * @notice The price at which a swap from spot reaches the core's max swap cost.
     * @param snapshot The core's snapshot.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return The square root of the price, with 96 binary precision.
     * @dev A swap from P0 to P1 loses at most 1 − (1 − fee) * P1 / P0: half the cost beyond the fee in square root price.
     */
    function getSwapCostLimit(Snapshot memory snapshot, bool zeroForOne) internal view returns (uint160) {
        return getSwapCostLimit(snapshot.sqrtPriceX96, snapshot.fee, snapshot.core.getMaxSwapCostBps(), zeroForOne);
    }

    /**
     * @notice The price at which a swap from a price reaches a max swap cost.
     * @param sqrtPriceX96 The square root of the price (token1/token0) the swap starts from, with 96 binary precision.
     * @param fee The pool's swap fee, in 1e-6.
     * @param maxSwapCostBps The max swap cost, in bps.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return The square root of the price, with 96 binary precision.
     */
    function getSwapCostLimit(uint256 sqrtPriceX96, uint256 fee, uint256 maxSwapCostBps, bool zeroForOne)
        internal
        pure
        returns (uint160)
    {
        // Unchecked: the max swap cost is a uint16 at every caller.
        unchecked {
            (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) =
                CLMath.getBand(sqrtPriceX96, (maxSwapCostBps * 100).zeroFloorSub(fee) * 5e11);
            return uint160(zeroForOne ? sqrtPriceLowerX96 : sqrtPriceUpperX96);
        }
    }

    /**
     * @notice Decodes each range's two storage words and its unstaked side's liquidity into a priced range.
     * @param words Two storage words per range.
     * @param positionLiquidity Every unstaked side's liquidity.
     * @return ranges The priced ranges.
     */
    function decodePricedRanges(bytes32[] memory words, uint128[] memory positionLiquidity)
        internal
        pure
        returns (PricedRange[] memory ranges)
    {
        uint256 length = words.length / 2;
        ranges = new PricedRange[](length);
        for (uint256 i; i < length; ++i) {
            (int24 tickLower, int24 tickUpper, uint128 stakedLiquidity) = words.decodeRange(i);
            PricedRange memory range = ranges[i];
            // Unchecked: both sides are positions on the range's ticks, within the pool's max liquidity per tick.
            unchecked {
                range.liquidity = positionLiquidity[i] + stakedLiquidity;
            }
            range.unstakedLiquidity = positionLiquidity[i];
            range.sqrtPriceLowerX96 = TickMath.getSqrtPriceAtTick(tickLower);
            range.sqrtPriceUpperX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        }
    }

    /**
     * @notice The tokens a core holds outside its ranges.
     * @param snapshot The core's snapshot.
     * @return idle0 The token0 in the buffer and uncollected fees.
     * @return idle1 The token1 in the buffer and uncollected fees.
     */
    function idle(Snapshot memory snapshot) internal pure returns (uint256 idle0, uint256 idle1) {
        (idle0, idle1) = (snapshot.buffer0 + snapshot.fees0, snapshot.buffer1 + snapshot.fees1);
    }

    /**
     * @notice The core's equivalent position at a price, from its ranges and idle tokens.
     * @param snapshot The core's snapshot.
     * @param sqrtPriceX96 The square root of the pool price (token1/token0), with 96 binary precision.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return position The equivalent position, its bound the core's nearest edge in the swap's direction.
     */
    function getPosition(Snapshot memory snapshot, uint160 sqrtPriceX96, bool zeroForOne)
        internal
        pure
        returns (EquivalentPosition memory position)
    {
        (uint256 idle0, uint256 idle1) = idle(snapshot);
        position = EquivalentPositionMath.getPosition(snapshot.ranges, sqrtPriceX96, zeroForOne, idle0, idle1);
    }

    /**
     * @notice The tokens a core holds at a price: its ranges, its buffer and its uncollected fees.
     * @param snapshot The core's snapshot.
     * @param sqrtPriceX96 The square root of the pool price (token1/token0), with 96 binary precision.
     * @return amount0 The token0, rounded down.
     * @return amount1 The token1, rounded down.
     */
    function getAmountsAt(Snapshot memory snapshot, uint160 sqrtPriceX96)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        // Cache the ranges.
        PricedRange[] memory ranges = snapshot.ranges;

        // Calculate the tokens in the ranges.
        for (uint256 i; i < ranges.length; ++i) {
            PricedRange memory range = ranges[i];
            if (range.liquidity == 0) continue;

            (uint256 range0, uint256 range1) = CLMath.getAmountsForLiquidity(
                sqrtPriceX96, range.sqrtPriceLowerX96, range.sqrtPriceUpperX96, range.liquidity
            );
            // Unchecked: at most 14 ranges of amounts below 2^192 each.
            unchecked {
                amount0 += range0;
                amount1 += range1;
            }
        }

        // Add the buffer and the uncollected fees.
        (uint256 idle0, uint256 idle1) = idle(snapshot);
        amount0 += idle0;
        amount1 += idle1;
    }

    /**
     * @notice The most a burn's or a mint's rounding moves one token's amount.
     * @param snapshot The core's snapshot.
     * @param sqrtPriceX96 The square root of the price (token1/token0) the shares are burned or minted at, with 96 binary precision.
     * @param isToken0 True for token0.
     * @return maxRounding The rounding bound, in that token.
     * @dev Per range: liquidity floor < u, amount floor < 1, second position < 1. Buffer floor < 1.
     */
    function getRounding(Snapshot memory snapshot, uint256 sqrtPriceX96, bool isToken0)
        internal
        pure
        returns (uint256 maxRounding)
    {
        // Unchecked: the core holds at most MAX_RANGE_CAP ranges and the price is a uint160 at every caller.
        unchecked {
            maxRounding = snapshot.ranges.length
                * ((isToken0 ? uint256(1 << 96).divUp(sqrtPriceX96) : sqrtPriceX96.divUp(1 << 96)) + 2) + 1;
        }
    }

    /* //////////////////////////////////////////////////////////////
                              MINT LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates what a mint of shares takes in both tokens at a price, rounded up.
     * @param snapshot The core's snapshot.
     * @param sqrtPriceX96 The square root of the pool price (token1/token0) the shares are minted at, with 96 binary precision.
     * @param shares The aLP shares minted.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return amountIn The tokenIn the mint takes.
     * @return amountOut The tokenOut the mint takes.
     * @return activeLiquidityDelta The liquidity the mint adds to the ranges the buy's first step trades against.
     */
    function getMintAmounts(Snapshot memory snapshot, uint160 sqrtPriceX96, uint256 shares, bool zeroForOne)
        internal
        pure
        returns (uint256 amountIn, uint256 amountOut, uint256 activeLiquidityDelta)
    {
        // Cache the ranges and the supply.
        PricedRange[] memory ranges = snapshot.ranges;
        uint256 supply = snapshot.supply;

        // Sum tokens the shares' liquidity takes per range, and that liquidity in ranges the buy trades against.
        uint256 amount0;
        uint256 amount1;
        // Unchecked: at most MAX_RANGE_CAP ranges of uint128 liquidity, with amounts below 2^194 each.
        unchecked {
            for (uint256 i; i < ranges.length; ++i) {
                PricedRange memory range = ranges[i];
                uint128 liquidityDelta = SafeCastLib.toUint128(uint256(range.liquidity).fullMulDivUp(shares, supply));
                (uint256 rangeAmount0, uint256 rangeAmount1) = CLMath.getAmountsForLiquidityRoundingUp(
                    sqrtPriceX96, range.sqrtPriceLowerX96, range.sqrtPriceUpperX96, liquidityDelta
                );
                amount0 += rangeAmount0;
                amount1 += rangeAmount1;
                if (zeroForOne
                        ? range.sqrtPriceLowerX96 < sqrtPriceX96 && sqrtPriceX96 <= range.sqrtPriceUpperX96
                        : range.sqrtPriceLowerX96 <= sqrtPriceX96 && sqrtPriceX96 < range.sqrtPriceUpperX96) activeLiquidityDelta += liquidityDelta;
            }
        }

        // Add the shares' pro rata part of the buffer and the fees, rounded up, and a margin of a wei per range on tokenIn.
        (uint256 idle0, uint256 idle1) = idle(snapshot);
        if (zeroForOne) idle0 += ranges.length;
        else idle1 += ranges.length;
        amount0 += idle0.fullMulDivUp(shares, supply);
        amount1 += idle1.fullMulDivUp(shares, supply);

        // Order the amounts by the swap's direction.
        (amountIn, amountOut) = zeroForOne ? (amount0, amount1) : (amount1, amount0);
    }

    /**
     * @notice Calculates the shares a balance of both tokens mints at a price.
     * @param snapshot The core's snapshot.
     * @param sqrtPriceX96 The square root of the pool price (token1/token0) the shares are minted at, with 96 binary precision.
     * @param amountIn The balance of tokenIn.
     * @param amountOut The balance of tokenOut.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return shares The aLP shares.
     */
    function getMintShares(
        Snapshot memory snapshot,
        uint160 sqrtPriceX96,
        uint256 amountIn,
        uint256 amountOut,
        bool zeroForOne
    ) internal pure returns (uint256 shares) {
        // Start the cost of the whole supply from the buffer and the fees, and a margin of a wei per range on tokenIn.
        (uint256 cost0, uint256 cost1) = idle(snapshot);
        if (zeroForOne) cost0 += snapshot.ranges.length;
        else cost1 += snapshot.ranges.length;

        // Order the balances by token, less the mint's rounding: per range a liquidity unit and its amounts' ceilings, and the idle's.
        (uint256 amount0, uint256 amount1) = zeroForOne ? (amountIn, amountOut) : (amountOut, amountIn);
        (amount0, amount1) =
        (
            amount0.zeroFloorSub(getRounding(snapshot, sqrtPriceX96, true)),
            amount1.zeroFloorSub(getRounding(snapshot, sqrtPriceX96, false))
        );

        // Cache the ranges.
        PricedRange[] memory ranges = snapshot.ranges;

        // Sum the tokens the whole supply holds per range.
        for (uint256 i; i < ranges.length; ++i) {
            PricedRange memory range = ranges[i];
            (uint256 rangeAmount0, uint256 rangeAmount1) = CLMath.getAmountsForLiquidityRoundingUp(
                sqrtPriceX96, range.sqrtPriceLowerX96, range.sqrtPriceUpperX96, range.liquidity
            );
            (cost0, cost1) = (cost0 + rangeAmount0, cost1 + rangeAmount1);
        }

        // If the supply holds no tokens, the balances mint no shares.
        if (cost0 == 0 && cost1 == 0) return 0;

        // Calculate the shares the balances mint, limited by the scarcer token.
        shares = type(uint256).max;
        if (cost0 > 0) shares = amount0.fullMulDiv(snapshot.supply, cost0);
        if (cost1 > 0) shares = FixedPointMathLib.min(shares, amount1.fullMulDiv(snapshot.supply, cost1));
    }

    /* //////////////////////////////////////////////////////////////
                              BURN LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates what a burn of shares releases in both tokens at a price, rounded down.
     * @param snapshot The core's snapshot.
     * @param sqrtPriceX96 The square root of the pool price (token1/token0) the shares are burned at, with 96 binary precision.
     * @param shares The aLP shares burned.
     * @param zeroForOne True when token0 is swapped for token1.
     * @return amountIn The tokenIn released.
     * @return amountOut The tokenOut released.
     * @return activeLiquidityDelta The liquidity the burn takes from the ranges the sale's first step trades against.
     */
    function getBurnAmounts(Snapshot memory snapshot, uint160 sqrtPriceX96, uint256 shares, bool zeroForOne)
        internal
        pure
        returns (uint256 amountIn, uint256 amountOut, uint256 activeLiquidityDelta)
    {
        // Cache the ranges.
        PricedRange[] memory ranges = snapshot.ranges;

        // Sum tokens the shares' liquidity releases per range, and that liquidity in ranges the sale trades against.
        uint256 amount0;
        uint256 amount1;
        // Unchecked: fromUnstaked is at most liquidityDelta, and each of at most MAX_RANGE_CAP ranges adds below 2^193.
        unchecked {
            for (uint256 i; i < ranges.length; ++i) {
                PricedRange memory range = ranges[i];
                uint128 liquidityDelta =
                    SafeCastLib.toUint128(uint256(range.liquidity).fullMulDiv(shares, snapshot.supply));
                if (liquidityDelta == 0) continue;
                if (zeroForOne
                        ? range.sqrtPriceLowerX96 < sqrtPriceX96 && sqrtPriceX96 <= range.sqrtPriceUpperX96
                        : range.sqrtPriceLowerX96 <= sqrtPriceX96 && sqrtPriceX96 < range.sqrtPriceUpperX96) activeLiquidityDelta += liquidityDelta;

                // The burn takes the unstaked side first, and each side releases its amounts rounded down.
                uint128 fromUnstaked = uint128(FixedPointMathLib.min(liquidityDelta, range.unstakedLiquidity));
                liquidityDelta -= fromUnstaked;
                (uint256 released0, uint256 released1) = CLMath.getAmountsForLiquidity(
                    sqrtPriceX96, range.sqrtPriceLowerX96, range.sqrtPriceUpperX96, fromUnstaked
                );
                amount0 += released0;
                amount1 += released1;
                (released0, released1) = CLMath.getAmountsForLiquidity(
                    sqrtPriceX96, range.sqrtPriceLowerX96, range.sqrtPriceUpperX96, liquidityDelta
                );
                amount0 += released0;
                amount1 += released1;
            }
        }

        // Add the shares' pro rata part of the buffer and the fees, rounded down.
        (uint256 idle0, uint256 idle1) = idle(snapshot);
        amount0 += idle0.fullMulDiv(shares, snapshot.supply);
        amount1 += idle1.fullMulDiv(shares, snapshot.supply);

        // Order the amounts by the swap's direction.
        (amountIn, amountOut) = zeroForOne ? (amount0, amount1) : (amount1, amount0);
    }
}
