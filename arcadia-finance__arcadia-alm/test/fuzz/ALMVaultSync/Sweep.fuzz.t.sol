/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the function "sweep" of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(reentrancy-events, unused-return)
contract Sweep_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_sweep_HandsTheBalancesToTheProtocol(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 dust0,
        uint256 dust1,
        address caller,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, left with some of each token.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        dust0 = bound(dust0, 0, Constants.MAX_FUZZED_AMOUNT);
        dust1 = bound(dust1, 0, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(address(vault), dust0);
        token1.mint(address(vault), dust1);
        uint256 owed0Before = almCore.getProtocolFees0();
        uint256 owed1Before = almCore.getProtocolFees1();
        uint256 core0Before = token0.balanceOf(address(almCore));
        uint256 core1Before = token1.balanceOf(address(almCore));

        // When: Anyone sweeps.
        vm.prank(caller);
        vm.expectEmit(address(vault));
        emit ALMVaultSync.Swept(dust0, dust1);
        (uint256 amount0, uint256 amount1) = vault.sweep();

        // Then: The vault holds none of either token any more.
        assertEq(amount0, dust0);
        assertEq(amount1, dust1);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);

        // And: The core holds both, accrued to the protocol rather than to the holders.
        assertEq(token0.balanceOf(address(almCore)), core0Before + dust0);
        assertEq(token1.balanceOf(address(almCore)), core1Before + dust1);
        assertEq(almCore.getProtocolFees0(), owed0Before + dust0);
        assertEq(almCore.getProtocolFees1(), owed1Before + dust1);
    }

    function testFuzz_Success_sweep_NothingToSweep(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address caller,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, holding none of either token.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        uint256 core0Before = token0.balanceOf(address(almCore));
        uint256 core1Before = token1.balanceOf(address(almCore));

        // When: Anyone sweeps.
        vm.prank(caller);
        (uint256 amount0, uint256 amount1) = vault.sweep();

        // Then: Nothing moved.
        assertEq(amount0, 0);
        assertEq(amount1, 0);
        assertEq(token0.balanceOf(address(almCore)), core0Before);
        assertEq(token1.balanceOf(address(almCore)), core1Before);
    }
}
