/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PoolTokensLib } from "../../../../src/core/libraries/state/PoolTokensLib.sol";
import { PoolTokensLib_Fuzz_Test } from "./_PoolTokensLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "checkSolvency" of library "PoolTokensLib".
 */
contract CheckSolvency_PoolTokensLib_Fuzz_Test is PoolTokensLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_checkSolvency_Token0Short(
        uint128 buffer0,
        uint128 protocolFees0,
        uint128 escrowed0,
        uint256 balance0,
        uint256 balance1
    ) public {
        // Given: Tracked token0 that the token0 balance falls short of.
        buffer0 = uint128(bound(buffer0, 1, type(uint128).max));
        poolTokensLib.setPoolTokens(buffer0, 0, protocolFees0, 0);
        poolTokensLib.setEscrowed(escrowed0, 0);
        uint256 reserve0 = uint256(buffer0) + protocolFees0 + escrowed0;
        token0.mint(address(poolTokensLib), bound(balance0, 0, reserve0 - 1));

        // And: Any token1 balance, nothing being accounted in it.
        token1.mint(address(poolTokensLib), balance1);

        // When: Checking solvency.
        // Then: It reverts.
        vm.expectRevert(PoolTokensLib.AccountingMismatch.selector);
        poolTokensLib.checkSolvency(address(token0), address(token1));
    }

    function testFuzz_Revert_checkSolvency_Token1Short(
        uint128 buffer1,
        uint128 protocolFees1,
        uint128 escrowed1,
        uint256 balance1,
        uint256 surplus0
    ) public {
        // Given: Tracked token1 that the token1 balance falls short of.
        buffer1 = uint128(bound(buffer1, 1, type(uint128).max));
        poolTokensLib.setPoolTokens(0, buffer1, 0, protocolFees1);
        poolTokensLib.setEscrowed(0, escrowed1);
        uint256 reserve1 = uint256(buffer1) + protocolFees1 + escrowed1;
        token1.mint(address(poolTokensLib), bound(balance1, 0, reserve1 - 1));

        // And: Any token0 balance, nothing being accounted in it.
        token0.mint(address(poolTokensLib), surplus0);

        // When: Checking solvency.
        // Then: It reverts.
        vm.expectRevert(PoolTokensLib.AccountingMismatch.selector);
        poolTokensLib.checkSolvency(address(token0), address(token1));
    }

    function testFuzz_Revert_checkSolvency_RewardBalanceShort(
        bool isToken0,
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1,
        uint128 lastRewardBalance,
        uint256 shortfall
    ) public {
        // Given: Buffers, protocol fees and escrow in both tokens.
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);
        poolTokensLib.setEscrowed(escrowed0, escrowed1);

        // And: The reward token is token0 or token1, with a measured reward balance.
        lastRewardBalance = uint128(bound(lastRewardBalance, 1, type(uint128).max));
        poolTokensLib.setRewardPoolToken(isToken0 ? 1 : 2, lastRewardBalance);

        // And: A reward-side balance covering the reserve, short of the reward on top.
        uint256 reserve0 = uint256(buffer0) + protocolFees0 + escrowed0;
        uint256 reserve1 = uint256(buffer1) + protocolFees1 + escrowed1;
        shortfall = bound(shortfall, 1, lastRewardBalance);
        token0.mint(address(poolTokensLib), isToken0 ? reserve0 + lastRewardBalance - shortfall : reserve0);
        token1.mint(address(poolTokensLib), isToken0 ? reserve1 : reserve1 + lastRewardBalance - shortfall);

        // When: Checking solvency.
        // Then: It reverts.
        vm.expectRevert(PoolTokensLib.AccountingMismatch.selector);
        poolTokensLib.checkSolvency(address(token0), address(token1));
    }

    function testFuzz_Success_checkSolvency_Covered(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1,
        uint256 surplus0,
        uint256 surplus1
    ) public {
        // Given: Buffers, protocol fees and escrow in both tokens.
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);
        poolTokensLib.setEscrowed(escrowed0, escrowed1);

        // And: Balances covering every accounted amount, with any surplus on top.
        uint256 reserve0 = uint256(buffer0) + protocolFees0 + escrowed0;
        uint256 reserve1 = uint256(buffer1) + protocolFees1 + escrowed1;
        token0.mint(address(poolTokensLib), reserve0 + bound(surplus0, 0, type(uint256).max - reserve0));
        token1.mint(address(poolTokensLib), reserve1 + bound(surplus1, 0, type(uint256).max - reserve1));

        // When: Checking solvency.
        (bool success,) = address(poolTokensLib)
            .staticcall(abi.encodeCall(poolTokensLib.checkSolvency, (address(token0), address(token1))));

        // Then: It does not revert.
        assertTrue(success);
    }

    function testFuzz_Success_checkSolvency_ExactlyCovered(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1
    ) public {
        // Given: Buffers, protocol fees and escrow in both tokens.
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);
        poolTokensLib.setEscrowed(escrowed0, escrowed1);

        // And: Balances of exactly every accounted amount.
        token0.mint(address(poolTokensLib), uint256(buffer0) + protocolFees0 + escrowed0);
        token1.mint(address(poolTokensLib), uint256(buffer1) + protocolFees1 + escrowed1);

        // When: Checking solvency.
        (bool success,) = address(poolTokensLib)
            .staticcall(abi.encodeCall(poolTokensLib.checkSolvency, (address(token0), address(token1))));

        // Then: It does not revert.
        assertTrue(success);
    }

    function testFuzz_Success_checkSolvency_CoversTheRewardBalance(
        bool isToken0,
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1,
        uint128 lastRewardBalance
    ) public {
        // Given: Buffers, protocol fees and escrow in both tokens.
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);
        poolTokensLib.setEscrowed(escrowed0, escrowed1);

        // And: The reward token is token0 or token1, with a measured reward balance.
        poolTokensLib.setRewardPoolToken(isToken0 ? 1 : 2, lastRewardBalance);

        // And: Balances of exactly the reserves, the reward balance on the reward side.
        uint256 reserve0 = uint256(buffer0) + protocolFees0 + escrowed0;
        uint256 reserve1 = uint256(buffer1) + protocolFees1 + escrowed1;
        token0.mint(address(poolTokensLib), isToken0 ? reserve0 + lastRewardBalance : reserve0);
        token1.mint(address(poolTokensLib), isToken0 ? reserve1 : reserve1 + lastRewardBalance);

        // When: Checking solvency.
        (bool success,) = address(poolTokensLib)
            .staticcall(abi.encodeCall(poolTokensLib.checkSolvency, (address(token0), address(token1))));

        // Then: It does not revert.
        assertTrue(success);
    }

    function testFuzz_Success_checkSolvency_IgnoresTheRewardBalanceOfAnotherToken(
        uint128 buffer0,
        uint128 buffer1,
        uint128 protocolFees0,
        uint128 protocolFees1,
        uint128 escrowed0,
        uint128 escrowed1,
        uint128 lastRewardBalance
    ) public {
        // Given: Buffers, protocol fees and escrow in both tokens.
        poolTokensLib.setPoolTokens(buffer0, buffer1, protocolFees0, protocolFees1);
        poolTokensLib.setEscrowed(escrowed0, escrowed1);

        // And: A reward token that is neither pool token, with a measured reward balance.
        lastRewardBalance = uint128(bound(lastRewardBalance, 1, type(uint128).max));
        poolTokensLib.setRewardPoolToken(0, lastRewardBalance);

        // And: Balances of exactly the reserves.
        token0.mint(address(poolTokensLib), uint256(buffer0) + protocolFees0 + escrowed0);
        token1.mint(address(poolTokensLib), uint256(buffer1) + protocolFees1 + escrowed1);

        // When: Checking solvency.
        (bool success,) = address(poolTokensLib)
            .staticcall(abi.encodeCall(poolTokensLib.checkSolvency, (address(token0), address(token1))));

        // Then: It does not revert.
        assertTrue(success);
    }
}
