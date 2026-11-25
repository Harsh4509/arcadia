/**
 * https://github.com/dromos-labs/metadex-slipstream-public/blob/main/contracts/periphery/libraries/OracleLibrary.sol
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
pragma solidity ^0.8.34;

import { IMetadexCLPool } from "../../../interfaces/IMetadexCLPool.sol";

/**
 * @title Metadex Oracle Library.
 * @notice Reads the time-weighted average tick of a Metadex CL pool.
 */
// forge-lint: disable-next-item(unsafe-typecast)
library MetadexOracle {
    /**
     * @notice Calculates the arithmetic mean tick of a pool over a window.
     * @param pool The Metadex CL pool.
     * @param secondsAgo The window, in seconds.
     * @return arithmeticMeanTick The arithmetic mean tick, rounded toward negative infinity.
     * @dev Vendored from OracleLibrary.consult, without the harmonic mean liquidity.
     */
    function consult(address pool, uint32 secondsAgo) internal view returns (int24 arithmeticMeanTick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;

        int56[] memory tickCumulatives = IMetadexCLPool(pool).observe(secondsAgos);
        // Unchecked: vendored, unchecked under solc 0.7.6.
        unchecked {
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

            arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(secondsAgo)));
            // Always round to negative infinity.
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)) {
                arithmeticMeanTick--;
            }
        }
    }
}
