/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice A range's whole liquidity and the sqrt prices at its ticks.
 */
struct PricedRange {
    uint128 liquidity;
    uint128 unstakedLiquidity;
    uint160 sqrtPriceLowerX96;
    uint160 sqrtPriceUpperX96;
}
