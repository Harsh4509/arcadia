/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ConfigLib } from "./ConfigLib.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../interfaces/IALMCoreEvents.sol";
import { PoolTokens, State } from "../../types/State.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { TokenAmounts, TokenDelta, TokenDeltaLib } from "../../types/TokenDelta.sol";

/**
 * @title PoolTokens Library.
 * @author Pragma Labs
 * @notice The token0 and token1 of a core: its buffer, the protocol fees and the escrow of the requests.
 */
library PoolTokensLib {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for address;
    using TokenDeltaLib for TokenDelta;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error AccountingMismatch();
    error InsufficientBuffer();

    /* //////////////////////////////////////////////////////////////
                                 CREDITS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Accrues the protocol share of collected fees and credits the principal and the net fees to the buffer.
     * @param state The core state.
     * @param principal The token amounts released, without fees.
     * @param fees The accrued fees collected, before the protocol share.
     * @return delta The token amounts credited to the buffer.
     */
    function creditCollected(State storage state, TokenDelta principal, TokenDelta fees)
        internal
        returns (TokenDelta delta)
    {
        // From collected fees, subtract share for the protocol.
        uint256 bps = state.config.protocolSwapFeeBps;
        (uint256 fees0, uint256 fees1) = TokenDeltaLib.toAmounts(fees);
        (uint256 protocolFee0, uint256 protocolFee1) =
            (fees0.fullMulDiv(bps, ConfigLib.BPS_DENOMINATOR), fees1.fullMulDiv(bps, ConfigLib.BPS_DENOMINATOR));

        // Calculate the buffer delta (principal plus net collected fees).
        // Unchecked: the protocol fee is at most half of the collected fees.
        unchecked {
            delta = principal.add(TokenDeltaLib.fromAmounts(fees0 - protocolFee0, fees1 - protocolFee1));
        }

        // Update State.
        state.poolTokens.protocolFees.applyDelta(TokenDeltaLib.fromAmounts(protocolFee0, protocolFee1));
        state.poolTokens.buffer.applyDelta(delta);

        // forge-lint: disable-next-line(reentrancy-events)
        if ((fees0 | fees1) != 0) emit IALMCoreEvents.FeesCollected(fees0, fees1);
    }

    /* //////////////////////////////////////////////////////////////
                              PROTOCOL FEES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Pays the protocol fees out.
     * @param fees The protocol fees.
     * @param token0 The token0 of the pool.
     * @param token1 The token1 of the pool.
     * @param recipient The recipient of the protocol fees.
     * @return amount0 The token0 paid.
     * @return amount1 The token1 paid.
     */
    function payProtocolFees(TokenAmounts storage fees, address token0, address token1, address recipient)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        // Cache the protocol fees.
        (amount0, amount1) = (fees.amount0, fees.amount1);

        // Update State.
        (fees.amount0, fees.amount1) = (0, 0);

        // Transfer the protocol fees in pool tokens to the fee recipient.
        if (amount0 > 0) token0.safeTransfer(recipient, amount0);
        if (amount1 > 0) token1.safeTransfer(recipient, amount1);
    }

    /* //////////////////////////////////////////////////////////////
                                RESERVES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Accrues the untracked tokens to the protocol.
     * @param state The core state.
     * @param token0 The token0 of the pool.
     * @param token1 The token1 of the pool.
     * @return amount0 The token0 skimmed.
     * @return amount1 The token1 skimmed.
     */
    function skim(State storage state, address token0, address token1)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        // Calculate the untracked tokens (balances above the reserves), except the reward token.
        PoolTokens storage poolTokens = state.poolTokens;
        (uint256 reserve0, uint256 reserve1) = getReserves(poolTokens);
        uint256 rewardPoolToken = state.config.rewardPoolToken;
        if (rewardPoolToken != 1) amount0 = token0.balanceOf(address(this)) - reserve0;
        if (rewardPoolToken != 2) amount1 = token1.balanceOf(address(this)) - reserve1;

        // Update State.
        poolTokens.protocolFees.applyDelta(TokenDeltaLib.fromAmounts(amount0, amount1));
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The token amounts the core accounts for: the buffer, the protocol fees and the escrow.
     * @param poolTokens The token ledger.
     * @return reserve0 The token0 accounted for.
     * @return reserve1 The token1 accounted for.
     */
    function getReserves(PoolTokens storage poolTokens) internal view returns (uint256 reserve0, uint256 reserve1) {
        // Unchecked: every term is a uint128.
        unchecked {
            (reserve0, reserve1) =
            (
                uint256(poolTokens.buffer.amount0) + poolTokens.protocolFees.amount0 + poolTokens.escrowed.amount0,
                uint256(poolTokens.buffer.amount1) + poolTokens.protocolFees.amount1 + poolTokens.escrowed.amount1
            );
        }
    }

    /**
     * @notice Checks the token balances cover every tracked amount, the measured reward balance included.
     * @param state The core state.
     * @param token0 The token0 of the pool.
     * @param token1 The token1 of the pool.
     */
    function checkSolvency(State storage state, address token0, address token1) internal view {
        (uint256 reserve0, uint256 reserve1) = getReserves(state.poolTokens);
        uint256 rewardPoolToken = state.config.rewardPoolToken;
        if (rewardPoolToken == 1) reserve0 += state.rewards.lastRewardBalance;
        else if (rewardPoolToken == 2) reserve1 += state.rewards.lastRewardBalance;
        if (token0.balanceOf(address(this)) < reserve0) revert AccountingMismatch();
        if (token1.balanceOf(address(this)) < reserve1) revert AccountingMismatch();
    }
}
