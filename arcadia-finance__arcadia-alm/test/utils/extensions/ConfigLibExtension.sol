/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Config } from "../../../src/core/types/State.sol";

contract ConfigLibExtension {
    Config internal config;

    function setTwapDeviation(uint32 twapWindow, uint64 maxSpotFromTwap) external {
        config.twapWindow = twapWindow;
        config.maxSpotFromTwap = maxSpotFromTwap;
    }

    function setTrustedDeviation(uint32 twapWindow, uint64 maxSpotFromTrusted, uint64 maxTwapFromTrusted) external {
        config.twapWindow = twapWindow;
        config.maxSpotFromTrusted = maxSpotFromTrusted;
        config.maxTwapFromTrusted = maxTwapFromTrusted;
    }

    function checkTwapDeviation(address pool, uint160 sqrtPriceX96) external view {
        config.checkTwapDeviation(pool, sqrtPriceX96);
    }

    function checkTrustedDeviation(address pool, uint160 trustedSqrtPriceX96)
        external
        view
        returns (uint160 spotSqrtPriceX96)
    {
        spotSqrtPriceX96 = config.checkTrustedDeviation(pool, trustedSqrtPriceX96);
    }

    function setConfig(Config memory config_) external {
        config = config_;
    }

    function checkConfigured() external view {
        config.checkConfigured();
    }
}
