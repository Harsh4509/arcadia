/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PoolLogic } from "../../../src/shared/libraries/logic/PoolLogic.sol";

contract PoolLogicExtension {
    function sqrtPriceX96(address pool) external view returns (uint160 sqrtPriceX96_) {
        sqrtPriceX96_ = PoolLogic.sqrtPriceX96(pool);
    }

    function liquidity(address pool) external view returns (uint128 liquidity_) {
        liquidity_ = PoolLogic.liquidity(pool);
    }

    function sqrtPriceLimit(bool zeroForOne) external pure returns (uint160 sqrtPriceLimitX96) {
        sqrtPriceLimitX96 = PoolLogic.sqrtPriceLimit(zeroForOne);
    }

    function tryFee(address pool) external view returns (bool ok, uint24 fee) {
        (ok, fee) = PoolLogic.tryFee(pool);
    }

    function liquidityNet(address pool, int24 tick) external view returns (int128 liquidityNet_) {
        liquidityNet_ = PoolLogic.liquidityNet(pool, tick);
    }
}
