/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CLMath } from "../../../shared/libraries/math/CLMath.sol";
import { ConfigLib } from "./ConfigLib.sol";
import { DynamicArrayLib } from "@solady/utils/DynamicArrayLib.sol";
import { EmissionsLogic } from "../logic/EmissionsLogic.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../interfaces/IALMCoreEvents.sol";
import { IMetadexCLGauge } from "../../../interfaces/IMetadexCLGauge.sol";
import { IMetadexCLGaugeFactory } from "../../../interfaces/IMetadexCLGaugeFactory.sol";
import { IMetadexCLPositionManager } from "../../../interfaces/IMetadexCLPositionManager.sol";
import { MetadexPositionValue } from "../../../shared/libraries/vendored/MetadexPositionValue.sol";
import { PositionManagerLogic } from "../logic/PositionManagerLogic.sol";
import { Range } from "../../types/Range.sol";
import { RangeAmounts } from "../../types/RangeAmounts.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { State } from "../../types/State.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { TokenDelta, TokenDeltaLib } from "../../types/TokenDelta.sol";

/**
 * @title Ranges Library.
 * @author Pragma Labs
 * @notice The core's Metadex CL ranges, each holding an unstaked and a staked side.
 */
// forge-lint: disable-next-item(calls-loop, reentrancy-events, require-revert-in-loop, uninitialized-local, unsafe-typecast, unused-return)
library RangesLib {
    using FixedPointMathLib for uint256;
    using TokenDeltaLib for TokenDelta;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error PenaltyWindowOpen(uint256 tokenId);
    error RangeCapExceeded();
    error RangeNotStaked();
    error RangeStaked();

    /* //////////////////////////////////////////////////////////////
                                 RANGES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Opens a range by minting its unstaked side at the given ticks.
     * @param state The core state.
     * @param positionManager The Metadex CL position manager.
     * @param params The mint parameters, without recipient and deadline.
     * @return liquidity The liquidity minted.
     * @return delta The token amounts the mint consumed.
     */
    function openRange(State storage state, address positionManager, IMetadexCLPositionManager.MintParams memory params)
        internal
        returns (uint128 liquidity, TokenDelta delta)
    {
        // Checks.
        uint256 index = state.ranges.length;
        if (index >= state.config.rangeCap) revert RangeCapExceeded();

        // Mint a position for the unstaked side, at the new range's ticks.
        uint256 tokenId;
        (tokenId, liquidity, delta) = PositionManagerLogic.mint(positionManager, params);

        // Update State.
        state.ranges
            .push(
                Range({
                    stakedLiquidity: 0,
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    unstakedTokenId: SafeCastLib.toUint80(tokenId),
                    stakedTokenId: 0,
                    stakedBlock: 0
                })
            );

        emit IALMCoreEvents.RangeOpened(index, params.tickLower, params.tickUpper, tokenId, liquidity);
    }

    /**
     * @notice Burns a range, releasing its unstaked side.
     * @param state The core state.
     * @param positionManager The Metadex CL position manager.
     * @param index The index of the range.
     * @param lastIndex The index of the last range.
     * @return tickLower The lower tick of the range.
     * @return tickUpper The upper tick of the range.
     * @return liquidity The liquidity the range held.
     * @return principal The token amounts released.
     * @return fees The accrued fees collected, before the protocol share.
     */
    function closeRange(State storage state, address positionManager, uint256 index, uint256 lastIndex)
        internal
        returns (int24 tickLower, int24 tickUpper, uint128 liquidity, TokenDelta principal, TokenDelta fees)
    {
        // Checks.
        Range[] storage ranges = state.ranges;
        uint256 tokenId;
        {
            Range storage range = ranges[index];
            if (range.stakedTokenId != 0) revert RangeStaked();

            (tickLower, tickUpper) = (range.tickLower, range.tickUpper);
            tokenId = range.unstakedTokenId;
        }

        // If the unstaked side holds liquidity, remove it and collect its fees, else collect only its fees.
        liquidity = IMetadexCLPositionManager(positionManager).positions(tokenId).liquidity;
        if (liquidity > 0) {
            IMetadexCLPositionManager.DecreaseLiquidityParams memory params;
            (params.tokenId, params.liquidity) = (tokenId, liquidity);
            (principal, fees) = PositionManagerLogic.decreaseLiquidityAndCollect(positionManager, params);
        } else {
            IMetadexCLPositionManager.CollectParams memory params;
            params.tokenId = tokenId;
            fees = PositionManagerLogic.collect(positionManager, params);
        }

        // Burn the unstaked side's position.
        IMetadexCLPositionManager(positionManager).burn(tokenId);

        // Update State.
        if (index != lastIndex) ranges[index] = ranges[lastIndex];
        ranges.pop();

        emit IALMCoreEvents.RangeClosed(index, tokenId);
    }

    /**
     * @notice Mints the staked side of a range and stakes it.
     * @param state The core state.
     * @param positionManager The Metadex CL position manager.
     * @param index The index of the range.
     * @param gauge The CL gauge of the pool.
     * @param params The mint parameters, without ticks, recipient and deadline.
     * @param config The penalty configuration of the gauge.
     * @return liquidity The liquidity minted.
     * @return delta The token amounts the mint consumed.
     */
    function mintStaked(
        State storage state,
        address positionManager,
        uint256 index,
        address gauge,
        IMetadexCLPositionManager.MintParams memory params,
        IMetadexCLGaugeFactory.PenaltyConfig memory config
    ) internal returns (uint128 liquidity, TokenDelta delta) {
        // Checks.
        Range storage range = state.ranges[index];
        if (range.stakedTokenId != 0) revert RangeStaked();

        // Mint a position for the staked side, at the range's ticks.
        (params.tickLower, params.tickUpper) = (range.tickLower, range.tickUpper);
        uint256 tokenId;
        (tokenId, liquidity, delta) = PositionManagerLogic.mint(positionManager, params);

        // Update State.
        range.stakedTokenId = SafeCastLib.toUint80(tokenId);
        // Unchecked: a range without a staked side holds no staked liquidity.
        unchecked {
            range.stakedLiquidity += liquidity;
        }

        // Deposit the staked side in the gauge.
        stake(state, range, positionManager, gauge, tokenId, config);

        emit IALMCoreEvents.Staked(index, tokenId, liquidity);
    }

    /**
     * @notice Adds liquidity to the staked side of a range.
     * @param state The core state.
     * @param positionManager The Metadex CL position manager.
     * @param index The index of the range.
     * @param gauge The CL gauge of the pool.
     * @param params The increase parameters, without token id and deadline.
     * @param windowOpen True when the staked side sits inside its penalty window and the caller did not accept it.
     * @param config The penalty configuration of the gauge.
     * @return liquidity The liquidity added.
     * @return delta The token amounts the add consumed.
     */
    function increaseStakedLiquidity(
        State storage state,
        address positionManager,
        uint256 index,
        address gauge,
        IMetadexCLPositionManager.IncreaseLiquidityParams memory params,
        bool windowOpen,
        IMetadexCLGaugeFactory.PenaltyConfig memory config
    ) internal returns (uint128 liquidity, TokenDelta delta) {
        // Checks.
        Range storage range = state.ranges[index];
        uint256 tokenId = range.stakedTokenId;
        if (tokenId == 0) revert RangeNotStaked();
        if (windowOpen) revert PenaltyWindowOpen(tokenId);

        // Withdraw the staked side from the gauge.
        unstake(gauge, tokenId);

        // Add liquidity to the staked side's position.
        params.tokenId = tokenId;
        (liquidity, delta) = PositionManagerLogic.increaseLiquidity(positionManager, params);

        // Update State.
        // Unchecked: the staked side is a position on the range's ticks, within the pool's max liquidity per tick.
        unchecked {
            range.stakedLiquidity += liquidity;
        }

        // Deposit the staked side in the gauge.
        stake(state, range, positionManager, gauge, tokenId, config);

        emit IALMCoreEvents.Staked(index, tokenId, liquidity);
    }

    /**
     * @notice Removes liquidity from the staked side of a range and collects what it accrued, burning a drained side.
     * @param state The core state.
     * @param positionManager The Metadex CL position manager.
     * @param index The index of the range.
     * @param gauge The CL gauge of the pool.
     * @param params The decrease parameters, without token id and deadline.
     * @param windowOpen True when the staked side sits inside its penalty window and the caller did not accept it.
     * @param emergency True to take the whole staked side out through the gauge's emergency withdraw, without a claim.
     * @param config The penalty configuration of the gauge.
     * @return principal The token amounts released.
     * @return fees The accrued fees collected, before the protocol share.
     */
    function decreaseStakedLiquidity(
        State storage state,
        address positionManager,
        uint256 index,
        address gauge,
        IMetadexCLPositionManager.DecreaseLiquidityParams memory params,
        bool windowOpen,
        bool emergency,
        IMetadexCLGaugeFactory.PenaltyConfig memory config
    ) internal returns (TokenDelta principal, TokenDelta fees) {
        // Checks.
        Range storage range = state.ranges[index];
        uint256 tokenId = range.stakedTokenId;
        if (tokenId == 0) revert RangeNotStaked();
        if (windowOpen) revert PenaltyWindowOpen(tokenId);

        // Withdraw the staked side from the gauge, in emergency mode all of it and without a claim.
        if (emergency) {
            params.liquidity = range.stakedLiquidity;
            IMetadexCLGauge(gauge).emergencyWithdraw(tokenId);
        } else {
            unstake(gauge, tokenId);
        }

        // Remove liquidity from the staked side's position and collect its fees.
        params.tokenId = tokenId;
        (principal, fees) = PositionManagerLogic.decreaseLiquidityAndCollect(positionManager, params);

        // Update State.
        uint128 stakedLiquidity = range.stakedLiquidity - params.liquidity;
        range.stakedLiquidity = stakedLiquidity;

        // If the staked side is drained, burn its position, else deposit the staked side in the gauge.
        if (stakedLiquidity == 0) {
            IMetadexCLPositionManager(positionManager).burn(tokenId);
            range.stakedTokenId = 0;

            emit IALMCoreEvents.Unstaked(index, tokenId);
        } else {
            stake(state, range, positionManager, gauge, tokenId, config);
        }
    }

    /**
     * @notice Deposits a range's staked side in the gauge and starts its penalty window.
     * @param state The core state.
     * @param range The range.
     * @param positionManager The Metadex CL position manager.
     * @param gauge The CL gauge of the pool.
     * @param tokenId The token id of the staked side.
     * @param config The penalty configuration of the gauge.
     */
    function stake(
        State storage state,
        Range storage range,
        address positionManager,
        address gauge,
        uint256 tokenId,
        IMetadexCLGaugeFactory.PenaltyConfig memory config
    ) internal {
        // Deposit the staked side in the gauge.
        IMetadexCLPositionManager(positionManager).approve(gauge, tokenId);
        IMetadexCLGauge(gauge).deposit(tokenId);

        // Update State.
        uint256 blockNumber = EmissionsLogic.getBlockNumber(state.config.arbBlockNumber);
        range.stakedBlock = SafeCastLib.toUint48(blockNumber);

        // If the gauge penalises an early unstake, extend the window end to this stake's window.
        if (config.penaltyRate == 0 || config.minStakeBlocks == 0) return;
        uint256 windowEnd = blockNumber + config.minStakeBlocks;
        if (windowEnd > state.config.windowEnd) state.config.windowEnd = uint48(windowEnd);
    }

    /**
     * @notice Withdraws a range's staked side from the gauge.
     * @param gauge The CL gauge of the pool.
     * @param tokenId The token id of the staked side.
     */
    function unstake(address gauge, uint256 tokenId) internal {
        // Withdraw the staked side from the gauge.
        IMetadexCLGauge(gauge).withdraw(tokenId);
    }

    /**
     * @notice Collects the accrued fees of every range with unstaked liquidity, and sums every range's principal.
     * @param state The core state.
     * @param positionManager The Metadex CL position manager.
     * @param sqrtPriceX96 The price the principal is computed at.
     * @return fees The accrued fees collected, before the protocol share.
     * @return amount0 The token0 principal of every range.
     * @return amount1 The token1 principal of every range.
     */
    function collectFees(State storage state, address positionManager, uint160 sqrtPriceX96)
        internal
        returns (TokenDelta fees, uint256 amount0, uint256 amount1)
    {
        Range[] storage ranges = state.ranges;
        uint256 length = ranges.length;
        IMetadexCLPositionManager.CollectParams memory params;
        for (uint256 i; i < length; ++i) {
            // If the range has no liquidity, skip it.
            Range storage range = unsafeAccess(ranges, i);
            uint128 unstakedLiquidity =
                IMetadexCLPositionManager(positionManager).positions(range.unstakedTokenId).liquidity;
            uint128 liquidity;
            // Unchecked: both sides are positions on the range's ticks, within the pool's max liquidity per tick.
            unchecked {
                liquidity = unstakedLiquidity + range.stakedLiquidity;
            }
            if (liquidity == 0) continue;

            // Calculate the range's principal (both sides, at the given price) and add it to the totals.
            {
                (uint256 rangeAmount0, uint256 rangeAmount1) =
                    CLMath.getPrincipalAmounts(sqrtPriceX96, range.tickLower, range.tickUpper, liquidity);
                // Unchecked: each range's amounts are below 2^224 and there are at most MAX_RANGE_CAP ranges.
                unchecked {
                    amount0 += rangeAmount0;
                    amount1 += rangeAmount1;
                }
            }

            // If the unstaked side has no liquidity, skip its fee collection.
            if (unstakedLiquidity == 0) continue;

            // Collect the fees of the unstaked side.
            params.tokenId = range.unstakedTokenId;
            fees = fees.add(PositionManagerLogic.collect(positionManager, params));
        }
    }

    /* //////////////////////////////////////////////////////////////
                                PRO RATA
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Adds every range's pro-rata share of a mint to its unstaked side, out of what the caller already paid in.
     * @param state The core state.
     * @param positionManager The Metadex CL position manager.
     * @param mintAmounts Every range's most amounts the position manager may take for its liquidity owed.
     * @return delta The token amounts the adds consumed.
     */
    function addLiquidity(State storage state, address positionManager, RangeAmounts[] memory mintAmounts)
        internal
        returns (TokenDelta delta)
    {
        uint256 length = mintAmounts.length;
        IMetadexCLPositionManager.IncreaseLiquidityParams memory params;
        for (uint256 i; i < length; ++i) {
            // If the range is owed no liquidity, skip it.
            RangeAmounts memory rangeAmounts = mintAmounts[i];
            if ((rangeAmounts.amount0 | rangeAmounts.amount1) == 0) continue;

            // Add the range's owed liquidity to the unstaked side.
            (params.amount0Desired, params.amount1Desired) = (rangeAmounts.amount0, rangeAmounts.amount1);
            params.tokenId = state.ranges[i].unstakedTokenId;
            (, TokenDelta rangeDelta) = PositionManagerLogic.increaseLiquidity(positionManager, params);

            // Add the consumed amounts to the totals.
            delta = delta.add(rangeDelta);
        }
    }

    /**
     * @notice Removes every range's pro-rata share of a burn, unstaked side first, and collects every range's fees.
     * @param state The core state.
     * @param positionManager The Metadex CL position manager.
     * @param gauge The CL gauge of the pool.
     * @param gaugeFactory The factory that created the gauge.
     * @param shares The aLP shares burned.
     * @param supplyBefore The aLP supply before this burn.
     * @return principal The token amounts released.
     * @return fees The accrued fees collected, before the protocol share.
     */
    function removeLiquidity(
        State storage state,
        address positionManager,
        address gauge,
        address gaugeFactory,
        uint256 shares,
        uint256 supplyBefore
    ) internal returns (TokenDelta principal, TokenDelta fees) {
        // Get the gauge's penalty configuration.
        IMetadexCLGaugeFactory.PenaltyConfig memory penalty = EmissionsLogic.getPenaltyConfig(gaugeFactory, gauge);

        // Cache the number of ranges.
        uint256 length = state.ranges.length;
        for (uint256 i; i < length; ++i) {
            // Calculate the range's liquidity the burn removes, pro rata to the shares, and its split per side.
            uint128 fromStaked;
            {
                uint128 fromUnstaked;
                {
                    uint128 unstakedLiquidity;
                    {
                        Range storage range = unsafeAccess(state.ranges, i);
                        unstakedLiquidity =
                        IMetadexCLPositionManager(positionManager).positions(range.unstakedTokenId).liquidity;
                        // Unchecked: both liquidities are uint128 values.
                        unchecked {
                            fromUnstaked = SafeCastLib.toUint128(
                                (uint256(unstakedLiquidity) + range.stakedLiquidity).fullMulDiv(shares, supplyBefore)
                            );
                        }
                    }

                    // If the burn removes no liquidity from the range, collect its unstaked side's fees and skip it.
                    if (fromUnstaked == 0) {
                        if (unstakedLiquidity > 0) {
                            IMetadexCLPositionManager.CollectParams memory params;
                            params.tokenId = unsafeAccess(state.ranges, i).unstakedTokenId;
                            fees = fees.add(PositionManagerLogic.collect(positionManager, params));
                        }
                        continue;
                    }

                    if (fromUnstaked > unstakedLiquidity) {
                        // Unchecked: the check above bounds unstakedLiquidity by fromUnstaked.
                        unchecked {
                            fromStaked = fromUnstaked - unstakedLiquidity;
                        }
                        fromUnstaked = unstakedLiquidity;
                    }
                }

                // Remove the unstaked side's part and add what it releases to the totals.
                if (fromUnstaked > 0) {
                    IMetadexCLPositionManager.DecreaseLiquidityParams memory params;
                    (params.tokenId, params.liquidity) = (unsafeAccess(state.ranges, i).unstakedTokenId, fromUnstaked);
                    (TokenDelta rangePrincipal, TokenDelta rangeFees) =
                        PositionManagerLogic.decreaseLiquidityAndCollect(positionManager, params);
                    (principal, fees) = (principal.add(rangePrincipal), fees.add(rangeFees));
                }
            }

            // Remove the staked side's part and add what it releases to the totals.
            if (fromStaked > 0) {
                (TokenDelta rangePrincipal, TokenDelta rangeFees) = decreaseStakedLiquidity(
                    state,
                    positionManager,
                    i,
                    gauge,
                    IMetadexCLPositionManager.DecreaseLiquidityParams({
                        tokenId: 0, liquidity: fromStaked, amount0Min: 0, amount1Min: 0, deadline: 0
                    }),
                    false,
                    false,
                    penalty
                );
                (principal, fees) = (principal.add(rangePrincipal), fees.add(rangeFees));
            }
        }
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The unstaked sides' liquidity and their uncollected fees, net of the protocol share.
     * @param ranges The ranges.
     * @param bps The protocol share of collected swap fees.
     * @param pool The Metadex CL pool.
     * @param positionManager The Metadex CL position manager.
     * @return fees0 The token0 fees.
     * @return fees1 The token1 fees.
     * @return positionLiquidity Every unstaked side's liquidity.
     */
    function getUnstakedPositions(Range[] storage ranges, uint256 bps, address pool, address positionManager)
        internal
        view
        returns (uint256 fees0, uint256 fees1, uint128[] memory positionLiquidity)
    {
        uint256 length = ranges.length;
        positionLiquidity = new uint128[](length);
        for (uint256 i; i < length; ++i) {
            // If the range has no unstaked liquidity, skip it.
            IMetadexCLPositionManager.Position memory position =
                IMetadexCLPositionManager(positionManager).positions(unsafeAccess(ranges, i).unstakedTokenId);
            if (position.liquidity == 0) continue;
            positionLiquidity[i] = position.liquidity;

            // Add the unstaked side's uncollected fees to the totals.
            (uint256 gross0, uint256 gross1) = MetadexPositionValue.fees(pool, position);
            fees0 += gross0;
            fees1 += gross1;
        }

        // Subtract the protocol share, floored once on the totals.
        // Unchecked: the protocol fee is at most half of the gross fees.
        unchecked {
            fees0 -= fees0.fullMulDiv(bps, ConfigLib.BPS_DENOMINATOR);
            fees1 -= fees1.fullMulDiv(bps, ConfigLib.BPS_DENOMINATOR);
        }
    }

    /**
     * @notice What every range's pro-rata share of a mint requires, in both tokens.
     * @param ranges The ranges.
     * @param positionLiquidity Every unstaked side's liquidity.
     * @param sqrtPriceX96 The pool's spot price.
     * @param shares The aLP shares minted.
     * @param supplyBefore The aLP supply before this mint.
     * @return amount0Desired The most token0 the position manager may take.
     * @return amount1Desired The most token1 the position manager may take.
     * @return mintAmounts Every range's most amounts the position manager may take for its liquidity owed.
     */
    function getMintAmounts(
        Range[] storage ranges,
        uint128[] memory positionLiquidity,
        uint160 sqrtPriceX96,
        uint256 shares,
        uint256 supplyBefore
    ) internal view returns (uint256 amount0Desired, uint256 amount1Desired, RangeAmounts[] memory mintAmounts) {
        uint256 length = ranges.length;
        mintAmounts = new RangeAmounts[](length);
        for (uint256 i; i < length; ++i) {
            // Get the range's ticks and the liquidity of both sides.
            int24 tickLower;
            int24 tickUpper;
            uint256 rangeLiquidity;
            // Unchecked: both liquidities are uint128 values.
            unchecked {
                Range storage range = unsafeAccess(ranges, i);
                (tickLower, tickUpper, rangeLiquidity) =
                (range.tickLower, range.tickUpper, uint256(positionLiquidity[i]) + range.stakedLiquidity);
            }

            // Calculate the most amounts the range may take for its liquidity owed for the minted shares.
            RangeAmounts memory rangeAmounts = mintAmounts[i];
            (rangeAmounts.amount0, rangeAmounts.amount1) = CLMath.getMintAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                rangeLiquidity,
                shares,
                supplyBefore
            );

            // Add the range's amounts to the desired totals.
            // Unchecked: each range's amounts are below 2^224 and there are at most MAX_RANGE_CAP ranges.
            unchecked {
                amount0Desired += rangeAmounts.amount0;
                amount1Desired += rangeAmounts.amount1;
            }
        }
    }

    /**
     * @notice Every token id the core has staked.
     * @param ranges The core's ranges.
     * @return tokenIds The staked token ids.
     */
    function stakedTokenIds(Range[] storage ranges) internal view returns (uint256[] memory tokenIds) {
        uint256 length = ranges.length;
        tokenIds = new uint256[](length);

        uint256 count;
        for (uint256 i; i < length; ++i) {
            uint256 tokenId = unsafeAccess(ranges, i).stakedTokenId;
            if (tokenId == 0) continue;

            tokenIds[count] = tokenId;
            // Unchecked: the count is at most the index.
            unchecked {
                ++count;
            }
        }

        tokenIds = DynamicArrayLib.truncate(tokenIds, count);
    }

    /**
     * @notice The staked ranges outside their penalty window.
     * @param ranges The core's ranges.
     * @param gauge The CL gauge the ranges are staked in.
     * @param gaugeFactory The factory that holds the gauge's penalty configuration.
     * @param blockNumber The gauge's current block number.
     * @return tokenIds The staked token ids outside their penalty window.
     * @return skipped True when a staked token id is inside its penalty window.
     */
    function claimableTokenIds(Range[] storage ranges, address gauge, address gaugeFactory, uint256 blockNumber)
        internal
        view
        returns (uint256[] memory tokenIds, bool skipped)
    {
        uint256 length = ranges.length;
        tokenIds = new uint256[](length);
        IMetadexCLGaugeFactory.PenaltyConfig memory config;
        bool configRead;

        uint256 count;
        for (uint256 i; i < length; ++i) {
            Range storage range = unsafeAccess(ranges, i);
            uint256 tokenId = range.stakedTokenId;
            if (tokenId == 0) continue;
            if (!configRead) {
                config = EmissionsLogic.getPenaltyConfig(gaugeFactory, gauge);
                configRead = true;
            }
            if (EmissionsLogic.isPenaltyWindowOpen(range.stakedBlock, config, blockNumber)) {
                skipped = true;
                continue;
            }

            tokenIds[count] = tokenId;
            // Unchecked: the count is at most the index.
            unchecked {
                ++count;
            }
        }

        tokenIds = DynamicArrayLib.truncate(tokenIds, count);
    }

    /**
     * @notice A range by index, without reading the array length to bound it.
     * @param ranges The ranges.
     * @param index The index of the range, below the array length.
     * @return range The range.
     */
    function unsafeAccess(Range[] storage ranges, uint256 index) internal pure returns (Range storage range) {
        assembly ("memory-safe") {
            mstore(0x00, ranges.slot)
            range.slot := add(keccak256(0x00, 0x20), shl(1, index))
        }
    }
}
