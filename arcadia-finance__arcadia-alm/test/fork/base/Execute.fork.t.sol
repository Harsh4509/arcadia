/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Base_Fork_Test } from "./_Base.fork.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { ICLGauge } from "../../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { Plan } from "../../utils/Plan.sol";
import { PoolLogic } from "../../../src/shared/libraries/logic/PoolLogic.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";

/**
 * @notice Fork tests for the function "execute" of contract "ALMCore", on Base.
 */
contract Execute_Base_Fork_Test is Base_Fork_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFork_Success_execute_ClearsSwapsOpensAndStakes(
        uint256 assets,
        uint256 shares,
        uint256 swapBps,
        uint256 openBps,
        uint256 maxShortfallBps,
        uint256 maxSwapCostBps
    ) public {
        // Given: A core worth 100k USDC of each token, in its buffer.
        seedCore(CLMath.convert(sqrtPriceX96(pool), false, 100_000e6, false), 100_000e6);

        // And: A WETH deposit request of 10 USDC to 100k USDC of value.
        assets = bound(
            assets,
            CLMath.convert(sqrtPriceX96(pool), false, 10e6, false),
            CLMath.convert(sqrtPriceX96(pool), false, 100_000e6, false)
        );
        deal(address(token0), depositor, assets);
        vm.startPrank(depositor);
        token0.approve(address(asyncVault0), assets);
        asyncVault0.requestDeposit(assets, depositor, depositor);
        vm.stopPrank();

        // And: A USDC redeem request of the steward, of one share up to what the USDC buffer pays.
        {
            uint256 value =
                almCore.bufferAmount1() + CLMath.convert(sqrtPriceX96(pool), true, almCore.bufferAmount0(), false);
            shares = bound(shares, 1, almCore.bufferAmount1().fullMulDiv(almCore.totalSupply(), value));
        }
        vm.startPrank(steward);
        almCore.approve(address(asyncVault1), shares);
        asyncVault1.requestRedeem(shares, steward, steward);
        vm.stopPrank();

        // And: A sale of a share of the open WETH, a range 20 spacings either side of spot opened with a share.
        openBps = Sentinels.OPEN_BALANCE | bound(openBps, 1, ConfigLib.BPS_DENOMINATOR - 1);
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .clearAllRequests(false, false)
            .swapViaPool(
                true,
                Sentinels.OPEN_BALANCE | bound(swapBps, 1, ConfigLib.BPS_DENOMINATOR - 1),
                PoolLogic.sqrtPriceLimit(true),
                0
            )
            .settleRequests();

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            (uint256 amountIn, uint256 amountOut) = planSwap(plan, true);
            uint256 value = CLMath.convert(sqrtPriceX96(pool), true, amountIn, false);
            setPlanLimits(
                maxShortfallBps,
                maxSwapCostBps,
                5,
                (value + 2).zeroFloorSub(amountOut),
                value > amountOut ? (value - amountOut).fullMulDivUp(ConfigLib.BPS_DENOMINATOR, value) : 0
            );
        }
        plan = plan.openRange(spacedTick(-20), spacedTick(20), openBps, openBps, 0, 0)
            .stake(
                0,
                Sentinels.OPENED,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                0,
                0
            );
        uint256 stakedLiquidity = pool.stakedLiquidity();

        // When: The keeper clears both queues, sells WETH, opens the range and stakes the rest of the buffer.
        runPlan(plan);

        // Then: Both requests are claimable.
        assertEq(asyncVault0.pendingDepositRequest(0, depositor), 0);
        assertEq(asyncVault0.claimableDepositRequest(0, depositor), assets);
        assertEq(asyncVault1.pendingRedeemRequest(0, steward), 0);
        assertEq(asyncVault1.claimableRedeemRequest(0, steward), shares);

        // And: The range's staked side is deposited in the live gauge and in range at the pool.
        Range memory range = almCore.getRange(0);
        assertGt(range.unstakedTokenId, 0);
        assertTrue(ICLGauge(GAUGE_CL50_WETH_USDC).stakedContains(address(almCore), range.stakedTokenId));
        assertEq(pool.stakedLiquidity(), stakedLiquidity + range.stakedLiquidity);
    }
}
