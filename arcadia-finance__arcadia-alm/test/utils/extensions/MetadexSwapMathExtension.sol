/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MetadexSwapMath } from "../../../src/shared/libraries/vendored/MetadexSwapMath.sol";

contract MetadexSwapMathExtension {
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) external pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        (sqrtPriceNextX96, amountIn, amountOut, feeAmount) = MetadexSwapMath.computeSwapStep(
            sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, amountRemaining, feePips
        );
    }
}
