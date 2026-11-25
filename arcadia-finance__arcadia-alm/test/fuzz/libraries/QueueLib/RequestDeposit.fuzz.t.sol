/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PoolTokens, Record, ShareAccount } from "../../../../src/core/types/State.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";
import { ShareLib } from "../../../../src/core/libraries/state/ShareLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "requestDeposit" of library "QueueLib".
 */
contract RequestDeposit_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_requestDeposit_LastExchangeRateNotSet(
        address vault,
        address controller,
        bool isToken0,
        uint256 assets,
        uint160 sqrtPriceX96
    ) public {
        // Given: No execution has stored an exchange rate.

        // When: Requesting a deposit.
        // Then: It reverts.
        vm.expectRevert(ShareLib.LastExchangeRateNotSet.selector);
        queueLib.requestDeposit(vault, controller, isToken0, assets, sqrtPriceX96);
    }

    function testFuzz_Success_requestDeposit_RecordsWithPendingShares(
        address vault,
        address controller,
        uint32 pendingEpoch,
        bool isToken0,
        uint256 assets,
        uint160 sqrtPriceX96,
        uint160 lastSqrtPriceX96,
        uint256 supply,
        uint256 value
    ) public {
        // Given: A stored exchange rate of at most one share per unit of value.
        uint256 sqrtPriceCeiling = FixedPointMathLib.sqrt(type(uint96).max) << 96;
        lastSqrtPriceX96 = uint160(bound(lastSqrtPriceX96, TickMath.MIN_SQRT_PRICE, sqrtPriceCeiling));
        value = bound(value, 1, type(uint128).max);
        supply = bound(supply, 1, value);
        queueLib.setLastExchangeRate(lastSqrtPriceX96, supply, value);

        // And: A spot at or above the rate's, a token0 unit worth at most a uint96.
        sqrtPriceX96 = uint160(bound(sqrtPriceX96, lastSqrtPriceX96, sqrtPriceCeiling));
        vm.assume(controller != address(0));
        queueLib.setPendingEpochs(vault, pendingEpoch, 0);

        // And: A request within a TokenDelta component whose pending aLP fits a uint96.
        assets = bound(
            assets,
            1,
            isToken0
                ? FixedPointMathLib.min(
                    FullMath.mulDiv(FullMath.mulDiv(type(uint96).max, 1 << 96, sqrtPriceX96), 1 << 96, sqrtPriceX96),
                    Constants.MAX_FUZZED_AMOUNT
                )
                : type(uint96).max
        );

        // When: Requesting the deposit.
        queueLib.requestDeposit(vault, controller, isToken0, assets, sqrtPriceX96);

        // Then: The record sits in the pending epoch with the assets and the pending aLP.
        uint256 pendingShares = isToken0
            ? FullMath.mulDivRoundingUp(FullMath.mulDivRoundingUp(assets, sqrtPriceX96, 1 << 96), sqrtPriceX96, 1 << 96)
            : assets;
        pendingShares =
            FullMath.mulDivRoundingUp(pendingShares, FullMath.mulDivRoundingUp(supply, 1 << 128, value), 1 << 128);
        Record memory record = queueLib.getDepositRecord(vault, controller);
        assertEq(record.epoch, pendingEpoch);
        assertEq(record.amountIn, assets);
        assertEq(record.pendingShares, pendingShares);
        assertEq(queueLib.getDepositEpoch(vault, pendingEpoch).amountIn, assets);

        // And: The pending aLP is pending on the controller.
        assertEq(queueLib.getShareAccount(controller).pendingShares, pendingShares);

        // And: The assets are escrowed in the vault's token.
        PoolTokens memory poolTokens = queueLib.getPoolTokens();
        assertEq(isToken0 ? poolTokens.escrowed.amount0 : poolTokens.escrowed.amount1, assets);
        assertEq(isToken0 ? poolTokens.escrowed.amount1 : poolTokens.escrowed.amount0, 0);
    }

    function testFuzz_Success_requestDeposit_AddsToThePendingShares(
        address vault,
        address controller,
        ShareAccount memory shareAccount,
        uint256 assets,
        uint256 supply,
        uint256 value
    ) public {
        // Given: A stored rate at a price of one, at most a share per unit of value.
        value = bound(value, 1, type(uint128).max);
        supply = bound(supply, 1, value);
        queueLib.setLastExchangeRate(1 << 96, supply, value);

        // And: A controller with pending aLP already.
        vm.assume(controller != address(0));
        shareAccount.pendingShares = uint128(bound(shareAccount.pendingShares, 1, type(uint128).max - type(uint96).max));
        queueLib.setShareAccount(controller, shareAccount);

        // When: Requesting a token1 deposit, its pending aLP in a uint96, at price one.
        assets = bound(assets, 1, type(uint96).max);
        queueLib.requestDeposit(vault, controller, false, assets, 1 << 96);

        // Then: The request's pending aLP is added to the controller's.
        uint256 pendingShares =
            FullMath.mulDivRoundingUp(assets, FullMath.mulDivRoundingUp(supply, 1 << 128, value), 1 << 128);
        assertEq(queueLib.getShareAccount(controller).pendingShares, shareAccount.pendingShares + pendingShares);
    }
}
