/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { EmissionsLogic_Fuzz_Test } from "./_EmissionsLogic.fuzz.t.sol";
import { IArbSys } from "../../../../src/interfaces/IArbSys.sol";
import { ICLGaugeFactory } from "../../../utils/fixtures/metadex/interfaces/ICLGaugeFactory.sol";
import { IMetadexCLGaugeFactory } from "../../../../src/interfaces/IMetadexCLGaugeFactory.sol";

/**
 * @notice Fuzz tests for the function "isPenaltyWindowOpen" of library "EmissionsLogic".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract IsPenaltyWindowOpen_EmissionsLogic_Fuzz_Test is EmissionsLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(EmissionsLogic_Fuzz_Test) {
        EmissionsLogic_Fuzz_Test.setUp();
        deployStakedPool();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isPenaltyWindowOpen_Config_PenaltyRateZero(uint256 stakedBlock, uint256 minStakeBlocks)
        public
    {
        // Given: A config with a zero penalty rate, whatever the window length.
        minStakeBlocks = bound(minStakeBlocks, 1, MAX_MIN_STAKE_BLOCKS);
        IMetadexCLGaugeFactory.PenaltyConfig memory config =
            IMetadexCLGaugeFactory.PenaltyConfig({ minStakeBlocks: minStakeBlocks, penaltyRate: 0 });

        // And: A range staked in the current block.
        stakedBlock = bound(stakedBlock, 1, type(uint64).max);
        vm.roll(stakedBlock);

        // When: Checking the window.
        // Then: It is closed.
        assertFalse(emissionsLogic.isPenaltyWindowOpen(stakedBlock, config, false));
    }

    function testFuzz_Success_isPenaltyWindowOpen_Config_PenaltyRateZeroPastTheWindow(
        uint256 stakedBlock,
        uint256 minStakeBlocks,
        uint256 blocksPassed
    ) public {
        // Given: A config with a zero penalty rate, whatever the window length.
        minStakeBlocks = bound(minStakeBlocks, 0, type(uint64).max);
        IMetadexCLGaugeFactory.PenaltyConfig memory config =
            IMetadexCLGaugeFactory.PenaltyConfig({ minStakeBlocks: minStakeBlocks, penaltyRate: 0 });

        // And: At least the window has passed since the stake.
        stakedBlock = bound(stakedBlock, 1, type(uint64).max);
        vm.roll(stakedBlock + bound(blocksPassed, minStakeBlocks, type(uint64).max));

        // When: Checking the window.
        // Then: It is closed.
        assertFalse(emissionsLogic.isPenaltyWindowOpen(stakedBlock, config, false));
    }

    function testFuzz_Success_isPenaltyWindowOpen_Config_MinStakeBlocksZero(uint256 stakedBlock, uint256 penaltyRate)
        public
    {
        // Given: A config with a zero window, whatever the penalty rate.
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        IMetadexCLGaugeFactory.PenaltyConfig memory config =
            IMetadexCLGaugeFactory.PenaltyConfig({ minStakeBlocks: 0, penaltyRate: penaltyRate });

        // And: A range staked in the current block.
        stakedBlock = bound(stakedBlock, 1, type(uint64).max);
        vm.roll(stakedBlock);

        // When: Checking the window.
        // Then: It is closed.
        assertFalse(emissionsLogic.isPenaltyWindowOpen(stakedBlock, config, false));
    }

    function testFuzz_Success_isPenaltyWindowOpen_Config_InsideWindow(
        uint256 stakedBlock,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocksPassed
    ) public {
        // Given: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, MAX_MIN_STAKE_BLOCKS);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        IMetadexCLGaugeFactory.PenaltyConfig memory config =
            IMetadexCLGaugeFactory.PenaltyConfig({ minStakeBlocks: minStakeBlocks, penaltyRate: penaltyRate });

        // And: Fewer blocks than the window have passed since the stake.
        stakedBlock = bound(stakedBlock, 1, type(uint64).max);
        blocksPassed = bound(blocksPassed, 0, minStakeBlocks - 1);
        vm.roll(stakedBlock + blocksPassed);

        // When: Checking the window.
        // Then: It is open.
        assertTrue(emissionsLogic.isPenaltyWindowOpen(stakedBlock, config, false));
    }

    function testFuzz_Success_isPenaltyWindowOpen_Config_AtOrAfterBoundary(
        uint256 stakedBlock,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocksPassed
    ) public {
        // Given: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint64).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        IMetadexCLGaugeFactory.PenaltyConfig memory config =
            IMetadexCLGaugeFactory.PenaltyConfig({ minStakeBlocks: minStakeBlocks, penaltyRate: penaltyRate });

        // And: At least the window has passed.
        stakedBlock = bound(stakedBlock, 1, type(uint64).max);
        blocksPassed = bound(blocksPassed, minStakeBlocks, type(uint64).max);

        // When: Checking the window exactly at the boundary.
        vm.roll(stakedBlock + minStakeBlocks);

        // Then: The strict comparison has already closed it.
        assertFalse(emissionsLogic.isPenaltyWindowOpen(stakedBlock, config, false));

        // When: Checking it again further out.
        vm.roll(stakedBlock + blocksPassed);

        // Then: It is still closed.
        assertFalse(emissionsLogic.isPenaltyWindowOpen(stakedBlock, config, false));
    }

    function testFuzz_Success_isPenaltyWindowOpen_MatchesTheGauge(
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocksPassed,
        uint256 emissions
    ) public {
        // Given: A penalty config, either leg possibly switched off.
        minStakeBlocks = bound(minStakeBlocks, 0, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, bound(penaltyRate, 0, MAX_PIPS));

        // And: A staked full-range position of up to the tick cap.
        uint256[] memory tokenIds = new uint256[](1);
        (tokenIds[0],) = mintPosition(
            pool,
            users.liquidityProvider,
            TICK_LOWER,
            TICK_UPPER,
            uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())))
        );
        stake(gauge, users.liquidityProvider, tokenIds[0]);

        // And: Emissions any penalty rate hides a unit of, settled in or past the window.
        accrueForBlocks(
            pool,
            gauge,
            bound(blocksPassed, 0, type(uint32).max),
            bound(emissions, MAX_PIPS + 1, Constants.MAX_EMISSIONS)
        );

        // When: Checking the window at the gauge's own config.
        ICLGaugeFactory.PenaltyConfig memory config = clGaugeFactory.effectivePenaltyConfig(address(gauge));
        bool open = emissionsLogic.isPenaltyWindowOpen(
            gauge.depositBlock(tokenIds[0]),
            IMetadexCLGaugeFactory.PenaltyConfig(config.minStakeBlocks, config.penaltyRate),
            false
        );

        // Then: It is open exactly when the gauge hides part of the emissions.
        assertEq(open, hiddenEmissions(gauge, users.liquidityProvider, tokenIds) > 0);
    }

    function testFuzz_Success_isPenaltyWindowOpen_ArbBlockNumber(
        uint256 stakedBlock,
        uint256 minStakeBlocks,
        uint256 penaltyRate,
        uint256 blocksInside,
        uint256 blocksPassed
    ) public {
        // Given: A live penalty config.
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint64).max);
        penaltyRate = bound(penaltyRate, 1, MAX_PIPS);
        IMetadexCLGaugeFactory.PenaltyConfig memory config =
            IMetadexCLGaugeFactory.PenaltyConfig({ minStakeBlocks: minStakeBlocks, penaltyRate: penaltyRate });

        // And: A range staked at an ArbSys block, the chain's own block past its window.
        stakedBlock = bound(stakedBlock, 1, type(uint64).max);
        vm.roll(stakedBlock + bound(blocksPassed, minStakeBlocks, type(uint64).max));
        vm.etch(address(0x64), hex"00");
        uint256 arbBlockNumber = stakedBlock + bound(blocksInside, 0, minStakeBlocks - 1);
        vm.mockCall(address(0x64), abi.encodeCall(IArbSys.arbBlockNumber, ()), abi.encode(arbBlockNumber));

        // When: Checking the window in ArbSys blocks.
        // Then: It is open.
        assertTrue(emissionsLogic.isPenaltyWindowOpen(stakedBlock, config, true));

        // And: It is closed in the chain's own blocks.
        assertFalse(emissionsLogic.isPenaltyWindowOpen(stakedBlock, config, false));
    }
}
