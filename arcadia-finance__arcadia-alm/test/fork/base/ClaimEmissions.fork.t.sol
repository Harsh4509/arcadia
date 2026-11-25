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
import { ICLGaugeFactory } from "../../utils/fixtures/metadex/interfaces/ICLGaugeFactory.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { Plan } from "../../utils/Plan.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";

/**
 * @notice Fork tests for the function "claimEmissions" of contract "ALMCore", on Base.
 */
contract ClaimEmissions_Base_Fork_Test is Base_Fork_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    uint256 internal constant BLOCK_TIME = 2;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFork_Success_claimEmissions_StakedRangePastItsPenaltyWindow(
        uint256 openBps,
        uint256 protocolEmissionFeeBps
    ) public {
        // Given: A core worth 100k USDC of each token, with a protocol share of its emissions.
        seedCore(CLMath.convert(sqrtPriceX96(pool), false, 100_000e6, false), 100_000e6);
        protocolEmissionFeeBps = bound(protocolEmissionFeeBps, 0, almCore.MAX_FEE_BPS_());
        vm.prank(address(deployer));
        almCore.setProtocolFees(uint16(protocolEmissionFeeBps), 0, feeRecipient);

        // And: A range 20 spacings either side of spot, a share of the buffer unstaked and the rest staked.
        openBps = bound(openBps, 1, ConfigLib.BPS_DENOMINATOR - 1);
        runStagingPlan(
            Plan.init()
                .openRange(
                    spacedTick(-20),
                    spacedTick(20),
                    Sentinels.OPEN_BALANCE | openBps,
                    Sentinels.OPEN_BALANCE | openBps,
                    0,
                    0
                )
                .stake(
                    0,
                    Sentinels.OPENED,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    0,
                    0
                )
        );

        // And: The first block past the live gauge's penalty window, at Base's block time.
        {
            uint256 minStakeBlocks =
                ICLGaugeFactory(METADEX_CL_GAUGE_FACTORY).effectivePenaltyConfig(GAUGE_CL50_WETH_USDC).minStakeBlocks;
            vm.roll(almCore.getRange(0).stakedBlock + minStakeBlocks);
            vm.warp(vm.getBlockTimestamp() + minStakeBlocks * BLOCK_TIME);
        }
        uint256 earned = ICLGauge(GAUGE_CL50_WETH_USDC).earned(address(almCore), almCore.stakedTokenIds());
        uint256 net = earned - earned.fullMulDiv(protocolEmissionFeeBps, ConfigLib.BPS_DENOMINATOR);
        uint256 owed = net.fullMulDiv(almCore.balanceOf(steward), almCore.totalSupply());

        // When: Anyone claims the steward's emissions.
        vm.prank(depositor);
        uint256 paid = almCore.claimEmissions(steward);

        // Then: The gauge paid the core all it earned.
        assertGt(earned, 0);
        assertEq(ICLGauge(GAUGE_CL50_WETH_USDC).earned(address(almCore), almCore.stakedTokenIds()), 0);
        assertEq(IERC20(AERO).balanceOf(address(almCore)), earned - paid);

        // And: The steward got its pro-rata share of the net, short of a wei of reward per share.
        assertEq(IERC20(AERO).balanceOf(steward), paid);
        assertLe(paid, owed);
        assertGe(paid + 1, owed);

        // And: The protocol share is booked.
        assertEq(almCore.getProtocolFeesReward(), earned - net);
    }
}
