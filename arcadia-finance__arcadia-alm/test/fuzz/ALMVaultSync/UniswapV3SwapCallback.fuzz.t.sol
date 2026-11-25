/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { ALMVaultSyncExtension } from "../../utils/extensions/ALMVaultSyncExtension.sol";
import { Constants } from "../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the function "uniswapV3SwapCallback" of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract UniswapV3SwapCallback_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_uniswapV3SwapCallback_OnlyPool_NotThePool(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address caller,
        int256 amount0Delta,
        int256 amount1Delta,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A caller other than the pool.
        vm.assume(caller != address(pool));

        // When: The caller invokes the callback.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMVaultSync.OnlyPool.selector);
        vault.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");
    }

    function testFuzz_Success_uniswapV3SwapCallback_PaysToken0(
        PoolState memory poolState,
        int256 amount0Delta,
        int256 amount1Delta,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price and a vault over it.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSyncExtension vault = vaultExtension(isToken0);

        // And: A pool swap callback that owes the pool token0.
        amount0Delta = bound(amount0Delta, 1, int256(Constants.MAX_FUZZED_AMOUNT));
        token0.mint(address(vault), uint256(amount0Delta));
        uint256 pool0Before = token0.balanceOf(address(pool));
        uint256 pool1Before = token1.balanceOf(address(pool));

        // When: The pool calls the callback.
        vm.prank(address(pool));
        vault.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");

        // Then: The pool received the token0 owed and no token1.
        assertEq(token0.balanceOf(address(pool)), pool0Before + uint256(amount0Delta));
        assertEq(token1.balanceOf(address(pool)), pool1Before);
    }

    function testFuzz_Success_uniswapV3SwapCallback_PaysToken1(
        PoolState memory poolState,
        int256 amount0Delta,
        int256 amount1Delta,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price and a vault over it.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSyncExtension vault = vaultExtension(isToken0);

        // And: A pool swap callback that owes the pool token1 only.
        amount0Delta = bound(amount0Delta, type(int256).min, 0);
        amount1Delta = bound(amount1Delta, 1, int256(Constants.MAX_FUZZED_AMOUNT));
        token1.mint(address(vault), uint256(amount1Delta));
        uint256 pool0Before = token0.balanceOf(address(pool));
        uint256 pool1Before = token1.balanceOf(address(pool));

        // When: The pool calls the callback.
        vm.prank(address(pool));
        vault.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");

        // Then: The pool received the token1 owed and no token0.
        assertEq(token0.balanceOf(address(pool)), pool0Before);
        assertEq(token1.balanceOf(address(pool)), pool1Before + uint256(amount1Delta));
    }

    function testFuzz_Success_uniswapV3SwapCallback_PaysNothing(
        PoolState memory poolState,
        int256 amount0Delta,
        int256 amount1Delta,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price and a vault over it.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSyncExtension vault = vaultExtension(isToken0);

        // And: A pool swap callback that owes the pool nothing.
        amount0Delta = bound(amount0Delta, type(int256).min, 0);
        amount1Delta = bound(amount1Delta, type(int256).min, 0);
        uint256 pool0Before = token0.balanceOf(address(pool));
        uint256 pool1Before = token1.balanceOf(address(pool));

        // When: The pool calls the callback.
        vm.prank(address(pool));
        vault.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");

        // Then: The pool received neither token.
        assertEq(token0.balanceOf(address(pool)), pool0Before);
        assertEq(token1.balanceOf(address(pool)), pool1Before);
    }
}
