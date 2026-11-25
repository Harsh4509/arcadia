/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";
import { Claimable } from "../../../../src/core/types/State.sol";
import { Constants } from "../../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Plan } from "../../../utils/Plan.sol";

/**
 * @notice Fuzz tests for the function "getClaimableRedeem" of library "ALMCoreViewLogic".
 */
contract GetClaimableRedeem_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getClaimableRedeem_ZeroBeforeSettlement(PoolState memory poolState, uint256 shares)
        public
    {
        // Given: A redeem recorded but not settled.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        recordRedeemAt(asyncVault0, controller, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));

        // When: Reading the claimable side.
        (uint128 amountIn, uint128 amountOut) =
            coreViewLogic.getClaimableRedeem(address(almCore), asyncVault0, controller);

        // Then: Nothing is claimable.
        assertEq(amountIn, 0);
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_getClaimableRedeem_IsWhatSettlementCredits(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests with a token0 redeem its buffer pays, the keeper settled.
        givenValidQueueState(queueState, 0, 0);
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        uint256 value =
            amount1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
        uint256 ceiling = FixedPointMathLib.min(
            almCore.balanceOf(users.steward) / 2,
            token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()).fullMulDiv(almCore.totalSupply(), value)
        );
        queueState.redeem0 = bound(queueState.redeem0, 0, ceiling);
        setQueueState(queueState);
        uint256 escrowedBefore = almCore.getEscrowed0();
        runPlan(Plan.init().clearAllRequests(true, false).settleRequests());

        // When: Reading the claimable side.
        (uint128 amountIn, uint128 amountOut) =
            coreViewLogic.getClaimableRedeem(address(almCore), asyncVault0, controller);

        // Then: It is the settled shares and the token0 the settlement escrowed for them.
        assertEq(amountIn, queueState.redeem0);
        assertEq(amountOut, almCore.getEscrowed0() - escrowedBefore);
    }

    function testFuzz_Success_getClaimableRedeem_ReadsApartFromTheDepositSide(
        PoolState memory poolState,
        address vault,
        address controller_,
        Claimable memory deposit,
        Claimable memory redeem
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A claimable deposit and redeem for one vault and controller.
        almCore.setClaimableDeposit(vault, controller_, deposit);
        almCore.setClaimableRedeem(vault, controller_, redeem);

        // When: Reading the redeem queue.
        (uint128 amountIn, uint128 amountOut) = coreViewLogic.getClaimableRedeem(address(almCore), vault, controller_);

        // Then: Both halves read back, free of the deposit queue.
        assertEq(amountIn, redeem.amountIn);
        assertEq(amountOut, redeem.amountOut);
    }
}
