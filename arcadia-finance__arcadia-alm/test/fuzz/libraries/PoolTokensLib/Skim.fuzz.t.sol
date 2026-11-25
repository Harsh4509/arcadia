/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { PoolTokens } from "../../../../src/core/types/State.sol";
import { PoolTokensLib_Fuzz_Test } from "./_PoolTokensLib.fuzz.t.sol";
import { stdError } from "@forge-std/StdError.sol";

/**
 * @notice Fuzz tests for the function "skim" of library "PoolTokensLib".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract Skim_PoolTokensLib_Fuzz_Test is PoolTokensLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_skim_Token0BelowTracked(uint128 buffer0, uint128 escrowed0, uint256 balance0) public {
        // Given: A token0 balance under the tracked token0.
        buffer0 = uint128(bound(buffer0, 1, type(uint128).max));
        poolTokensLib.setPoolTokens(buffer0, 0, 0, 0);
        poolTokensLib.setEscrowed(escrowed0, 0);
        token0.mint(address(poolTokensLib), bound(balance0, 0, uint256(buffer0) + escrowed0 - 1));

        // When: Skimming.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        poolTokensLib.skim(address(token0), address(token1));
    }

    function testFuzz_Revert_skim_Token1BelowTracked(uint128 buffer1, uint128 protocolFees1, uint256 balance1) public {
        // Given: A token1 balance under the tracked token1, nothing tracked in token0.
        buffer1 = uint128(bound(buffer1, 1, type(uint128).max));
        poolTokensLib.setPoolTokens(0, buffer1, 0, protocolFees1);
        token1.mint(address(poolTokensLib), bound(balance1, 0, uint256(buffer1) + protocolFees1 - 1));

        // When: Skimming.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        poolTokensLib.skim(address(token0), address(token1));
    }

    function testFuzz_Success_skim_AccruesTheUntracked(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1,
        uint256 surplus0,
        uint256 surplus1
    ) public {
        // Given: Buffers, protocol fees a token delta holds and escrow in both tokens.
        protocolFees0 = uint128(bound(protocolFees0, 0, Constants.MAX_FUZZED_AMOUNT));
        protocolFees1 = uint128(bound(protocolFees1, 0, Constants.MAX_FUZZED_AMOUNT));
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);
        poolTokensLib.setEscrowed(escrowed0, escrowed1);

        // And: An untracked surplus the protocol fee balance has room for.
        surplus0 = bound(surplus0, 0, Constants.MAX_FUZZED_AMOUNT - protocolFees0);
        surplus1 = bound(surplus1, 0, Constants.MAX_FUZZED_AMOUNT - protocolFees1);
        token0.mint(address(poolTokensLib), uint256(buffer0) + protocolFees0 + escrowed0 + surplus0);
        token1.mint(address(poolTokensLib), uint256(buffer1) + protocolFees1 + escrowed1 + surplus1);

        // When: Skimming.
        (uint256 amount0, uint256 amount1) = poolTokensLib.skim(address(token0), address(token1));

        // Then: The whole surplus is skimmed into the protocol fees.
        assertEq(amount0, surplus0);
        assertEq(amount1, surplus1);
        PoolTokens memory poolTokens = poolTokensLib.getPoolTokens();
        assertEq(poolTokens.protocolFees.amount0, uint256(protocolFees0) + surplus0);
        assertEq(poolTokens.protocolFees.amount1, uint256(protocolFees1) + surplus1);

        // And: The buffers are untouched.
        assertEq(poolTokens.buffer.amount0, buffer0);
        assertEq(poolTokens.buffer.amount1, buffer1);
    }

    function testFuzz_Success_skim_CreditsTheExcessAfterAClaim(uint256 excess0, address recipient) public {
        // Given: A full token0 fee balance and an untracked excess beside it.
        vm.assume(recipient != address(poolTokensLib) && recipient != address(0));
        excess0 = bound(excess0, 1, Constants.MAX_FUZZED_AMOUNT);
        poolTokensLib.setPoolTokens(0, 0, uint128(Constants.MAX_FUZZED_AMOUNT), 0);
        token0.mint(address(poolTokensLib), Constants.MAX_FUZZED_AMOUNT + excess0);

        // And: The fee balance claimed.
        poolTokensLib.payProtocolFees(address(token0), address(token1), recipient);

        // When: Skimming.
        (uint256 amount0,) = poolTokensLib.skim(address(token0), address(token1));

        // Then: The excess is skimmed into the emptied fee balance.
        assertEq(amount0, excess0);
        assertEq(poolTokensLib.getPoolTokens().protocolFees.amount0, excess0);
    }

    function testFuzz_Success_skim_LeavesTheRewardToken(
        bool isToken0,
        uint128 lastRewardBalance,
        uint256 surplus0,
        uint256 surplus1
    ) public {
        // Given: The reward token is token0 or token1, with a measured reward balance.
        poolTokensLib.setRewardPoolToken(isToken0 ? 1 : 2, lastRewardBalance);

        // And: Untracked balances in both tokens.
        surplus0 = bound(surplus0, 0, Constants.MAX_FUZZED_AMOUNT);
        surplus1 = bound(surplus1, 0, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(address(poolTokensLib), surplus0);
        token1.mint(address(poolTokensLib), surplus1);

        // When: Skimming.
        (uint256 amount0, uint256 amount1) = poolTokensLib.skim(address(token0), address(token1));

        // Then: Only the other token is skimmed, the reward token stays for the holders.
        assertEq(amount0, isToken0 ? 0 : surplus0);
        assertEq(amount1, isToken0 ? surplus1 : 0);
        PoolTokens memory poolTokens = poolTokensLib.getPoolTokens();
        assertEq(poolTokens.protocolFees.amount0, amount0);
        assertEq(poolTokens.protocolFees.amount1, amount1);
    }
}
