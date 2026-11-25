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
 * @notice Fuzz tests for the function "checkTrustedDeviation" of library "ConfigLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CheckTrustedDeviation_ConfigLib_Fuzz_Test is ConfigLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_checkTrustedDeviation_ZeroTrustedPrice(
        PoolState memory poolState,
        uint64 maxSpot,
        uint64 maxTwap
    ) public {
        // Given: A pool with depth at a fuzzed price, and any two bands.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, maxSpot, maxTwap);

        // When: Checking the pool against a trusted price of zero.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        configLib.checkTrustedDeviation(address(pool), 0);
    }

    function testFuzz_Revert_checkTrustedDeviation_OneAboveTheSpotBand(PoolState memory poolState, uint64 maxSpot)
        public
    {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Any spot band, and a TWAP band as wide as storage holds.
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, maxSpot, type(uint64).max);

        // And: A trusted price one above the highest whose band holds spot.
        uint160 trusted = uint160(poolState.sqrtPrice * (1e18 + uint256(maxSpot)) / 1e18 + 1);

        // When: Checking the pool against the trusted price.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        configLib.checkTrustedDeviation(address(pool), trusted);
    }

    function testFuzz_Revert_checkTrustedDeviation_OneBelowTheSpotBand(PoolState memory poolState, uint64 maxSpot)
        public
    {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Any spot band, and a TWAP band as wide as storage holds.
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, maxSpot, type(uint64).max);

        // And: A trusted price one below the lowest whose band holds spot.
        uint160 trusted = uint160(FixedPointMathLib.divUp(poolState.sqrtPrice * 1e18, 1e18 + uint256(maxSpot)) - 1);

        // When: Checking the pool against the trusted price.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        configLib.checkTrustedDeviation(address(pool), trusted);
    }

    function testFuzz_Revert_checkTrustedDeviation_OneAboveTheTwapBand(PoolState memory poolState, uint64 maxTwap)
        public
    {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A spot band as wide as storage holds, and a TWAP band up to a factor two.
        maxTwap = uint64(bound(maxTwap, 0, Constants.WIDE_DEVIATION));
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, type(uint64).max, maxTwap);

        // And: A trusted price one above the highest whose band holds the TWAP.
        uint160 trusted = uint160(mean * (1e18 + uint256(maxTwap)) / 1e18 + 1);

        // When: Checking the pool against the trusted price.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        configLib.checkTrustedDeviation(address(pool), trusted);
    }

    function testFuzz_Revert_checkTrustedDeviation_OneBelowTheTwapBand(PoolState memory poolState, uint64 maxTwap)
        public
    {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A spot band as wide as storage holds, and a TWAP band up to a factor two.
        maxTwap = uint64(bound(maxTwap, 0, Constants.WIDE_DEVIATION));
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, type(uint64).max, maxTwap);

        // And: A trusted price one below the lowest whose band holds the TWAP.
        uint160 trusted = uint160(FixedPointMathLib.divUp(mean * 1e18, 1e18 + uint256(maxTwap)) - 1);

        // When: Checking the pool against the trusted price.
        // Then: It reverts.
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        configLib.checkTrustedDeviation(address(pool), trusted);
    }

    function testFuzz_Success_checkTrustedDeviation_AtTheSpotBandUpperEdge(PoolState memory poolState, uint64 maxSpot)
        public
    {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A spot band up to a factor two, and a TWAP band as wide as storage holds.
        maxSpot = uint64(bound(maxSpot, 0, Constants.WIDE_DEVIATION));
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, maxSpot, type(uint64).max);

        // And: The highest trusted price whose band holds spot.
        uint160 trusted = uint160(poolState.sqrtPrice * (1e18 + uint256(maxSpot)) / 1e18);

        // When: Checking the pool against the trusted price.
        uint160 spot = configLib.checkTrustedDeviation(address(pool), trusted);

        // Then: It returns the pool's spot.
        assertEq(spot, poolState.sqrtPrice);
    }

    function testFuzz_Success_checkTrustedDeviation_AtTheSpotBandLowerEdge(PoolState memory poolState, uint64 maxSpot)
        public
    {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A spot band up to a factor two, and a TWAP band as wide as storage holds.
        maxSpot = uint64(bound(maxSpot, 0, Constants.WIDE_DEVIATION));
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, maxSpot, type(uint64).max);

        // And: The lowest trusted price whose band holds spot.
        uint160 trusted = uint160(FixedPointMathLib.divUp(poolState.sqrtPrice * 1e18, 1e18 + uint256(maxSpot)));

        // When: Checking the pool against the trusted price.
        uint160 spot = configLib.checkTrustedDeviation(address(pool), trusted);

        // Then: It returns the pool's spot.
        assertEq(spot, poolState.sqrtPrice);
    }

    function testFuzz_Success_checkTrustedDeviation_AtTheTwapBandUpperEdge(PoolState memory poolState, uint64 maxTwap)
        public
    {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A spot band as wide as storage holds, and a TWAP band up to a factor two.
        maxTwap = uint64(bound(maxTwap, 0, Constants.WIDE_DEVIATION));
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, type(uint64).max, maxTwap);

        // And: The highest trusted price whose band holds the TWAP.
        uint160 trusted = uint160(mean * (1e18 + uint256(maxTwap)) / 1e18);

        // When: Checking the pool against the trusted price.
        uint160 spot = configLib.checkTrustedDeviation(address(pool), trusted);

        // Then: It returns the pool's spot.
        assertEq(spot, poolState.sqrtPrice);
    }

    function testFuzz_Success_checkTrustedDeviation_AtTheTwapBandLowerEdge(PoolState memory poolState, uint64 maxTwap)
        public
    {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A spot band as wide as storage holds, and a TWAP band up to a factor two.
        maxTwap = uint64(bound(maxTwap, 0, Constants.WIDE_DEVIATION));
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, type(uint64).max, maxTwap);

        // And: The lowest trusted price whose band holds the TWAP.
        uint160 trusted = uint160(FixedPointMathLib.divUp(mean * 1e18, 1e18 + uint256(maxTwap)));

        // When: Checking the pool against the trusted price.
        uint160 spot = configLib.checkTrustedDeviation(address(pool), trusted);

        // Then: It returns the pool's spot.
        assertEq(spot, poolState.sqrtPrice);
    }

    function testFuzz_Success_checkTrustedDeviation_BothInsideTheirBands(
        PoolState memory poolState,
        uint160 trusted,
        uint64 maxSpot,
        uint64 maxTwap
    ) public {
        // Given: A pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A trusted price within the wide deviation band around spot.
        trusted = uint160(
            bound(
                trusted,
                FixedPointMathLib.divUp(poolState.sqrtPrice * 1e18, 1e18 + Constants.WIDE_DEVIATION),
                poolState.sqrtPrice * (1e18 + Constants.WIDE_DEVIATION) / 1e18
            )
        );

        // And: Bands at least the ratio of the trusted price to spot and to the TWAP.
        uint256 spotRatio = FixedPointMathLib.max(
            FixedPointMathLib.divUp(poolState.sqrtPrice * 1e18, trusted),
            FixedPointMathLib.divUp(uint256(trusted) * 1e18, poolState.sqrtPrice)
        );
        uint256 twapRatio = FixedPointMathLib.max(
            FixedPointMathLib.divUp(mean * 1e18, trusted), FixedPointMathLib.divUp(uint256(trusted) * 1e18, mean)
        );
        maxSpot = uint64(bound(maxSpot, spotRatio - 1e18, type(uint64).max));
        maxTwap = uint64(bound(maxTwap, twapRatio - 1e18, type(uint64).max));
        configLib.setTrustedDeviation(Constants.TWAP_WINDOW, maxSpot, maxTwap);

        // When: Checking the pool against the trusted price.
        uint160 spot = configLib.checkTrustedDeviation(address(pool), trusted);

        // Then: It returns the pool's spot.
        assertEq(spot, poolState.sqrtPrice);
    }
}
