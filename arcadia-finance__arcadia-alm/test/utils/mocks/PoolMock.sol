/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { TickBitmap } from "@uniswap/v4-core/src/libraries/TickBitmap.sol";

contract PoolMock {
    int24 public tickSpacing;
    uint128 public liquidity;
    uint24 public unstakedFee;

    mapping(int16 wordPosition => uint256 word) public tickBitmap;
    mapping(int24 tick => uint128 liquidityGross) internal liquidityGrosses;
    mapping(int24 tick => int128 liquidityNet) internal liquidityNets;
    mapping(int24 tick => int128 stakedLiquidityNet) internal stakedLiquidityNets;

    constructor(int24 tickSpacing_, uint128 liquidity_) {
        (tickSpacing, liquidity) = (tickSpacing_, liquidity_);
    }

    function addLiquidityNet(int24 tick, int128 liquidityNet) external {
        liquidityNets[tick] += liquidityNet;
        liquidityGrosses[tick] += uint128(FixedPointMathLib.abs(liquidityNet));
        if (liquidityGrosses[tick] == 0) return;
        (int16 wordPosition, uint8 bitPosition) = TickBitmap.position(tick / tickSpacing);
        tickBitmap[wordPosition] |= uint256(1) << bitPosition;
    }

    function addStakedLiquidityNet(int24 tick, int128 stakedLiquidityNet) external {
        stakedLiquidityNets[tick] += stakedLiquidityNet;
    }

    function setUnstakedFee(uint24 unstakedFee_) external {
        unstakedFee = unstakedFee_;
    }

    function ticks(int24 tick)
        external
        view
        returns (uint128, int128, int128, uint256, uint256, uint256, int56, uint160, uint32, bool)
    {
        uint128 liquidityGross = liquidityGrosses[tick];
        return (liquidityGross, liquidityNets[tick], stakedLiquidityNets[tick], 0, 0, 0, 0, 0, 0, liquidityGross != 0);
    }
}
