/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import {
    TokenAmounts,
    TokenDelta,
    TokenDeltaLib,
    toTokenDelta as _toTokenDelta
} from "../../../src/core/types/TokenDelta.sol";

contract TokenDeltaLibExtension {
    using TokenDeltaLib for TokenDelta;

    TokenAmounts internal amounts;

    function setAmounts(uint128 amount0_, uint128 amount1_) external {
        (amounts.amount0, amounts.amount1) = (amount0_, amount1_);
    }

    function getAmounts() external view returns (TokenAmounts memory amounts_) {
        amounts_ = amounts;
    }

    function applyDelta(TokenDelta delta) external {
        amounts.applyDelta(delta);
    }

    function toTokenDelta(int128 token0Amount, int128 token1Amount) external pure returns (TokenDelta delta) {
        delta = _toTokenDelta(token0Amount, token1Amount);
    }

    function fromAmounts(uint256 token0Amount, uint256 token1Amount) external pure returns (TokenDelta delta) {
        delta = TokenDeltaLib.fromAmounts(token0Amount, token1Amount);
    }

    function single(bool isToken0, int128 amount) external pure returns (TokenDelta delta) {
        delta = TokenDeltaLib.single(isToken0, amount);
    }

    function toAmounts(TokenDelta delta) external pure returns (uint256 token0Amount, uint256 token1Amount) {
        (token0Amount, token1Amount) = TokenDeltaLib.toAmounts(delta);
    }

    function amount0(TokenDelta delta) external pure returns (int128) {
        return delta.amount0();
    }

    function amount1(TokenDelta delta) external pure returns (int128) {
        return delta.amount1();
    }

    function neg(TokenDelta a) external pure returns (TokenDelta) {
        return a.neg();
    }

    function add(TokenDelta a, TokenDelta b) external pure returns (TokenDelta) {
        return a.add(b);
    }
}
