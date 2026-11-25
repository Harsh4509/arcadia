/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EmissionsLogic } from "../../../src/core/libraries/logic/EmissionsLogic.sol";
import { IMetadexCLGaugeFactory } from "../../../src/interfaces/IMetadexCLGaugeFactory.sol";
import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";
import { PoolTokens, State } from "../../../src/core/types/State.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RangeAmounts } from "../../../src/core/types/RangeAmounts.sol";
import { RangesLib } from "../../../src/core/libraries/state/RangesLib.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { TokenDelta } from "../../../src/core/types/TokenDelta.sol";

contract RangesLibExtension {
    using RangesLib for Range[];
    using SafeTransferLib for address;

    address internal immutable POSITION_MANAGER;
    address internal immutable POOL;
    address internal immutable GAUGE;
    address internal immutable GAUGE_FACTORY;
    address internal immutable TOKEN0;
    address internal immutable TOKEN1;
    int24 internal immutable TICK_SPACING;

    State internal state;

    constructor(
        address positionManager,
        address pool,
        address gauge,
        address gaugeFactory,
        address token0,
        address token1,
        int24 tickSpacing
    ) {
        POSITION_MANAGER = positionManager;
        POOL = pool;
        GAUGE = gauge;
        GAUGE_FACTORY = gaugeFactory;
        TOKEN0 = token0;
        TOKEN1 = token1;
        TICK_SPACING = tickSpacing;
        token0.safeApproveWithRetry(positionManager, type(uint256).max);
        token1.safeApproveWithRetry(positionManager, type(uint256).max);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4 selector) {
        selector = this.onERC721Received.selector;
    }

    function pushRange(Range memory range) external {
        state.ranges.push(range);
    }

    function getRange(uint256 index) external view returns (Range memory range) {
        range = state.ranges[index];
    }

    function getRangesLength() external view returns (uint256 length) {
        length = state.ranges.length;
    }

    function setRangeCap(uint8 rangeCap) external {
        state.config.rangeCap = rangeCap;
    }

    function setProtocolSwapFeeBps(uint16 protocolSwapFeeBps) external {
        state.config.protocolSwapFeeBps = protocolSwapFeeBps;
    }

    function setBuffers(uint128 buffer0, uint128 buffer1) external {
        (state.poolTokens.buffer.amount0, state.poolTokens.buffer.amount1) = (buffer0, buffer1);
    }

    function getPoolTokens() external view returns (PoolTokens memory poolTokens) {
        poolTokens = state.poolTokens;
    }

    function getWindowEnd() external view returns (uint48 windowEnd) {
        windowEnd = state.config.windowEnd;
    }

    function setWindowEnd(uint48 windowEnd) external {
        state.config.windowEnd = windowEnd;
    }

    function getPreCredited() external view returns (uint128 preCredited) {
        preCredited = state.rewards.preCredited;
    }

    function setPreCredited(uint128 preCredited) external {
        state.rewards.preCredited = preCredited;
    }

    function openRange(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint128 liquidity, TokenDelta delta) {
        IMetadexCLPositionManager.MintParams memory params;
        (params.token0, params.token1, params.tickSpacing, params.tickLower, params.tickUpper) =
        (TOKEN0, TOKEN1, TICK_SPACING, tickLower, tickUpper);
        (params.amount0Desired, params.amount1Desired, params.amount0Min, params.amount1Min) =
        (amount0Desired, amount1Desired, amount0Min, amount1Min);
        (liquidity, delta) = state.openRange(POSITION_MANAGER, params);
    }

    function closeRange(uint256 index)
        external
        returns (int24 tickLower, int24 tickUpper, uint128 liquidity, TokenDelta principal, TokenDelta fees)
    {
        (tickLower, tickUpper, liquidity, principal, fees) =
            state.closeRange(POSITION_MANAGER, index, state.ranges.length - 1);
    }

    function mintStaked(uint256 index, uint256 amount0Desired, uint256 amount1Desired)
        external
        returns (uint128 liquidity, TokenDelta delta)
    {
        IMetadexCLPositionManager.MintParams memory params;
        (params.token0, params.token1, params.tickSpacing) = (TOKEN0, TOKEN1, TICK_SPACING);
        (params.amount0Desired, params.amount1Desired) = (amount0Desired, amount1Desired);
        (liquidity, delta) = state.mintStaked(POSITION_MANAGER, index, GAUGE, params, penaltyConfig());
    }

    function increaseStakedLiquidity(uint256 index, uint256 amount0Desired, uint256 amount1Desired, bool windowOpen)
        external
        returns (uint128 liquidity, TokenDelta delta)
    {
        IMetadexCLPositionManager.IncreaseLiquidityParams memory params;
        (params.amount0Desired, params.amount1Desired) = (amount0Desired, amount1Desired);
        (liquidity, delta) =
            state.increaseStakedLiquidity(POSITION_MANAGER, index, GAUGE, params, windowOpen, penaltyConfig());
    }

    function decreaseStakedLiquidity(uint256 index, uint128 liquidity, bool windowOpen)
        external
        returns (TokenDelta principal, TokenDelta fees)
    {
        IMetadexCLPositionManager.DecreaseLiquidityParams memory params;
        params.liquidity = liquidity;
        (principal, fees) =
            state.decreaseStakedLiquidity(POSITION_MANAGER, index, GAUGE, params, windowOpen, false, penaltyConfig());
    }

    function decreaseStakedLiquidity(uint256 index, uint128 liquidity, bool windowOpen, bool emergency)
        external
        returns (TokenDelta principal, TokenDelta fees, uint128 liquidityRemoved)
    {
        IMetadexCLPositionManager.DecreaseLiquidityParams memory params;
        params.liquidity = liquidity;
        (principal, fees) = state.decreaseStakedLiquidity(
            POSITION_MANAGER, index, GAUGE, params, windowOpen, emergency, penaltyConfig()
        );
        liquidityRemoved = params.liquidity;
    }

    function stake(uint256 index, uint256 tokenId) external {
        state.stake(state.ranges[index], POSITION_MANAGER, GAUGE, tokenId, penaltyConfig());
    }

    function penaltyConfig() internal view returns (IMetadexCLGaugeFactory.PenaltyConfig memory config) {
        config = IMetadexCLGaugeFactory(GAUGE_FACTORY).effectivePenaltyConfig(GAUGE);
    }

    function unstake(uint256 tokenId) external {
        RangesLib.unstake(GAUGE, tokenId);
    }

    function addLiquidity(RangeAmounts[] memory mintAmounts) external returns (TokenDelta delta) {
        delta = state.addLiquidity(POSITION_MANAGER, mintAmounts);
    }

    function removeLiquidity(uint256 shares, uint256 supplyBefore)
        external
        returns (TokenDelta principal, TokenDelta fees)
    {
        (principal, fees) = state.removeLiquidity(POSITION_MANAGER, GAUGE, GAUGE_FACTORY, shares, supplyBefore);
    }

    function getUnstakedPositions(uint256 bps)
        external
        view
        returns (uint256 fees0, uint256 fees1, uint128[] memory positionLiquidity)
    {
        (fees0, fees1, positionLiquidity) = state.ranges.getUnstakedPositions(bps, POOL, POSITION_MANAGER);
    }

    function collectFees(uint160 sqrtPriceX96) external returns (TokenDelta fees, uint256 amount0, uint256 amount1) {
        (fees, amount0, amount1) = state.collectFees(POSITION_MANAGER, sqrtPriceX96);
    }

    function stakedTokenIds() external view returns (uint256[] memory tokenIds) {
        tokenIds = state.ranges.stakedTokenIds();
    }

    function setArbBlockNumber(bool arbBlockNumber) external {
        state.config.arbBlockNumber = arbBlockNumber;
    }

    function claimableTokenIds(address gauge, address gaugeFactory)
        external
        view
        returns (uint256[] memory tokenIds, bool skipped)
    {
        (tokenIds, skipped) = state.ranges
            .claimableTokenIds(gauge, gaugeFactory, EmissionsLogic.getBlockNumber(state.config.arbBlockNumber));
    }

    function getMintAmounts(uint128[] memory positionLiquidity, uint160 sqrtPriceX96, uint256 shares, uint256 supply)
        external
        view
        returns (uint256 amount0Desired, uint256 amount1Desired, RangeAmounts[] memory mintAmounts)
    {
        (amount0Desired, amount1Desired, mintAmounts) =
            state.ranges.getMintAmounts(positionLiquidity, sqrtPriceX96, shares, supply);
    }

    function unsafeAccess(uint256 index) external view returns (Range memory range) {
        range = state.ranges.unsafeAccess(index);
    }
}
