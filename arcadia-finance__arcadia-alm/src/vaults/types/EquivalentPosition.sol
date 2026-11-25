/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice The one position whose token amounts equal those of every range and the buffer together.
 */
struct EquivalentPosition {
    // The liquidity of the ranges in range in the direction of the swap.
    uint256 liquidity;
    // The unstaked part of that liquidity, which earns the swap's fees.
    uint256 unstakedLiquidity;
    // amount0 is liquidity * Q96 / sqrtPrice - constant0.
    int256 constant0;
    // amount1 is liquidity * sqrtPrice / Q96 - constant1.
    int256 constant1;
    // The nearest range edge in the direction of the swap, where the position stops holding.
    uint160 sqrtPriceBound;
}
