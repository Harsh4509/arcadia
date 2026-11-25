/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { RangesLib_Fuzz_Test } from "./_RangesLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "unstake" of library "RangesLib".
 */
contract Unstake_RangesLib_Fuzz_Test is RangesLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_unstake_WithdrawsFromTheGauge(
        PoolState memory poolState,
        RangeState memory range,
        uint32 blocks
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployRangesLib();

        // And: A range whose staked side sits in the gauge, any number of blocks later.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        pushRangeOf(range);
        vm.roll(vm.getBlockNumber() + blocks);

        // When: Unstaking the staked side.
        rangesLib.unstake(range.stakedTokenId);

        // Then: The gauge no longer holds it and the ranges own it again.
        assertFalse(gauge.stakedContains(address(rangesLib), range.stakedTokenId));
        assertEq(POSITION_MANAGER.ownerOf(range.stakedTokenId), address(rangesLib));

        // And: The range is untouched.
        assertEq(rangesLib.getRange(range.index).stakedTokenId, range.stakedTokenId);
        assertEq(rangesLib.getRange(range.index).stakedLiquidity, range.liquidityStaked);
    }
}
