/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { ConfigLib_Fuzz_Test } from "./_ConfigLib.fuzz.t.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "checkTwapDeviation" of library "ConfigLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CheckTwapDeviation_ConfigLib_Fuzz_Test is ConfigLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_checkTwapDeviation_OneAboveTheBand(PoolState memory poolState, uint64 deviation) public {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band around the TWAP.
        configLib.setTwapDeviation(Constants.TWAP_WINDOW, deviation);

        // And: A spot price one above the band's upper edge.
        uint160 spotPrice = uint160(mean * (1e18 + uint256(deviation)) / 1e18 + 1);

        // When: Checking the spot price against the TWAP.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        configLib.checkTwapDeviation(address(pool), spotPrice);
    }

    function testFuzz_Revert_checkTwapDeviation_OneBelowTheBand(PoolState memory poolState, uint64 deviation) public {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band around the TWAP.
        configLib.setTwapDeviation(Constants.TWAP_WINDOW, deviation);

        // And: A spot price one below the band's lower edge.
        uint160 spotPrice = uint160(FixedPointMathLib.divUp(mean * 1e18, 1e18 + uint256(deviation)) - 1);

        // When: Checking the spot price against the TWAP.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        configLib.checkTwapDeviation(address(pool), spotPrice);
    }

    function testFuzz_Success_checkTwapDeviation_AtTheUpperEdge(PoolState memory poolState, uint64 deviation) public {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band around the TWAP.
        configLib.setTwapDeviation(Constants.TWAP_WINDOW, deviation);

        // And: A spot price at the band's upper edge.
        uint160 spotPrice = uint160(mean * (1e18 + uint256(deviation)) / 1e18);

        // When: Checking the spot price against the TWAP.
        (bool success,) =
            address(configLib).staticcall(abi.encodeCall(configLib.checkTwapDeviation, (address(pool), spotPrice)));

        // Then: It does not revert.
        assertTrue(success);
    }

    function testFuzz_Success_checkTwapDeviation_AtTheLowerEdge(PoolState memory poolState, uint64 deviation) public {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band around the TWAP.
        configLib.setTwapDeviation(Constants.TWAP_WINDOW, deviation);

        // And: A spot price at the band's lower edge.
        uint160 spotPrice = uint160(FixedPointMathLib.divUp(mean * 1e18, 1e18 + uint256(deviation)));

        // When: Checking the spot price against the TWAP.
        (bool success,) =
            address(configLib).staticcall(abi.encodeCall(configLib.checkTwapDeviation, (address(pool), spotPrice)));

        // Then: It does not revert.
        assertTrue(success);
    }

    function testFuzz_Success_checkTwapDeviation_InsideTheBand(
        PoolState memory poolState,
        uint64 deviation,
        uint160 spotPrice
    ) public {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band around the TWAP.
        configLib.setTwapDeviation(Constants.TWAP_WINDOW, deviation);

        // And: A spot price between the band's edges.
        spotPrice = uint160(
            bound(
                spotPrice,
                FixedPointMathLib.divUp(mean * 1e18, 1e18 + uint256(deviation)),
                mean * (1e18 + uint256(deviation)) / 1e18
            )
        );

        // When: Checking the spot price against the TWAP.
        (bool success,) =
            address(configLib).staticcall(abi.encodeCall(configLib.checkTwapDeviation, (address(pool), spotPrice)));

        // Then: It does not revert.
        assertTrue(success);
    }
}
