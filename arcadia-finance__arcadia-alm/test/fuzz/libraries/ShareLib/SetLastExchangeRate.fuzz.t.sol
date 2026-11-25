/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ExchangeRate } from "../../../../src/core/types/State.sol";
import { FixedPoint128 } from "@uniswap/v4-core/src/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { ShareLib_Fuzz_Test } from "./_ShareLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setLastExchangeRate" of library "ShareLib".
 */
contract SetLastExchangeRate_ShareLib_Fuzz_Test is ShareLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_setLastExchangeRate_ZeroValue(uint160 lastSqrtPriceX96, uint256 supply) public {
        // Given: A plan that ends on no value.

        // When: Storing its exchange rate.
        // Then: It reverts.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        shareLib.setLastExchangeRate(lastSqrtPriceX96, supply, 0);
    }

    function testFuzz_Revert_setLastExchangeRate_SupplyPerValuePastUint256(
        uint160 lastSqrtPriceX96,
        uint256 supply,
        uint256 value
    ) public {
        // Given: A supply so far above the value that its 128-bit ratio passes a uint256.
        supply = bound(supply, 1 << 128, type(uint256).max);
        value = bound(value, 1, supply >> 128);

        // When: Storing the exchange rate.
        // Then: It reverts.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        shareLib.setLastExchangeRate(lastSqrtPriceX96, supply, value);
    }

    function testFuzz_Success_setLastExchangeRate_StoresTheSupplyPerValueRoundedUp(
        uint160 lastSqrtPriceX96,
        uint256 supply,
        uint256 value
    ) public {
        // Given: A supply 2^128 short of a uint256, and a value its ratio fits against.
        supply = bound(supply, 0, type(uint256).max - (1 << 128));
        value = bound(value, (supply >> 128) + 1, type(uint256).max);

        // When: Storing the exchange rate.
        shareLib.setLastExchangeRate(lastSqrtPriceX96, supply, value);

        // Then: The ratio is the supply per value in X128, rounded up.
        ExchangeRate memory lastExchangeRate = shareLib.getLastExchangeRate();
        assertEq(lastExchangeRate.supplyPerValueX128, FullMath.mulDivRoundingUp(supply, FixedPoint128.Q128, value));

        // And: The price is stored beside it.
        assertEq(lastExchangeRate.sqrtPriceX96, lastSqrtPriceX96);
    }
}
