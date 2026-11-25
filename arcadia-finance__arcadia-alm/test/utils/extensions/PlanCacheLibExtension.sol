/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CoreImmutables } from "../../../src/core/types/CoreImmutables.sol";
import { PlanCache, PlanCacheLib } from "../../../src/core/types/PlanCache.sol";
import { State } from "../../../src/core/types/State.sol";
import { TokenDelta } from "../../../src/core/types/TokenDelta.sol";

contract PlanCacheLibExtension {
    State internal state;
    CoreImmutables internal immutables;

    function setBuffers(uint128 buffer0, uint128 buffer1) external {
        (state.poolTokens.buffer.amount0, state.poolTokens.buffer.amount1) = (buffer0, buffer1);
    }

    function setImmutables(CoreImmutables memory immutables_) external {
        immutables = immutables_;
    }

    function setMaxShortfallBps(uint16 maxShortfallBps) external {
        state.config.maxShortfallBps = maxShortfallBps;
    }

    function start(
        uint160 trustedSqrtPriceX96,
        uint160 spotSqrtPriceX96,
        uint256 supplyBefore,
        uint256 amount0,
        uint256 amount1
    ) external view returns (PlanCache memory cache) {
        cache = PlanCacheLib.start(
            state, immutables, trustedSqrtPriceX96, spotSqrtPriceX96, supplyBefore, amount0, amount1
        );
    }

    function checkShortfall(PlanCache memory cache, uint256 valueAfter, uint256 supplyAfter) external view {
        cache.checkShortfall(state.config, valueAfter, supplyAfter);
    }

    function applyBufferDelta(PlanCache memory cache, TokenDelta delta) external pure returns (PlanCache memory) {
        cache.applyBufferDelta(delta);
        return cache;
    }

    function applyLiquidityDelta(PlanCache memory cache, int24 tickLower, int24 tickUpper, int256 liquidityDelta)
        external
        pure
        returns (PlanCache memory)
    {
        cache.applyLiquidityDelta(tickLower, tickUpper, liquidityDelta);
        return cache;
    }

    function openRange(PlanCache memory cache, uint256 index) external pure returns (PlanCache memory) {
        cache.openRange(index);
        return cache;
    }

    function closeRange(PlanCache memory cache, uint256 index, uint256 lastIndex)
        external
        pure
        returns (PlanCache memory)
    {
        cache.closeRange(index, lastIndex);
        return cache;
    }

    function isOpenedRange(PlanCache memory cache, uint256 index) external pure returns (bool opened) {
        opened = cache.isOpenedRange(index);
    }

    function hasUnsettledEpochs(PlanCache memory cache) external pure returns (bool unsettled) {
        unsettled = cache.hasUnsettledEpochs();
    }

    function getCleared(PlanCache memory cache, bool isDeposit, bool isToken0) external pure returns (uint256 cleared) {
        cleared = cache.getCleared(isDeposit, isToken0);
    }

    function setCleared(PlanCache memory cache, bool isDeposit, bool isToken0, uint256 cleared)
        external
        pure
        returns (PlanCache memory)
    {
        cache.setCleared(isDeposit, isToken0, cleared);
        return cache;
    }

    function getValueAfter(PlanCache memory cache) external pure returns (uint256 valueAfter) {
        valueAfter = cache.getValueAfter();
    }

    function getValue(uint160 trustedSqrtPriceX96, int256 amount0, int256 amount1, bool roundUp)
        external
        pure
        returns (uint256 value)
    {
        value = PlanCacheLib.getValue(trustedSqrtPriceX96, amount0, amount1, roundUp);
    }

    function getOwed(PlanCache memory cache) external pure returns (uint256 owed0, uint256 owed1) {
        (owed0, owed1) = cache.getOwed();
    }

    function getSettlementAmountsOut(PlanCache memory cache)
        external
        pure
        returns (uint256 shares0, uint256 shares1, uint256 assets0, uint256 assets1)
    {
        (shares0, shares1, assets0, assets1) = cache.getSettlementAmountsOut();
    }

    function getLevies(
        uint256 depositIn,
        uint256 depositOut,
        uint256 redeemOut,
        uint256 redeemIn,
        uint256 swapCost,
        uint256 swapped,
        uint256 heldIn,
        uint256 heldOut
    ) external pure returns (uint256 depositLevy, uint256 redeemLevy) {
        (depositLevy, redeemLevy) = PlanCacheLib.getLevies(
            depositIn, depositOut, redeemOut, redeemIn, swapCost, swapped, heldIn, heldOut
        );
    }
}
