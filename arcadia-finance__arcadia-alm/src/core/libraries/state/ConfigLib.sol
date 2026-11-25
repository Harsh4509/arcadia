/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CLMath } from "../../../shared/libraries/math/CLMath.sol";
import { Config } from "../../types/State.sol";
import { MetadexOracle } from "../../../shared/libraries/vendored/MetadexOracle.sol";
import { PoolLogic } from "../../../shared/libraries/logic/PoolLogic.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title Config Library.
 * @author Pragma Labs
 * @notice The governance bounds, the protocol fee cap, the TWAP reference and the price deviation checks.
 */
library ConfigLib {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The basis points in a whole.
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    // The maximum protocol share of emissions and of collected swap fees.
    uint256 internal constant MAX_FEE_BPS = 5000;

    // The maximum range cap.
    uint8 internal constant MAX_RANGE_CAP = 14;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error NotConfigured();
    error PriceDeviation();

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Reverts unless the parameters a seed relies on are all set.
     * @param config The governance parameters.
     */
    function checkConfigured(Config storage config) internal view {
        if (config.twapWindow == 0 || config.rangeCap == 0 || config.totalCap == 0 || config.perUserCap == 0) {
            revert NotConfigured();
        }
    }

    /**
     * @notice Reverts when the pool's spot price sits outside the band around its TWAP.
     * @param config The governance parameters.
     * @param pool The Metadex CL pool.
     * @param sqrtPriceX96 The pool's spot price.
     */
    function checkTwapDeviation(Config storage config, address pool, uint160 sqrtPriceX96) internal view {
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) = CLMath.getBand(
            TickMath.getSqrtPriceAtTick(MetadexOracle.consult(pool, config.twapWindow)), config.maxSpotFromTwap
        );
        if (sqrtPriceX96 < sqrtPriceLowerX96 || sqrtPriceX96 > sqrtPriceUpperX96) revert PriceDeviation();
    }

    /**
     * @notice Reverts when the spot or the TWAP price sits outside its band around a price the caller supplies.
     * @param config The governance parameters.
     * @param pool The Metadex CL pool.
     * @param trustedSqrtPriceX96 The sqrt price the caller's plan was computed against.
     * @return spotSqrtPriceX96 The pool's spot price.
     */
    function checkTrustedDeviation(Config storage config, address pool, uint160 trustedSqrtPriceX96)
        internal
        view
        returns (uint160 spotSqrtPriceX96)
    {
        (uint256 sqrtPriceLowerX96, uint256 sqrtPriceUpperX96) =
            CLMath.getBand(trustedSqrtPriceX96, config.maxSpotFromTrusted);
        spotSqrtPriceX96 = PoolLogic.sqrtPriceX96(pool);
        if (spotSqrtPriceX96 < sqrtPriceLowerX96 || spotSqrtPriceX96 > sqrtPriceUpperX96) revert PriceDeviation();

        (sqrtPriceLowerX96, sqrtPriceUpperX96) = CLMath.getBand(trustedSqrtPriceX96, config.maxTwapFromTrusted);
        uint256 twapSqrtPriceX96 = TickMath.getSqrtPriceAtTick(MetadexOracle.consult(pool, config.twapWindow));
        if (twapSqrtPriceX96 < sqrtPriceLowerX96 || twapSqrtPriceX96 > sqrtPriceUpperX96) revert PriceDeviation();
    }
}
