/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PoolTokens, State } from "../../../src/core/types/State.sol";
import { PoolTokensLib } from "../../../src/core/libraries/state/PoolTokensLib.sol";
import { TokenAmounts, TokenDelta } from "../../../src/core/types/TokenDelta.sol";

contract PoolTokensLibExtension {
    using PoolTokensLib for TokenAmounts;

    State internal state;

    function setPoolTokens(uint128 buffer0, uint128 buffer1, uint128 protocolFees0, uint128 protocolFees1) external {
        (state.poolTokens.buffer.amount0, state.poolTokens.buffer.amount1) = (buffer0, buffer1);
        (state.poolTokens.protocolFees.amount0, state.poolTokens.protocolFees.amount1) = (protocolFees0, protocolFees1);
    }

    function setEscrowed(uint128 escrowed0, uint128 escrowed1) external {
        (state.poolTokens.escrowed.amount0, state.poolTokens.escrowed.amount1) = (escrowed0, escrowed1);
    }

    function setProtocolSwapFeeBps(uint16 protocolSwapFeeBps) external {
        state.config.protocolSwapFeeBps = protocolSwapFeeBps;
    }

    function setRewardPoolToken(uint8 rewardPoolToken, uint128 lastRewardBalance) external {
        state.config.rewardPoolToken = rewardPoolToken;
        state.rewards.lastRewardBalance = lastRewardBalance;
    }

    function getPoolTokens() external view returns (PoolTokens memory poolTokens) {
        poolTokens = state.poolTokens;
    }

    function creditCollected(TokenDelta principal, TokenDelta fees) external returns (TokenDelta delta) {
        delta = state.creditCollected(principal, fees);
    }

    function payProtocolFees(address token0, address token1, address recipient)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = state.poolTokens.protocolFees.payProtocolFees(token0, token1, recipient);
    }

    function skim(address token0, address token1) external returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = state.skim(token0, token1);
    }

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1) {
        (reserve0, reserve1) = state.poolTokens.getReserves();
    }

    function checkSolvency(address token0, address token1) external view {
        state.checkSolvency(token0, token1);
    }
}
