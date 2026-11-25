/**
 * https://github.com/dromos-labs/metadex-slipstream-public/blob/main/contracts/periphery/libraries/PositionValue.sol
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
pragma solidity ^0.8.34;

import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLPool } from "../../../interfaces/IMetadexCLPool.sol";
import { IMetadexCLPositionManager } from "../../../interfaces/IMetadexCLPositionManager.sol";

/**
 * @title Metadex Position Value.
 * @notice Reads the fees a Metadex CL position has accrued.
 */
// forge-lint: disable-next-item(calls-loop)
library MetadexPositionValue {
    using FixedPointMathLib for uint256;

    /**
     * @notice Calculates the fees a position has accrued and not collected yet.
     * @param pool The Metadex CL pool.
     * @param position The position, as the position manager returns it.
     * @return amount0 The fee amount of token0.
     * @return amount1 The fee amount of token1.
     * @dev Vendored from PositionValue.fees, with the fee growth inside read from the pool.
     */
    function fees(address pool, IMetadexCLPositionManager.Position memory position)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            IMetadexCLPool(pool).getFeeGrowthInside(position.tickLower, position.tickUpper);

        // Unchecked: vendored, unchecked under solc 0.7.6.
        unchecked {
            amount0 = position.tokensOwed0
                + (feeGrowthInside0CurrentX128 - position.feeGrowthInside0LastX128)
                .fullMulDiv(position.liquidity, FixedPoint128.Q128);
            amount1 = position.tokensOwed1
                + (feeGrowthInside1CurrentX128 - position.feeGrowthInside1LastX128)
                .fullMulDiv(position.liquidity, FixedPoint128.Q128);
        }
    }
}
