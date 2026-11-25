/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { ILeafVoter } from "../../utils/fixtures/metadex/interfaces/ILeafVoter.sol";
import { IMetadexCLGauge } from "../../../src/interfaces/IMetadexCLGauge.sol";

/**
 * @notice Fuzz tests for the function "claimEmissions" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast, divide-before-multiply, reentrancy-events, unused-return)
contract ClaimEmissions_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_claimEmissions_PaysTheRewardBalance(
        PoolState memory poolState,
        uint96 credited,
        uint96 protocolFees,
        uint96 balance
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A credit larger than the reward balance, whatever the protocol fees.
        credited = uint96(bound(credited, 1, type(uint96).max));
        balance = uint96(bound(balance, 0, uint256(credited) - 1));
        deal(almCore.REWARD_TOKEN_(), address(almCore), balance);
        almCore.setFeesOwed(0, 0, protocolFees);
        almCore.setPendingReward(accountA, credited);

        // And: The recorded balance matches, so no reward accrues.
        almCore.setRewardAccounting(0, 0, 0, balance);

        // When: Calling claimEmissions().
        uint256 amount = almCore.claimEmissions(accountA);

        // Then: The account is paid the whole reward balance, and the rest stays owed.
        assertEq(amount, balance);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), balance);
        assertEq(almCore.getPendingReward(accountA), uint256(credited) - balance);
        assertEq(almCore.getLastRewardBalance(), 0);
    }

    function testFuzz_Success_claimEmissions_PaysAccountWhoeverCalls(
        PoolState memory poolState,
        address caller,
        uint16 feeBps,
        uint96 shares,
        uint96 received,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The caller is not the vault itself.
        vm.assume(caller != address(almCore));

        // And: An emission fee within the ceiling.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);

        // And: A holder beside a seed keeping the reward per share a uint128, and reward.
        shares = uint96(bound(shares, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(
                uint256(type(uint96).max).fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES
            ) + 1,
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, shares);
        deal(almCore.REWARD_TOKEN_(), address(almCore), received);

        uint256 net = received - uint256(received) * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 delta = net.fullMulDiv(1e18, seedShares + shares);
        uint256 expected = uint256(shares).fullMulDiv(delta, 1e18);
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 protocolFees = almCore.getProtocolFeesReward();

        // When: Anyone calls claimEmissions() for the holder.
        vm.prank(caller);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.EmissionsClaimed(accountA, expected);
        uint256 amount = almCore.claimEmissions(accountA);

        // Then: The holder is paid and its credit is cleared.
        assertEq(amount, expected);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), expected);
        assertEq(almCore.getPendingReward(accountA), 0);
        assertEq(almCore.getLastRewardBalance(), received - expected);

        // And: The accumulator rose by the net, the fee accrued, the holder snapshotted.
        assertEq(almCore.rewardPerShare_(), rewardPerShare + delta);
        assertEq(almCore.getRewardHighWater(), highWater + net);
        assertEq(almCore.getProtocolFeesReward(), protocolFees + (received - net));
        assertEq(almCore.getRewardSnapshot(accountA), rewardPerShare + delta);
    }

    function testFuzz_Success_claimEmissions_ZeroPending(PoolState memory poolState, uint96 shares) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A holder with no accrual behind it.
        almCore.mintShares(accountA, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));

        // When: Calling claimEmissions().
        uint256 amount = almCore.claimEmissions(accountA);

        // Then: Nothing is paid.
        assertEq(amount, 0);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), 0);
    }

    function testFuzz_Success_claimEmissions_EmptySetSkipsGauge(PoolState memory poolState, uint96 shares) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A holder and no staked range, the gauge reverting on an empty claim set.
        almCore.mintShares(accountA, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));

        // When: Calling claimEmissions().
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.claimEmissions.selector), 0);
        uint256 amount = almCore.claimEmissions(accountA);

        // Then: The gauge was never asked to claim, and nothing is paid.
        assertEq(amount, 0);
    }

    function testFuzz_Success_claimEmissions_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it past its window, emissions up to the ceiling.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        addEmissionsToGaugeCL(pool, gauge, bound(emissions, 2, Constants.MAX_EMISSIONS));
        vm.roll(vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));
        uint256 earned = gauge.earned(address(almCore));

        // And: A paused core.
        vm.prank(factory);
        almCore.pause();

        // When: An account claims its emissions.
        almCore.claimEmissions(address(1));

        // Then: The delivered amount is recorded.
        assertEq(almCore.getClaimedCumulative(), earned);
    }

    function testFuzz_Success_claimEmissions_ClaimsTheGaugeOnlyWhileTheChainMints(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocks,
        uint256 emissions,
        bool mintable,
        uint256 pick
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault holding it past its penalty window, emissions accrued.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        accrueForBlocks(pool, gauge, bound(blocks, 1, type(uint32).max), bound(emissions, 2, Constants.MAX_EMISSIONS));

        // And: A chain status that either mints or does not.
        if (mintable) setMintableStatus(pick);
        else setNotMintableStatus(pick);
        uint256[] memory tokenIds = almCore.stakedTokenIds();
        uint256 earned = gauge.earned(address(almCore), tokenIds);
        uint256 net = earned - earned * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 claimedCumulative = almCore.getClaimedCumulative();
        uint256 lastRewardBalance = almCore.getLastRewardBalance();
        uint256 delta = net.fullMulDiv(1e18, coreState.supply);
        uint256 owed = almCore.balanceOf(users.steward).fullMulDiv(delta, 1e18);
        uint256 expected = mintable ? owed : 0;

        // When: The seed holder claims its emissions.
        uint256 amount = almCore.claimEmissions(users.steward);

        // Then: The gauge paid the core only while mintable, else the reward stays there.
        assertEq(gauge.earned(address(almCore), tokenIds), mintable ? 0 : earned);
        assertEq(almCore.getClaimedCumulative(), claimedCumulative + (mintable ? net : 0));
        assertEq(almCore.getLastRewardBalance(), lastRewardBalance + (mintable ? earned : 0) - expected);

        // And: The earned reward is credited on either status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare + delta);

        // And: The holder is paid its share only while mintable, the rest stays owed.
        assertEq(amount, expected);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(users.steward), expected);
        assertEq(almCore.getPendingReward(users.steward), owed - expected);
    }

    function testFuzz_Success_claimEmissions_PausedAccrualPaysProRataToTheBlocksHeld(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocksBefore,
        uint256 blocksAfter,
        uint256 emissions,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A vault holding it past its window, no emission fee, checkpointed Active.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        vm.prank(factory);
        almCore.setProtocolFees(0, 0, users.feeRecipient);
        almCore.checkpoint_();
        uint256 supply = almCore.totalSupply();
        uint256 held = almCore.balanceOf(users.steward);
        uint256 owed = almCore.getRewardOwed(users.steward);
        uint256 counted = gauge.earned(address(almCore), almCore.stakedTokenIds());

        // And: The chain paused, emissions accrued before and after a newcomer mints.
        setChainStatus(ILeafVoter.ChainStatus.Paused);
        emissions = bound(emissions, 2, Constants.MAX_EMISSIONS);
        accrueForBlocks(pool, gauge, bound(blocksBefore, 1, type(uint32).max), emissions);
        uint256 earnedBefore = gauge.earned(address(almCore), almCore.stakedTokenIds()) - counted;
        shares = bound(shares, 1, supply);
        almCore.mintShares(accountA, shares);
        accrueForBlocks(pool, gauge, bound(blocksAfter, 1, type(uint32).max), emissions);
        uint256 earnedAfter = gauge.earned(address(almCore), almCore.stakedTokenIds()) - counted - earnedBefore;

        // And: The reward owed, each accrual over the supply it accrued under.
        uint256 deltaBefore = earnedBefore.fullMulDiv(1e18, supply);
        uint256 deltaAfter = earnedAfter.fullMulDiv(1e18, supply + shares);
        uint256 owedSteward = owed + held.fullMulDiv(deltaBefore + deltaAfter, 1e18);
        uint256 owedNewcomer = shares.fullMulDiv(deltaAfter, 1e18);
        assertEq(almCore.getRewardOwed(users.steward), owedSteward);
        assertEq(almCore.getRewardOwed(accountA), owedNewcomer);

        // And: A claim during the pause pays nothing and keeps the credit.
        assertEq(almCore.claimEmissions(accountA), 0);
        assertEq(almCore.getPendingReward(accountA), owedNewcomer);

        // When: The chain resumes and both claim.
        setChainStatus(ILeafVoter.ChainStatus.Active);
        uint256 paidNewcomer = almCore.claimEmissions(accountA);
        uint256 paidSteward = almCore.claimEmissions(users.steward);

        // Then: Each is paid pro rata to the blocks it held.
        assertEq(paidNewcomer, owedNewcomer);
        assertEq(paidSteward, owedSteward);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), owedNewcomer);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(users.steward), owedSteward);
    }

    function testFuzz_Success_claimEmissions_SuspendedAccruesNothing(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocks,
        uint256 emissions,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A vault holding it past its window, no emission fee, checkpointed Active.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        vm.prank(factory);
        almCore.setProtocolFees(0, 0, users.feeRecipient);
        almCore.checkpoint_();
        uint256 supply = almCore.totalSupply();
        uint256 held = almCore.balanceOf(users.steward);
        uint256 owed = almCore.getRewardOwed(users.steward);
        uint256 counted = gauge.earned(address(almCore), almCore.stakedTokenIds());

        // And: Emissions accrued while Paused, then the chain Suspended.
        setChainStatus(ILeafVoter.ChainStatus.Paused);
        emissions = bound(emissions, 2, Constants.MAX_EMISSIONS);
        blocks = bound(blocks, 1, type(uint32).max);
        accrueForBlocks(pool, gauge, blocks, emissions);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds()) - counted;
        setChainStatus(ILeafVoter.ChainStatus.Suspended);

        // And: A newcomer minting while Suspended, more blocks passing without accrual.
        almCore.mintShares(accountA, bound(shares, 1, supply));
        accrueForBlocks(pool, gauge, blocks, emissions);
        assertEq(gauge.earned(address(almCore), almCore.stakedTokenIds()), counted + earned);

        // When: The chain resumes and both claim.
        setChainStatus(ILeafVoter.ChainStatus.Active);
        uint256 paidNewcomer = almCore.claimEmissions(accountA);
        uint256 paidSteward = almCore.claimEmissions(users.steward);

        // Then: The holder through the pause is paid it all, the newcomer nothing.
        assertEq(paidSteward, owed + held.fullMulDiv(earned.fullMulDiv(1e18, supply), 1e18));
        assertEq(paidNewcomer, 0);
    }

    function testFuzz_Success_claimEmissions_SunsetPaysWhatWasEarnedBefore(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocks,
        uint256 emissions,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A vault holding it past its window, no emission fee, checkpointed Active.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        vm.prank(factory);
        almCore.setProtocolFees(0, 0, users.feeRecipient);
        almCore.checkpoint_();
        uint256 supply = almCore.totalSupply();
        uint256 held = almCore.balanceOf(users.steward);
        uint256 owed = almCore.getRewardOwed(users.steward);
        uint256 counted = gauge.earned(address(almCore), almCore.stakedTokenIds());

        // And: Emissions accrued while Active, then the chain Sunset.
        emissions = bound(emissions, 2, Constants.MAX_EMISSIONS);
        blocks = bound(blocks, 1, type(uint32).max);
        accrueForBlocks(pool, gauge, blocks, emissions);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds()) - counted;
        setChainStatus(ILeafVoter.ChainStatus.Sunset);

        // And: A newcomer minting while Sunset, more blocks passing without accrual.
        almCore.mintShares(accountA, bound(shares, 1, supply));
        accrueForBlocks(pool, gauge, blocks, emissions);
        assertEq(gauge.earned(address(almCore), almCore.stakedTokenIds()), counted + earned);

        // When: Both claim while Sunset.
        uint256 paidNewcomer = almCore.claimEmissions(accountA);
        uint256 paidSteward = almCore.claimEmissions(users.steward);

        // Then: The gauge paid, the holder its earlier earnings, the newcomer nothing.
        assertEq(gauge.earned(address(almCore), almCore.stakedTokenIds()), 0);
        assertEq(paidSteward, owed + held.fullMulDiv(earned.fullMulDiv(1e18, supply), 1e18));
        assertEq(paidNewcomer, 0);
    }
}
