/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { Plan } from "../../utils/Plan.sol";

/**
 * @notice Fuzz tests for the function "receive" of contract "ALMCore".
 */
contract Receive_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_receive(PoolState memory poolState, address sender, uint256 amount) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A sender holding ether.
        amount = bound(amount, 1, type(uint128).max);
        vm.deal(sender, amount);
        uint256 balance = address(almCore).balance;

        // When: It sends the core ether.
        vm.prank(sender);
        (bool success,) = address(almCore).call{ value: amount }("");

        // Then: The core holds it.
        assertTrue(success);
        assertEq(address(almCore).balance, balance + amount);
    }

    function testFuzz_Success_receive_MintWithEtherInThePositionManager(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 stray
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        shares = bound(shares, 2, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        vm.stopPrank();

        // And: Ether forced into the position manager.
        stray = bound(stray, 1, type(uint128).max);
        vm.deal(address(POSITION_MANAGER), stray);

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        vm.prank(users.unprivilegedAddress);
        almCore.mint(shares, users.unprivilegedAddress);

        // Then: The position manager refunded the ether to the core.
        assertEq(address(POSITION_MANAGER).balance, 0);
        assertEq(address(almCore).balance, stray);
    }

    function testFuzz_Success_receive_OpenRangeWithEtherInThePositionManager(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 stray,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: The buffer holds the amounts the range needs.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundBuffer(amount0, amount1);

        // And: Ether forced into the position manager.
        stray = bound(stray, 1, type(uint128).max);
        vm.deal(address(POSITION_MANAGER), stray);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager calls openRange().
        runPlan(Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0));

        // Then: The range is opened and the position manager refunded the ether.
        assertEq(almCore.getRangesLength(), 1);
        assertEq(address(POSITION_MANAGER).balance, 0);
        assertEq(address(almCore).balance, stray);
    }
}
