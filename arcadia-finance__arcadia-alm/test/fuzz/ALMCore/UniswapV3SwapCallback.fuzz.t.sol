/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

/**
 * @notice Fuzz tests for the function "uniswapV3SwapCallback" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract UniswapV3SwapCallback_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_uniswapV3SwapCallback_OnlyPool_NotThePool(
        address caller,
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) public {
        // Given: A caller that is not the pool.
        vm.assume(caller != address(pool));

        // When: It calls the callback outside a swap.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMCore.OnlyPool.selector);
        almCore.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
    }

    function testFuzz_Revert_uniswapV3SwapCallback_TransferFailed_Token0(
        uint256 balance0,
        int256 amount0Delta,
        int256 amount1Delta
    ) public {
        // Given: A pool swap callback that owes the pool more token0 than the core holds.
        token0.mint(address(almCore), bound(balance0, 0, Constants.MAX_FUZZED_AMOUNT - 1));
        amount0Delta =
            bound(amount0Delta, int256(token0.balanceOf(address(almCore))) + 1, int256(Constants.MAX_FUZZED_AMOUNT));

        // When: The pool calls the callback.
        // Then: It reverts.
        vm.prank(address(pool));
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        almCore.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");
    }

    function testFuzz_Revert_uniswapV3SwapCallback_TransferFailed_Token1(
        uint256 balance1,
        int256 amount0Delta,
        int256 amount1Delta
    ) public {
        // Given: A callback owing the pool only token1, more than the core holds.
        token1.mint(address(almCore), bound(balance1, 0, Constants.MAX_FUZZED_AMOUNT - 1));
        amount0Delta = bound(amount0Delta, type(int256).min, 0);
        amount1Delta =
            bound(amount1Delta, int256(token1.balanceOf(address(almCore))) + 1, int256(Constants.MAX_FUZZED_AMOUNT));

        // When: The pool calls the callback.
        // Then: It reverts.
        vm.prank(address(pool));
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        almCore.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");
    }

    function testFuzz_Success_uniswapV3SwapCallback_PaysToken0(int256 amount0Delta, int256 amount1Delta) public {
        // Given: A pool swap callback that owes the pool token0.
        amount0Delta = bound(amount0Delta, 1, int256(Constants.MAX_FUZZED_AMOUNT));
        token0.mint(address(almCore), uint256(amount0Delta));
        uint256 pool0Before = token0.balanceOf(address(pool));
        uint256 pool1Before = token1.balanceOf(address(pool));
        uint256 core0Before = token0.balanceOf(address(almCore));
        uint256 core1Before = token1.balanceOf(address(almCore));

        // When: The pool calls the callback.
        vm.prank(address(pool));
        almCore.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");

        // Then: The pool received the token0 owed and no token1.
        assertEq(token0.balanceOf(address(pool)), pool0Before + uint256(amount0Delta));
        assertEq(token1.balanceOf(address(pool)), pool1Before);

        // And: The core paid the token0 out of its own balance.
        assertEq(token0.balanceOf(address(almCore)), core0Before - uint256(amount0Delta));
        assertEq(token1.balanceOf(address(almCore)), core1Before);
    }

    function testFuzz_Success_uniswapV3SwapCallback_PaysToken1(int256 amount0Delta, int256 amount1Delta) public {
        // Given: A pool swap callback that owes the pool token1 only.
        amount0Delta = bound(amount0Delta, type(int256).min, 0);
        amount1Delta = bound(amount1Delta, 1, int256(Constants.MAX_FUZZED_AMOUNT));
        token1.mint(address(almCore), uint256(amount1Delta));
        uint256 pool0Before = token0.balanceOf(address(pool));
        uint256 pool1Before = token1.balanceOf(address(pool));
        uint256 core0Before = token0.balanceOf(address(almCore));
        uint256 core1Before = token1.balanceOf(address(almCore));

        // When: The pool calls the callback.
        vm.prank(address(pool));
        almCore.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");

        // Then: The pool received the token1 owed and no token0.
        assertEq(token0.balanceOf(address(pool)), pool0Before);
        assertEq(token1.balanceOf(address(pool)), pool1Before + uint256(amount1Delta));

        // And: The core paid the token1 out of its own balance.
        assertEq(token0.balanceOf(address(almCore)), core0Before);
        assertEq(token1.balanceOf(address(almCore)), core1Before - uint256(amount1Delta));
    }

    function testFuzz_Success_uniswapV3SwapCallback_PaysNothing(int256 amount0Delta, int256 amount1Delta) public {
        // Given: A pool swap callback that owes the pool nothing.
        amount0Delta = bound(amount0Delta, type(int256).min, 0);
        amount1Delta = bound(amount1Delta, type(int256).min, 0);
        uint256 pool0Before = token0.balanceOf(address(pool));
        uint256 pool1Before = token1.balanceOf(address(pool));

        // When: The pool calls the callback.
        vm.prank(address(pool));
        almCore.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");

        // Then: The pool received neither token.
        assertEq(token0.balanceOf(address(pool)), pool0Before);
        assertEq(token1.balanceOf(address(pool)), pool1Before);
    }

    function testFuzz_Success_uniswapV3SwapCallback_PaysOnlyToken0WhenBothAreOwed(
        int256 amount0Delta,
        int256 amount1Delta
    ) public {
        // Given: A callback owing the pool both tokens, and a core holding both.
        amount0Delta = bound(amount0Delta, 1, int256(Constants.MAX_FUZZED_AMOUNT));
        amount1Delta = bound(amount1Delta, 1, int256(Constants.MAX_FUZZED_AMOUNT));
        token0.mint(address(almCore), uint256(amount0Delta));
        token1.mint(address(almCore), uint256(amount1Delta));
        uint256 pool0Before = token0.balanceOf(address(pool));
        uint256 pool1Before = token1.balanceOf(address(pool));
        uint256 core1Before = token1.balanceOf(address(almCore));

        // When: The pool calls the callback.
        vm.prank(address(pool));
        almCore.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");

        // Then: The pool received the token0 owed and no token1.
        assertEq(token0.balanceOf(address(pool)), pool0Before + uint256(amount0Delta));
        assertEq(token1.balanceOf(address(pool)), pool1Before);
        assertEq(token1.balanceOf(address(almCore)), core1Before);
    }
}
