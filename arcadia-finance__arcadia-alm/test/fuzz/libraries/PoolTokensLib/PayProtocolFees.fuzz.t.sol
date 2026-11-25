/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { PoolTokens } from "../../../../src/core/types/State.sol";
import { PoolTokensLib_Fuzz_Test } from "./_PoolTokensLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "payProtocolFees" of library "PoolTokensLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract PayProtocolFees_PoolTokensLib_Fuzz_Test is PoolTokensLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_payProtocolFees_PaysTheFees(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        address recipient
    ) public {
        // Given: Fee balances a token delta holds, beside fuzzed buffers.
        vm.assume(recipient != address(poolTokensLib) && recipient != address(0));
        protocolFees0 = uint128(bound(protocolFees0, 0, Constants.MAX_FUZZED_AMOUNT));
        protocolFees1 = uint128(bound(protocolFees1, 0, Constants.MAX_FUZZED_AMOUNT));
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);

        // And: The tokens to pay them.
        token0.mint(address(poolTokensLib), protocolFees0);
        token1.mint(address(poolTokensLib), protocolFees1);
        uint256 balance0Before = token0.balanceOf(recipient);
        uint256 balance1Before = token1.balanceOf(recipient);

        // When: Claiming the protocol fees.
        (uint256 amount0, uint256 amount1) = poolTokensLib.payProtocolFees(address(token0), address(token1), recipient);

        // Then: The whole fee balances are paid to the recipient.
        assertEq(amount0, protocolFees0);
        assertEq(amount1, protocolFees1);
        assertEq(token0.balanceOf(recipient), balance0Before + protocolFees0);
        assertEq(token1.balanceOf(recipient), balance1Before + protocolFees1);

        // And: The fee balances are zero, and the buffers are untouched.
        PoolTokens memory poolTokens = poolTokensLib.getPoolTokens();
        assertEq(poolTokens.protocolFees.amount0, 0);
        assertEq(poolTokens.protocolFees.amount1, 0);
        assertEq(poolTokens.buffer.amount0, buffer0);
        assertEq(poolTokens.buffer.amount1, buffer1);
    }

    function testFuzz_Success_payProtocolFees_PaysAFullBalance(uint128 protocolFees0, address recipient) public {
        // Given: A token0 fee balance up to the uint128 maximum.
        vm.assume(recipient != address(poolTokensLib) && recipient != address(0));
        poolTokensLib.setPoolTokens(0, 0, protocolFees0, 0);

        // And: The tokens to pay it.
        token0.mint(address(poolTokensLib), protocolFees0);
        uint256 balance0Before = token0.balanceOf(recipient);

        // When: Claiming the protocol fees.
        (uint256 amount0, uint256 amount1) = poolTokensLib.payProtocolFees(address(token0), address(token1), recipient);

        // Then: The whole balance is paid to the recipient, and the fee balance is zero.
        assertEq(amount0, protocolFees0);
        assertEq(amount1, 0);
        assertEq(token0.balanceOf(recipient), balance0Before + protocolFees0);
        assertEq(poolTokensLib.getPoolTokens().protocolFees.amount0, 0);
    }

    function testFuzz_Success_payProtocolFees_NothingToPayTransfersNothing(
        uint128 buffer0,
        uint128 buffer1,
        address recipient
    ) public {
        // Given: Zero fee balances, beside fuzzed buffers.
        vm.assume(recipient != address(poolTokensLib) && recipient != address(0));
        poolTokensLib.setPoolTokens(buffer0, buffer1, 0, 0);

        // When: Claiming the protocol fees.
        // Then: No token is transferred.
        vm.expectCall(address(token0), abi.encodeWithSelector(token0.transfer.selector), 0);
        vm.expectCall(address(token1), abi.encodeWithSelector(token1.transfer.selector), 0);
        (uint256 amount0, uint256 amount1) = poolTokensLib.payProtocolFees(address(token0), address(token1), recipient);

        // And: It pays zero of both tokens.
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }
}
