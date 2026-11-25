/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { MintOptimizationMath } from "../../../src/vaults/libraries/math/MintOptimizationMath.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { Snapshot, SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Symbolic tests for the function "getMintAmountOut" of library "MintOptimizationMath".
 */
contract GetMintAmountOut_MintOptimizationMath_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function oneRange(uint128 liquidity, uint160 lower, uint160 upper, uint128 idle0, uint128 idle1, uint256 supply)
        internal
        pure
        returns (Snapshot memory snapshot)
    {
        snapshot.ranges = new PricedRange[](1);
        snapshot.ranges[0] = PricedRange(liquidity, 0, lower, upper);
        (snapshot.buffer0, snapshot.buffer1, snapshot.supply) = (idle0, idle1, supply);
        snapshot.core = IALMCore(address(0));
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmountOut_IsZeroIffTheMintTakesNoTokenOut(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1,
        uint256 shares,
        uint256 supply,
        bool zeroForOne
    ) public pure {
        // Given: One range, idle tokens, a mint in a uint128 supply, price 2^48 to 2^128.
        vm.assume(lower >= 1 << 48 && lower < upper && upper <= type(uint128).max);
        vm.assume(sqrtPriceX96 >= 1 << 48 && sqrtPriceX96 <= type(uint128).max && shares <= supply);
        vm.assume(supply != 0 && supply <= type(uint128).max);
        Snapshot memory snapshot = oneRange(liquidity, lower, upper, idle0, idle1, supply);

        // When: Taking the mint's tokenOut with its margins, and without.
        (uint256 amountOut,) = MintOptimizationMath.getMintAmountOut(snapshot, sqrtPriceX96, zeroForOne, shares);
        (, uint256 amountMintOut,) = SnapshotLib.getMintAmounts(snapshot, sqrtPriceX96, shares, zeroForOne);

        // Then: It is zero exactly when the mint takes no tokenOut.
        assertEq(amountOut == 0, amountMintOut == 0);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getMintAmountOut_IsAtLeastTheMintsTokenOutPlusTheRangeCount(
        uint128 liquidity,
        uint160 lower,
        uint160 upper,
        uint160 sqrtPriceX96,
        uint128 idle0,
        uint128 idle1,
        uint256 shares,
        uint256 supply,
        bool zeroForOne
    ) public pure {
        // Given: One range, idle, a tokenOut mint, uint128 supply, price 2^48 to 2^128.
        vm.assume(lower >= 1 << 48 && lower < upper && upper <= type(uint128).max);
        vm.assume(sqrtPriceX96 >= 1 << 48 && sqrtPriceX96 <= type(uint128).max && shares <= supply);
        vm.assume(supply != 0 && supply <= type(uint128).max);
        Snapshot memory snapshot = oneRange(liquidity, lower, upper, idle0, idle1, supply);
        (, uint256 amountMintOut, uint256 activeLiquidityDelta) =
            SnapshotLib.getMintAmounts(snapshot, sqrtPriceX96, shares, zeroForOne);
        vm.assume(amountMintOut != 0);

        // When: Taking the mint's tokenOut with its margins.
        (uint256 amountOut, uint256 activeLiquidityDelta_) =
            MintOptimizationMath.getMintAmountOut(snapshot, sqrtPriceX96, zeroForOne, shares);

        // Then: At least the mint's tokenOut plus one per range, its liquidity in range.
        assertGe(amountOut, amountMintOut + 1);
        assertEq(activeLiquidityDelta_, activeLiquidityDelta);
    }
}
