/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { IMetadexCLPool } from "../../../interfaces/IMetadexCLPool.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title Pool Logic.
 * @author Pragma Labs
 * @notice The Metadex CL pool's spot price, liquidity, fee, swap price limits and liquidity net.
 */
// forge-lint: disable-next-item(calls-loop, unsafe-typecast, unused-return)
library PoolLogic {
    /* //////////////////////////////////////////////////////////////
                                  LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The pool's spot price.
     * @param pool The Metadex CL pool.
     * @return sqrtPriceX96_ The current sqrt price.
     */
    function sqrtPriceX96(address pool) internal view returns (uint160 sqrtPriceX96_) {
        (sqrtPriceX96_,,,,,) = IMetadexCLPool(pool).slot0();
    }

    /**
     * @notice The pool's active liquidity.
     * @param pool The Metadex CL pool.
     * @return liquidity_ The in-range liquidity.
     */
    function liquidity(address pool) internal view returns (uint128 liquidity_) {
        liquidity_ = IMetadexCLPool(pool).liquidity();
    }

    /**
     * @notice The pool's swap fee, when its fee getter does not revert.
     * @param pool The Metadex CL pool.
     * @return ok False when the fee read reverts.
     * @return fee The fee, with 6 decimals precision, zero when not ok.
     */
    function tryFee(address pool) internal view returns (bool ok, uint24 fee) {
        try IMetadexCLPool(pool).fee() returns (uint24 fee_) {
            (ok, fee) = (true, fee_);
        } catch { }
    }

    /**
     * @notice The price limit of a swap in a direction.
     * @param zeroForOne True when the swap sells token0.
     * @return sqrtPriceLimitX96 The price the swap may not pass.
     */
    function sqrtPriceLimit(bool zeroForOne) internal pure returns (uint160 sqrtPriceLimitX96) {
        // Unchecked: MIN_SQRT_PRICE and MAX_SQRT_PRICE lie strictly within the uint160 range.
        unchecked {
            sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        }
    }

    /**
     * @notice The pool's liquidity net at a tick.
     * @param pool The Metadex CL pool.
     * @param tick The tick.
     * @return liquidityNet_ The liquidity added when the price crosses the tick upward.
     */
    function liquidityNet(address pool, int24 tick) internal view returns (int128 liquidityNet_) {
        (, liquidityNet_,,,,,,,,) = IMetadexCLPool(pool).ticks(tick);
    }
}
