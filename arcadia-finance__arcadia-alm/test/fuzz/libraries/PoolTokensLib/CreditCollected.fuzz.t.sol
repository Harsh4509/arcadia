/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ConfigLib } from "../../../../src/core/libraries/state/ConfigLib.sol";
import { IALMCoreEvents } from "../../../../src/interfaces/IALMCoreEvents.sol";
import { PoolTokens } from "../../../../src/core/types/State.sol";
import { PoolTokensLib_Fuzz_Test } from "./_PoolTokensLib.fuzz.t.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { TokenDelta, toTokenDelta } from "../../../../src/core/types/TokenDelta.sol";

/**
 * @notice Fuzz tests for the function "creditCollected" of library "PoolTokensLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CreditCollected_PoolTokensLib_Fuzz_Test is PoolTokensLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_creditCollected_NegativeFees0(
        int128 principal0,
        int128 principal1,
        int128 fees0,
        int128 fees1,
        uint256 bps
    ) public {
        // Given: A swap fee within the ceiling.
        bps = bound(bps, 0, ConfigLib.MAX_FEE_BPS);
        poolTokensLib.setProtocolSwapFeeBps(uint16(bps));

        // And: Fees that take token0 rather than crediting it.
        fees0 = int128(bound(fees0, type(int128).min, -1));

        // When: Applying the delta.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        poolTokensLib.creditCollected(toTokenDelta(principal0, principal1), toTokenDelta(fees0, fees1));
    }

    function testFuzz_Revert_creditCollected_NegativeFees1(
        int128 principal0,
        int128 principal1,
        int128 fees0,
        int128 fees1,
        uint256 bps
    ) public {
        // Given: A swap fee within the ceiling.
        bps = bound(bps, 0, ConfigLib.MAX_FEE_BPS);
        poolTokensLib.setProtocolSwapFeeBps(uint16(bps));

        // And: Fees that credit token0 and take token1.
        fees0 = int128(bound(fees0, 0, type(int128).max));
        fees1 = int128(bound(fees1, type(int128).min, -1));

        // When: Applying the delta.
        // Then: It reverts.
        vm.expectRevert(SafeCastLib.Overflow.selector);
        poolTokensLib.creditCollected(toTokenDelta(principal0, principal1), toTokenDelta(fees0, fees1));
    }

    function testFuzz_Success_creditCollected_SplitsTheFeesAndCreditsTheBuffer(
        uint64 principal0,
        uint64 principal1,
        uint64 fees0,
        uint64 fees1,
        uint256 bps,
        uint64 buffer0,
        uint64 buffer1,
        uint64 protocolFees0,
        uint64 protocolFees1
    ) public {
        // Given: A swap fee within the ceiling, and the protocol share of the fees.
        bps = bound(bps, 0, ConfigLib.MAX_FEE_BPS);
        poolTokensLib.setProtocolSwapFeeBps(uint16(bps));
        uint256 fee0 = uint256(fees0) * bps / ConfigLib.BPS_DENOMINATOR;
        uint256 fee1 = uint256(fees1) * bps / ConfigLib.BPS_DENOMINATOR;

        // And: A buffer and fee balances.
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);

        // When: Applying the delta on a principal and its fees.
        TokenDelta delta = poolTokensLib.creditCollected(
            toTokenDelta(int128(uint128(principal0)), int128(uint128(principal1))),
            toTokenDelta(int128(uint128(fees0)), int128(uint128(fees1)))
        );

        // Then: The buffer gets the principal and the fees less the protocol share.
        uint256 credit0 = uint256(principal0) + fees0 - fee0;
        uint256 credit1 = uint256(principal1) + fees1 - fee1;
        assertEq(int256(delta.amount0()), int256(credit0));
        assertEq(int256(delta.amount1()), int256(credit1));
        PoolTokens memory poolTokens = poolTokensLib.getPoolTokens();
        assertEq(poolTokens.buffer.amount0, uint256(buffer0) + credit0);
        assertEq(poolTokens.buffer.amount1, uint256(buffer1) + credit1);

        // And: The protocol share accrues to the fee balances.
        assertEq(poolTokens.protocolFees.amount0, uint256(protocolFees0) + fee0);
        assertEq(poolTokens.protocolFees.amount1, uint256(protocolFees1) + fee1);
    }

    function testFuzz_Success_creditCollected_EmitsFeesCollected(
        uint64 principal0,
        uint64 principal1,
        uint64 fees0,
        uint64 fees1,
        uint256 bps
    ) public {
        // Given: A swap fee within the ceiling.
        bps = bound(bps, 0, ConfigLib.MAX_FEE_BPS);
        poolTokensLib.setProtocolSwapFeeBps(uint16(bps));

        // And: Fees on at least one token.
        fees0 = uint64(bound(fees0, fees1 == 0 ? 1 : 0, type(uint64).max));

        // When: Applying the delta on a principal and its fees.
        // Then: It reports the fees before the protocol share.
        vm.expectEmit(address(poolTokensLib));
        emit IALMCoreEvents.FeesCollected(fees0, fees1);
        poolTokensLib.creditCollected(
            toTokenDelta(int128(uint128(principal0)), int128(uint128(principal1))),
            toTokenDelta(int128(uint128(fees0)), int128(uint128(fees1)))
        );
    }

    function testFuzz_Success_creditCollected_NoFeesCreditsOnlyThePrincipal(
        uint64 principal0,
        uint64 principal1,
        uint256 bps,
        uint64 buffer0,
        uint64 buffer1,
        uint64 protocolFees0,
        uint64 protocolFees1
    ) public {
        // Given: A swap fee within the ceiling.
        bps = bound(bps, 0, ConfigLib.MAX_FEE_BPS);
        poolTokensLib.setProtocolSwapFeeBps(uint16(bps));

        // And: A buffer and fee balances.
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);

        // When: Applying the delta on a principal without fees, logging no fees.
        vm.expectEmit(false, false, false, false, address(poolTokensLib), 0);
        emit IALMCoreEvents.FeesCollected(0, 0);
        TokenDelta delta = poolTokensLib.creditCollected(
            toTokenDelta(int128(uint128(principal0)), int128(uint128(principal1))), toTokenDelta(0, 0)
        );

        // Then: The buffer is credited the principal.
        assertEq(int256(delta.amount0()), int256(uint256(principal0)));
        assertEq(int256(delta.amount1()), int256(uint256(principal1)));
        PoolTokens memory poolTokens = poolTokensLib.getPoolTokens();
        assertEq(poolTokens.buffer.amount0, uint256(buffer0) + principal0);
        assertEq(poolTokens.buffer.amount1, uint256(buffer1) + principal1);

        // And: The fee balances are untouched.
        assertEq(poolTokens.protocolFees.amount0, protocolFees0);
        assertEq(poolTokens.protocolFees.amount1, protocolFees1);
    }
}
