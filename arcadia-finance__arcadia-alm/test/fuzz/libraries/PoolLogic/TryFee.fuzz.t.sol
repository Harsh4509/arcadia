/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IMetadexCLPool } from "../../../../src/interfaces/IMetadexCLPool.sol";
import { PoolLogic_Fuzz_Test } from "./_PoolLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "tryFee" of library "PoolLogic".
 */
contract TryFee_PoolLogic_Fuzz_Test is PoolLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_tryFee_HookAnswers(PoolState memory poolState) public {
        // Given: A pool with depth.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: Reading the fee.
        (bool ok, uint24 fee) = poolLogic.tryFee(address(pool));

        // Then: It is read, at the pool's own fee.
        assertTrue(ok);
        assertEq(fee, pool.fee());
    }

    function testFuzz_Success_tryFee_FeeReadReverts(PoolState memory poolState) public {
        // Given: A pool with depth whose fee read reverts.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.mockCallRevert(address(pool), abi.encodeWithSelector(IMetadexCLPool.fee.selector), "");

        // When: Reading the fee.
        (bool ok, uint24 fee) = poolLogic.tryFee(address(pool));

        // Then: It is not read, the fee is zero, and the call does not revert.
        assertFalse(ok);
        assertEq(fee, 0);
    }
}
