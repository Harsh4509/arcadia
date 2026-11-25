/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EmissionsLogic } from "../../../src/core/libraries/logic/EmissionsLogic.sol";
import { EmissionsLogicExtension } from "../../utils/extensions/EmissionsLogicExtension.sol";
import { IMetadexCLGauge } from "../../../src/interfaces/IMetadexCLGauge.sol";
import { IMetadexCLGaugeFactory } from "../../../src/interfaces/IMetadexCLGaugeFactory.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic tests for the function "isPenaltyWindowOpen" of library "EmissionsLogic".
 */
contract IsOpen_EmissionsLogic_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_isPenaltyWindowOpen_ClosesAtTheBoundary(
        uint256 stakedBlock,
        uint256 minStakeBlocks,
        uint256 penaltyRate
    ) public {
        // Given: A live config on a staked range, at the first block outside the window.
        vm.assume(stakedBlock != 0 && penaltyRate != 0 && minStakeBlocks != 0);
        vm.assume(stakedBlock <= type(uint256).max - minStakeBlocks);
        vm.roll(stakedBlock + minStakeBlocks);

        // When: The window is checked.
        // Then: It is closed.
        assertFalse(
            EmissionsLogic.isPenaltyWindowOpen(
                stakedBlock, IMetadexCLGaugeFactory.PenaltyConfig(minStakeBlocks, penaltyRate), block.number
            )
        );
    }

    function prove_isPenaltyWindowOpen_NeverReopensAtALaterBlock(
        uint256 stakedBlock,
        IMetadexCLGaugeFactory.PenaltyConfig memory config,
        uint256 earlierBlock,
        uint256 laterBlock
    ) public pure {
        // Given: Any config whose window end fits uint256, and two blocks in order.
        vm.assume(stakedBlock <= type(uint256).max - config.minStakeBlocks && earlierBlock <= laterBlock);

        // When: The window is checked at both blocks.
        bool openEarlier = EmissionsLogic.isPenaltyWindowOpen(stakedBlock, config, earlierBlock);
        bool openLater = EmissionsLogic.isPenaltyWindowOpen(stakedBlock, config, laterBlock);

        // Then: It is open at the later block only if it is open at the earlier one.
        assertTrue(!openLater || openEarlier);
    }

    function prove_isPenaltyWindowOpen_NeverOpensWithoutAConfig(uint256 stakedBlock, uint256 blockNumber) public {
        // Given: A range staked at or before the block, and a config with either leg off.
        vm.assume(stakedBlock <= blockNumber);
        vm.roll(blockNumber);

        // When: The window is checked.
        // Then: It is closed either way.
        assertFalse(
            EmissionsLogic.isPenaltyWindowOpen(stakedBlock, IMetadexCLGaugeFactory.PenaltyConfig(0, 1), block.number)
        );
        assertFalse(
            EmissionsLogic.isPenaltyWindowOpen(stakedBlock, IMetadexCLGaugeFactory.PenaltyConfig(1, 0), block.number)
        );
    }
}

/**
 * @notice Symbolic tests for the function "getHiddenEmissions" of library "EmissionsLogic".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetHiddenEmissions_EmissionsLogic_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    address internal constant GAUGE = address(0x6A);
    address internal constant GAUGE_FACTORY = address(0x6F);
    address internal constant LEAF_VOTER = address(0x1F);
    address internal constant POOL = address(0x70);

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    EmissionsLogicExtension internal emissionsLogic;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        emissionsLogic = new EmissionsLogicExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_getHiddenEmissions_OneStakedSide_HidesAtMostThePenaltysCut(
        uint128 stakedLiquidity,
        uint48 stakedBlock,
        uint48 minStakeBlocks,
        uint256 penaltyRate,
        uint256 share,
        uint256 rewardGrowthGlobalX128,
        uint128 rewardGrowthDeltaX128,
        uint256 rewardGrowthSnapshotX128,
        uint256 blockNumber
    ) public {
        // Given: A staked side in its penalty window, rates < 1, accrual since snapshot.
        vm.assume(penaltyRate <= 1e6 && share <= 1e6 && minStakeBlocks != 0 && penaltyRate != 0);
        vm.assume(uint256(stakedBlock) + minStakeBlocks <= type(uint48).max);
        vm.assume(blockNumber >= stakedBlock && blockNumber < uint256(stakedBlock) + minStakeBlocks);
        vm.roll(blockNumber);
        emissionsLogic.pushRange(Range(0, 0, 0, stakedLiquidity, 1, stakedBlock));
        vm.mockCall(GAUGE, abi.encodeCall(IMetadexCLGauge.pool, ()), abi.encode(POOL));
        vm.mockCall(POOL, abi.encodeCall(IMetadexCLPool.stakedLiquidity, ()), abi.encode(uint128(0)));
        vm.mockCall(
            GAUGE_FACTORY,
            abi.encodeCall(IMetadexCLGaugeFactory.effectivePenaltyConfig, (GAUGE)),
            abi.encode(IMetadexCLGaugeFactory.PenaltyConfig(minStakeBlocks, penaltyRate))
        );
        vm.mockCall(
            GAUGE_FACTORY, abi.encodeCall(IMetadexCLGaugeFactory.referralConfig, (GAUGE)), abi.encode(address(0), share)
        );
        vm.mockCall(POOL, abi.encodeCall(IMetadexCLPool.rewardGrowthGlobalX128, ()), abi.encode(rewardGrowthGlobalX128));
        vm.mockCall(
            POOL,
            abi.encodeCall(IMetadexCLPool.getRewardGrowthInside, (0, 0, rewardGrowthGlobalX128)),
            abi.encode(rewardGrowthSnapshotX128 + rewardGrowthDeltaX128)
        );
        vm.mockCall(
            GAUGE, abi.encodeCall(IMetadexCLGauge.rewardGrowthInside, (1)), abi.encode(rewardGrowthSnapshotX128)
        );
        uint256 accrued = uint256(rewardGrowthDeltaX128) * stakedLiquidity >> 128;
        uint256 visible = accrued - accrued * penaltyRate / 1e6;

        // When: Taking the hidden emissions.
        (uint256 hidden, uint48 windowEnd) = emissionsLogic.getHiddenEmissions(GAUGE, GAUGE_FACTORY, LEAF_VOTER);

        // Then: At most the penalty's cut of accrued emissions, window ends with side's.
        assertLe(hidden, accrued - visible);
        assertEq(windowEnd, uint256(stakedBlock) + minStakeBlocks);
    }
}
