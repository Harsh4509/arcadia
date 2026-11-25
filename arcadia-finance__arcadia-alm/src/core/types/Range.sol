/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @notice One tick range the core holds, with its staked liquidity and its staked and unstaked token ids.
 */
struct Range {
    int24 tickLower;
    int24 tickUpper;
    uint80 unstakedTokenId;
    uint128 stakedLiquidity;
    uint80 stakedTokenId;
    uint48 stakedBlock;
}
