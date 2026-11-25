/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLGauge } from "../../../../src/interfaces/IMetadexCLGauge.sol";
import { RewardAccount } from "../../../../src/core/types/State.sol";
import { RewardsLib } from "../../../../src/core/libraries/state/RewardsLib.sol";
import { RewardsLib_Fuzz_Test } from "./_RewardsLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "payReward" of library "RewardsLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract PayReward_RewardsLib_Fuzz_Test is RewardsLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_payReward_PaysTheMeasuredBalance(
        PoolState memory poolState,
        uint128 claimed,
        uint128 measured,
        uint128 protocolFees,
        uint128 credited,
        uint256 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with no new reward since its last checkpoint.
        deployRewardsLib();
        measured = uint128(bound(measured, 0, type(uint128).max - 1));
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), measured);

        // And: An account credited more than the measured balance, whatever the fees.
        credited = uint128(bound(credited, uint256(measured) + 1, type(uint128).max));
        rewardsLib.setRewards(0, claimed, claimed, measured, protocolFees);
        rewardsLib.setRewardAccount(accountA, RewardAccount({ rewardPerSharePaid: 0, rewardOwed: credited }));

        // When: Claiming for the account.
        uint256 amount = rewardsLib.payReward(supply, accountA, 0);

        // Then: The account is paid the measured balance, and the rest stays owed.
        assertEq(amount, measured);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), measured);
        assertEq(rewardsLib.getRewardAccount(accountA).rewardOwed, credited - measured);

        // And: The measured balance is used up.
        (,,, uint128 measuredAfter,) = rewardsLib.getRewards();
        assertEq(measuredAfter, 0);
    }

    function testFuzz_Success_payReward_PaysNothingBeforeTheHiddenPartArrives(
        PoolState memory poolState,
        uint16 feeBps,
        uint64 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling, one holder and a full penalty.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        shares = uint64(bound(shares, almCore.DEAD_SHARES_(), type(uint64).max));
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued inside the window, pre-credited.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        almCore.checkpoint_();
        almCore.updateRewards(accountA);
        uint256 owed = almCore.getPendingReward(accountA);

        // When: Claiming for the holder inside the window.
        uint256 amount = almCore.claimEmissions(accountA);

        // Then: Nothing is paid, the hidden part is not received, the credit stays owed.
        assertEq(amount, 0);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), 0);
        assertEq(almCore.getPendingReward(accountA), owed);
    }

    function testFuzz_Success_payReward_PaysTheCreditedReward(
        PoolState memory poolState,
        uint128 claimed,
        uint128 measured,
        uint128 protocolFees,
        uint128 credited,
        uint256 supply
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with no new reward since its last checkpoint.
        deployRewardsLib();
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), measured);

        // And: An account credited at most the measured balance, whatever the fees.
        credited = uint128(bound(credited, 0, measured));
        rewardsLib.setRewards(0, claimed, claimed, measured, protocolFees);
        rewardsLib.setRewardAccount(accountA, RewardAccount({ rewardPerSharePaid: 0, rewardOwed: credited }));

        // When: Claiming for the account.
        uint256 amount = rewardsLib.payReward(supply, accountA, 0);

        // Then: The account is paid its credit, which is cleared.
        assertEq(amount, credited);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), credited);
        assertEq(rewardsLib.getRewardAccount(accountA).rewardOwed, 0);

        // And: The measured balance fell by it.
        (,,, uint128 measuredAfter,) = rewardsLib.getRewards();
        assertEq(measuredAfter, measured - credited);
    }

    function testFuzz_Success_payReward_AccruesBeforePaying(
        PoolState memory poolState,
        uint128 claimed,
        uint128 accumulator,
        uint96 balance
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core with no new reward since its checkpoint, balance covers any credit.
        deployRewardsLib();
        deal(almCore.REWARD_TOKEN_(), address(rewardsLib), type(uint128).max);

        // And: An accumulator ahead of an account's snapshot, within a uint128 credit.
        uint256 room = uint256(type(uint128).max) * 1e18 / (uint256(balance) + 1);
        accumulator = uint128(bound(accumulator, 1, room < type(uint128).max ? room : type(uint128).max));
        rewardsLib.setRewards(accumulator, claimed, claimed, type(uint128).max, 0);

        // When: Claiming for an account holding aLP.
        uint256 amount = rewardsLib.payReward(uint256(balance) + 1, accountA, balance);

        // Then: The account is paid what its balance earned since its snapshot.
        assertEq(amount, uint256(balance) * accumulator / 1e18);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), amount);
        assertEq(rewardsLib.getRewardAccount(accountA).rewardPerSharePaid, accumulator);
    }

    function testFuzz_Success_payReward_DeliversEmissions(
        PoolState memory poolState,
        uint128 liquidity,
        uint256 emissions,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A staked range whose penalty window has closed, with emissions accrued.
        liquidity = uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())));
        stakeIntoRange(liquidity);
        emissions = bound(emissions, 1, MAX_BASE_RATE);
        addEmissionsToGaugeCL(pool, gauge, emissions);
        vm.roll(vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));

        // And: The earned amount before the claim, and a chain the gauge still mints on.
        uint256 earned = gauge.earned(address(almCore));
        setMintableStatus(status);

        // When: Claiming for an account.
        almCore.claimEmissions(accountA);

        // Then: The earned amount is delivered to the core.
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), earned);
    }

    function testFuzz_Success_payReward_SkipsPositionInsidePenaltyWindow(
        PoolState memory poolState,
        uint128 liquidity,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A staked range still inside its penalty window, with emissions accrued.
        liquidity = uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())));
        stakeIntoRange(liquidity);
        emissions = bound(emissions, 1, MAX_BASE_RATE);
        addEmissionsToGaugeCL(pool, gauge, emissions);

        // When: Claiming for an account.
        almCore.claimEmissions(accountA);

        // Then: The range was skipped, so nothing was claimed.
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), 0);
    }

    function testFuzz_Success_payReward_NoGaugeClaimWithoutAnIdOrADeferral(PoolState memory poolState) public {
        // Given: A pool at a fuzzed price, no staked range, nothing deferred.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: Claiming for an account.
        // Then: The gauge is not asked to claim.
        vm.expectCall(
            address(gauge),
            abi.encodeCall(IMetadexCLGauge.claimEmissions, (address(almCore), address(almCore), new uint256[](0))),
            0
        );
        almCore.claimEmissions(accountA);
    }

    function testFuzz_Success_payReward_ClaimsADeferral(PoolState memory poolState, uint256 deferred) public {
        // Given: A pool at a fuzzed price, no staked range, emissions deferred at gauge.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.mockCall(
            address(gauge),
            abi.encodeWithSelector(IMetadexCLGauge.deferredEmissions.selector, address(almCore)),
            abi.encode(bound(deferred, 1, type(uint128).max))
        );

        // And: A gauge that accepts the claim.
        vm.mockCall(
            address(gauge),
            abi.encodeCall(IMetadexCLGauge.claimEmissions, (address(almCore), address(almCore), new uint256[](0))),
            ""
        );

        // When: Claiming for an account.
        // Then: The gauge is asked to claim the deferral with no token id.
        vm.expectCall(
            address(gauge),
            abi.encodeCall(IMetadexCLGauge.claimEmissions, (address(almCore), address(almCore), new uint256[](0))),
            1
        );
        almCore.claimEmissions(accountA);
    }

    function testFuzz_Success_payReward_SkipsTheGaugeWhileTheChainDoesNotMint(
        PoolState memory poolState,
        uint256 deferred,
        uint256 pick
    ) public {
        // Given: A pool at a fuzzed price, no staked range, emissions deferred at gauge.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.mockCall(
            address(gauge),
            abi.encodeWithSelector(IMetadexCLGauge.deferredEmissions.selector, address(almCore)),
            abi.encode(bound(deferred, 1, type(uint128).max))
        );

        // And: A chain that is paused or suspended.
        setNotMintableStatus(pick);

        // When: Claiming for an account.
        // Then: The gauge is not asked to claim.
        vm.expectCall(
            address(gauge),
            abi.encodeCall(IMetadexCLGauge.claimEmissions, (address(almCore), address(almCore), new uint256[](0))),
            0
        );
        almCore.claimEmissions(accountA);
    }

    function testFuzz_Success_payReward_ClaimsTheStakedIdsOutsideTheirWindow(
        PoolState memory poolState,
        uint128 liquidity
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A staked range of the vault whose penalty window has closed.
        liquidity = uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing())));
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(liquidity);
        vm.roll(vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));

        // When: Claiming for an account.
        // Then: The gauge is asked to claim the staked id.
        vm.expectCall(
            address(gauge),
            abi.encodeCall(IMetadexCLGauge.claimEmissions, (address(almCore), address(almCore), tokenIds)),
            1
        );
        almCore.claimEmissions(accountA);
    }

    function testFuzz_Success_payReward_PaysThePreCreditOnceTheWindowCloses(
        PoolState memory poolState,
        uint16 feeBps,
        uint64 shares,
        uint128 liquidity,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling, one holder and a full penalty.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        shares = uint64(bound(shares, almCore.DEAD_SHARES_(), type(uint64).max));
        almCore.mintShares(accountA, shares);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A staked range inside its penalty window.
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = stakeIntoRange(uint128(bound(liquidity, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()))));
        almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

        // And: Emissions accrued inside the window, pre-credited.
        accrueForBlocks(pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), tokenIds);
        almCore.checkpoint_();

        // When: The penalty window closes, and the holder claims.
        closePenaltyWindow(gauge);
        uint256 amount = almCore.claimEmissions(accountA);

        // Then: The claim pays the holder's part of the pre-credit.
        uint256 rewardPerShare = FixedPointMathLib.fullMulDiv(hidden - hidden * feeBps / 10_000, 1e18, shares);
        assertEq(amount, FixedPointMathLib.fullMulDiv(shares, rewardPerShare, 1e18));
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), amount);
    }

    function testFuzz_Success_payReward_PreCreditPaidFromOtherRangesEmissions(
        PoolState memory poolState,
        uint16 feeBps,
        uint96 sharesA,
        uint96 sharesB,
        uint128 liquidityInside,
        uint128 liquidityClosed,
        uint256 minStakeBlocks,
        uint256 blocks,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An emission fee within the ceiling, a full penalty over a fuzzed window.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);
        minStakeBlocks = bound(minStakeBlocks, 1, type(uint32).max);
        setPenaltyConfig(minStakeBlocks, MAX_PIPS);

        // And: A holder and a second holder with at least twice its aLP.
        sharesA = uint96(
            bound(
                sharesA,
                FixedPointMathLib.max(
                    FixedPointMathLib.fullMulDivUp(Constants.MAX_EMISSIONS, 1e18, type(uint128).max),
                    Constants.DEAD_SHARES
                ),
                type(uint96).max / 2
            )
        );
        sharesB = uint96(bound(sharesB, 2 * uint256(sharesA), type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        almCore.mintShares(accountB, sharesB);

        uint256 hidden;
        uint256 earned;
        {
            // And: A staked range whose penalty window has closed.
            uint256[] memory closedToken = new uint256[](1);
            liquidityClosed =
                uint128(bound(liquidityClosed, 1, tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) / 2));
            closedToken[0] = stakeIntoRange(liquidityClosed);
            closePenaltyWindow(gauge);

            // And: A second staked range, no larger, inside its penalty window.
            uint256[] memory insideToken = new uint256[](1);
            insideToken[0] = stakeIntoRange(uint128(bound(liquidityInside, 1, liquidityClosed)));
            almCore.setWindowEnd(uint48(vm.getBlockNumber() + minStakeBlocks));

            // And: Emissions accrued on both ranges.
            accrueForBlocks(
                pool, gauge, bound(blocks, 0, minStakeBlocks - 1), bound(emissions, 1, Constants.MAX_EMISSIONS)
            );
            hidden = hiddenEmissions(gauge, address(almCore), insideToken);
            earned = gauge.earned(address(almCore), closedToken);
        }

        // When: Claiming for the holder.
        uint256 amount = almCore.claimEmissions(accountA);

        // Then: It is paid its share of the visible emissions and the pre-credit.
        uint256 rewardPerShare = FixedPointMathLib.fullMulDiv(
            earned - earned * feeBps / 10_000 + hidden - hidden * feeBps / 10_000, 1e18, uint256(sharesA) + sharesB
        );
        assertEq(amount, FixedPointMathLib.fullMulDiv(sharesA, rewardPerShare, 1e18));
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(accountA), amount);
    }
}
