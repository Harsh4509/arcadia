/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { IMetadexCLGauge } from "../../../../src/interfaces/IMetadexCLGauge.sol";
import { Range } from "../../../../src/core/types/Range.sol";
import { RewardsLib_Fuzz_Test } from "./_RewardsLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claimGaugeEmissions" of library "RewardsLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ClaimGaugeEmissions_RewardsLib_Fuzz_Test is RewardsLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(RewardsLib_Fuzz_Test) {
        RewardsLib_Fuzz_Test.setUp();
        setSpotPoolState();
        deployRewardsLib();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_claimGaugeEmissions_ClaimsRangesPastTheWindow(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 emissions
    ) public {
        // Given: A penalty config, and a range the library staked.
        minStakeBlocks = bound(minStakeBlocks, 0, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 0, MAX_PIPS));
        liquidity = uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())));
        Range memory range = stakeIntoRange(pool, gauge, address(rewardsLib), TICK_LOWER, TICK_UPPER, liquidity);
        rewardsLib.pushRange(range);

        // And: Its window passed, with emissions accrued.
        closePenaltyWindow(gauge);
        addEmissionsToGaugeCL(pool, gauge, bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = range.stakedTokenId;
        uint256 earned = gauge.earned(address(rewardsLib), tokenIds);
        uint256 balance = IERC20(almCore.REWARD_TOKEN_()).balanceOf(address(rewardsLib));

        // When: Claiming the gauge emissions.
        bool skipped = rewardsLib.claimGaugeEmissions();

        // Then: Nothing is skipped and the earned emissions are paid to the library.
        assertFalse(skipped);
        assertEq(IERC20(almCore.REWARD_TOKEN_()).balanceOf(address(rewardsLib)), balance + earned);
        assertEq(gauge.earned(address(rewardsLib), tokenIds), 0);
    }

    function testFuzz_Success_claimGaugeEmissions_SkipsRangesInsideTheWindow(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A live penalty config, and a range the library staked.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 1, MAX_PIPS));
        liquidity = uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())));
        Range memory range = stakeIntoRange(pool, gauge, address(rewardsLib), TICK_LOWER, TICK_UPPER, liquidity);
        rewardsLib.pushRange(range);

        // And: Emissions accrued inside its window.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = range.stakedTokenId;
        uint256 earned = gauge.earned(address(rewardsLib), tokenIds);
        uint256 balance = IERC20(almCore.REWARD_TOKEN_()).balanceOf(address(rewardsLib));

        // When: Claiming the gauge emissions.
        bool skipped = rewardsLib.claimGaugeEmissions();

        // Then: The range is skipped, its emissions left in the gauge.
        assertTrue(skipped);
        assertEq(IERC20(almCore.REWARD_TOKEN_()).balanceOf(address(rewardsLib)), balance);
        assertEq(gauge.earned(address(rewardsLib), tokenIds), earned);
    }

    function testFuzz_Success_claimGaugeEmissions_NothingToClaim(uint256 minStakeBlocks, uint256 penaltyRate) public {
        // Given: Any penalty config, no staked range and nothing deferred at the gauge.
        setPenaltyConfig(bound(minStakeBlocks, 0, type(uint32).max), bound(penaltyRate, 0, MAX_PIPS));

        // When: Claiming the gauge emissions.
        // Then: The gauge is not called.
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.claimEmissions.selector), 0);
        assertFalse(rewardsLib.claimGaugeEmissions());
    }

    function testFuzz_Success_claimGaugeEmissions_ClaimsDeferredEmissions(uint256 deferred) public {
        // Given: No staked range, and emissions deferred at the gauge.
        vm.mockCall(
            address(gauge),
            abi.encodeCall(IMetadexCLGauge.deferredEmissions, (address(rewardsLib))),
            abi.encode(bound(deferred, 1, type(uint128).max))
        );

        // When: Claiming the gauge emissions.
        // Then: The gauge is called with no token ids.
        uint256[] memory tokenIds;
        bytes memory claim =
            abi.encodeCall(IMetadexCLGauge.claimEmissions, (address(rewardsLib), address(rewardsLib), tokenIds));
        vm.mockCall(address(gauge), claim, "");
        vm.expectCall(address(gauge), claim);
        assertFalse(rewardsLib.claimGaugeEmissions());
    }
}
