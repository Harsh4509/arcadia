/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import {
    BalanceDelta as TokenDelta,
    toBalanceDelta as toTokenDelta
} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";

/**
 * @notice An amount of token0 and an amount of token1.
 */
struct TokenAmounts {
    uint128 amount0;
    uint128 amount1;
}

using TokenDeltaLib for TokenAmounts global;

/**
 * @title Token Delta Library.
 * @author Pragma Labs
 * @notice Uniswap v4's `BalanceDelta` as `TokenDelta`, with `uint256` conversions and application to stored token pairs.
 */
// forge-lint: disable-next-item(require-revert-in-loop)
library TokenDeltaLib {
    /* //////////////////////////////////////////////////////////////
                                  LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Negates both components of a delta.
     * @param tokenDelta The delta.
     * @return negated The delta with both components negated.
     */
    function neg(TokenDelta tokenDelta) internal pure returns (TokenDelta negated) {
        uint256 overflow;
        assembly ("memory-safe") {
            let negated0 := sub(0, sar(128, tokenDelta))
            let negated1 := sub(0, signextend(15, tokenDelta))
            overflow := or(shr(128, add(negated0, shl(127, 1))), shr(128, add(negated1, shl(127, 1))))
            negated := or(shl(128, negated0), and(negated1, 0xffffffffffffffffffffffffffffffff))
        }
        if (overflow != 0) revert SafeCastLib.Overflow();
    }

    /**
     * @notice Adds two deltas, component by component.
     * @param a The first delta.
     * @param b The second delta.
     * @return sum The sum of both deltas.
     */
    function add(TokenDelta a, TokenDelta b) internal pure returns (TokenDelta sum) {
        uint256 overflow;
        assembly ("memory-safe") {
            let sum0 := add(sar(128, a), sar(128, b))
            let sum1 := add(signextend(15, a), signextend(15, b))
            overflow := or(shr(128, add(sum0, shl(127, 1))), shr(128, add(sum1, shl(127, 1))))
            sum := or(shl(128, sum0), and(sum1, 0xffffffffffffffffffffffffffffffff))
        }
        if (overflow != 0) revert SafeCastLib.Overflow();
    }

    /**
     * @notice Packs a signed amount of one token into a delta.
     * @param isToken0 True when the amount is token0.
     * @param amount The signed amount.
     * @return tokenDelta The packed delta, zero in the other component.
     */
    function single(bool isToken0, int128 amount) internal pure returns (TokenDelta tokenDelta) {
        assembly ("memory-safe") {
            tokenDelta := shl(mul(128, isToken0), and(amount, 0xffffffffffffffffffffffffffffffff))
        }
    }

    /**
     * @notice Packs two non-negative amounts into a delta.
     * @param amount0 The token0 magnitude.
     * @param amount1 The token1 magnitude.
     * @return tokenDelta The packed delta, positive in both components.
     */
    function fromAmounts(uint256 amount0, uint256 amount1) internal pure returns (TokenDelta tokenDelta) {
        if ((amount0 | amount1) >> 127 != 0) revert SafeCastLib.Overflow();
        assembly ("memory-safe") {
            tokenDelta := or(shl(128, amount0), amount1)
        }
    }

    /**
     * @notice Reads both components of a delta back into magnitudes.
     * @param tokenDelta The delta, positive in both components.
     * @return amount0 The token0 magnitude.
     * @return amount1 The token1 magnitude.
     */
    function toAmounts(TokenDelta tokenDelta) internal pure returns (uint256 amount0, uint256 amount1) {
        assembly ("memory-safe") {
            amount0 := sar(128, tokenDelta)
            amount1 := signextend(15, tokenDelta)
        }
    }

    /**
     * @notice Applies a delta to a stored token pair, writing nothing for a zero delta.
     * @param amounts The token pair.
     * @param delta The token amounts credited, negative for the amounts taken.
     */
    function applyDelta(TokenAmounts storage amounts, TokenDelta delta) internal {
        assembly ("memory-safe") {
            if delta {
                let packed := sload(amounts.slot)
                let amount0 := add(and(packed, 0xffffffffffffffffffffffffffffffff), sar(128, delta))
                let amount1 := add(shr(128, packed), signextend(15, delta))
                if or(shr(128, amount0), shr(128, amount1)) {
                    mstore(0x00, 0x4e487b71)
                    mstore(0x20, 0x11)
                    revert(0x1c, 0x24)
                }
                sstore(amounts.slot, or(amount0, shl(128, amount1)))
            }
        }
    }
}
