/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { ExchangeRate } from "../../../../src/core/types/State.sol";
import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { ShareLib } from "../../../../src/core/libraries/state/ShareLib.sol";
import { ShareLib_Fuzz_Test } from "./_ShareLib.fuzz.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getPendingShares" of library "ShareLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetPendingShares_ShareLib_Fuzz_Test is ShareLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getPendingShares_LastExchangeRateNotSet(
        bool isToken0,
        uint256 assets,
        uint160 sqrtPriceX96,
        uint256 supplyPerValueX128
    ) public {
        // Given: A stored exchange rate without a price.
        shareLib.setLastExchangeRate(ExchangeRate({ supplyPerValueX128: supplyPerValueX128, sqrtPriceX96: 0 }));

        // When: Computing the pending shares.
        // Then: It reverts.
        vm.expectRevert(ShareLib.LastExchangeRateNotSet.selector);
        shareLib.getPendingShares(isToken0, assets, sqrtPriceX96);
    }

    function testFuzz_Success_getPendingShares_Token0_SpotAboveTheExchangeRate(
        uint96 assets,
        uint160 sqrtPriceX96,
        uint160 lastSqrtPriceX96,
        uint128 supplyPerValueX128
    ) public {
        // Given: A spot above the exchange rate, both inside the band.
        lastSqrtPriceX96 = uint160(
            bound(
                lastSqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK) - 1
            )
        );
        sqrtPriceX96 =
            uint160(bound(sqrtPriceX96, lastSqrtPriceX96 + 1, TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)));

        shareLib.setLastExchangeRate(
            ExchangeRate({ supplyPerValueX128: supplyPerValueX128, sqrtPriceX96: lastSqrtPriceX96 })
        );

        // When: Computing the pending shares for a token0 amount.
        uint256 shares = shareLib.getPendingShares(true, assets, sqrtPriceX96);

        // Then: They are the amount's value at spot at the rate, each step rounded up.
        uint256 value = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(assets, sqrtPriceX96, FixedPoint96.Q96), sqrtPriceX96, FixedPoint96.Q96
        );
        assertEq(shares, FullMath.mulDivRoundingUp(value, supplyPerValueX128, FixedPoint128.Q128));
    }

    function testFuzz_Success_getPendingShares_Token0_SpotAtOrBelowTheExchangeRate(
        uint96 assets,
        uint160 sqrtPriceX96,
        uint160 lastSqrtPriceX96,
        uint128 supplyPerValueX128
    ) public {
        // Given: A spot at or below the exchange rate, both inside the band.
        lastSqrtPriceX96 = uint160(
            bound(
                lastSqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        sqrtPriceX96 =
            uint160(bound(sqrtPriceX96, TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK), lastSqrtPriceX96));

        shareLib.setLastExchangeRate(
            ExchangeRate({ supplyPerValueX128: supplyPerValueX128, sqrtPriceX96: lastSqrtPriceX96 })
        );

        // When: Computing the pending shares for a token0 amount.
        uint256 shares = shareLib.getPendingShares(true, assets, sqrtPriceX96);

        // Then: They are the amount's value at the rate's price, each step rounded up.
        uint256 value = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(assets, lastSqrtPriceX96, FixedPoint96.Q96), lastSqrtPriceX96, FixedPoint96.Q96
        );
        assertEq(shares, FullMath.mulDivRoundingUp(value, supplyPerValueX128, FixedPoint128.Q128));
    }

    function testFuzz_Success_getPendingShares_Token1_SpotAtOrAboveTheExchangeRate(
        uint96 assets,
        uint160 sqrtPriceX96,
        uint160 lastSqrtPriceX96,
        uint128 supplyPerValueX128
    ) public {
        // Given: A spot at or above the exchange rate, both inside the band.
        lastSqrtPriceX96 = uint160(
            bound(
                lastSqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK),
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, lastSqrtPriceX96, TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)));

        shareLib.setLastExchangeRate(
            ExchangeRate({ supplyPerValueX128: supplyPerValueX128, sqrtPriceX96: lastSqrtPriceX96 })
        );

        // When: Computing the pending shares for a token1 amount.
        uint256 shares = shareLib.getPendingShares(false, assets, sqrtPriceX96);

        // Then: They are the amount at the exchange rate's ratio, rounded up.
        assertEq(shares, FullMath.mulDivRoundingUp(assets, supplyPerValueX128, FixedPoint128.Q128));
    }

    function testFuzz_Success_getPendingShares_Token1_SpotBelowTheExchangeRate(
        uint96 assets,
        uint160 sqrtPriceX96,
        uint160 lastSqrtPriceX96,
        uint128 supplyPerValueX128
    ) public {
        // Given: A spot below the exchange rate, both inside the band.
        lastSqrtPriceX96 = uint160(
            bound(
                lastSqrtPriceX96,
                TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK) + 1,
                TickMath.getSqrtPriceAtTick(Constants.BOUND_TICK)
            )
        );
        sqrtPriceX96 =
            uint160(bound(sqrtPriceX96, TickMath.getSqrtPriceAtTick(-Constants.BOUND_TICK), lastSqrtPriceX96 - 1));

        shareLib.setLastExchangeRate(
            ExchangeRate({ supplyPerValueX128: supplyPerValueX128, sqrtPriceX96: lastSqrtPriceX96 })
        );

        // When: Computing the pending shares for a token1 amount.
        uint256 shares = shareLib.getPendingShares(false, assets, sqrtPriceX96);

        // Then: They are the amount grossed up by the price drop, each step rounded up.
        uint256 value = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(assets, lastSqrtPriceX96, sqrtPriceX96), lastSqrtPriceX96, sqrtPriceX96
        );
        assertEq(shares, FullMath.mulDivRoundingUp(value, supplyPerValueX128, FixedPoint128.Q128));
    }
}
