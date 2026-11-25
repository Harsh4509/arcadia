/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLGauge } from "../../../src/interfaces/IMetadexCLGauge.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";

/**
 * @notice Fuzz tests for the function "transfer" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast, erc20-unchecked-transfer)
contract Transfer_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_transfer_InvalidRecipient(PoolState memory poolState, uint96 sharesA, uint96 amount)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A holder moving at most the shares it holds.
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 0, sharesA));

        // When: The holder transfers to the zero address.
        // Then: It reverts.
        vm.prank(accountA);
        vm.expectRevert(BaseCore.InvalidRecipient.selector);
        almCore.transfer(address(0), amount);
    }

    function testFuzz_Revert_transfer_InsufficientBalance(PoolState memory poolState, uint96 sharesA, uint256 amount)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A holder moving more shares than it holds.
        almCore.mintShares(accountA, sharesA);
        amount = bound(amount, uint256(sharesA) + 1, type(uint256).max);

        // When: The holder calls transfer().
        // Then: It reverts.
        vm.prank(accountA);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        almCore.transfer(accountB, amount);
    }

    function testFuzz_Revert_transfer_PerUserCapExceeded(
        PoolState memory poolState,
        uint96 sharesA,
        uint96 amount,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A holder, and a per user cap one share short of what it sends.
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 1, sharesA));
        vm.prank(factory);
        almCore.setPerUserCap(amount - 1);
        vm.assume(receiver != accountA && receiver != address(almCore) && receiver != address(0));

        // When: The holder transfers to any other account.
        // Then: It reverts on the receiver's cap balance.
        vm.prank(accountA);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.transfer(receiver, amount);
    }

    function testFuzz_Success_transfer_CreditsBothSidesBeforeTheBalanceMoves(
        PoolState memory poolState,
        uint96 sharesA,
        uint96 sharesB,
        uint96 amount,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: Two holders next to a supply the reward per share of the accrual fits.
        uint256 accrued = bound(earned, 1, Constants.MAX_FUZZED_AMOUNT);
        uint256 net = accrued - accrued * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        sharesB = uint96(bound(sharesB, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(net.fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, sharesA);
        almCore.mintShares(accountB, sharesB);

        // And: An accrual neither of them has been credited with yet.
        mockEarned(gauge, address(almCore), accrued);
        amount = uint96(bound(amount, 0, sharesA));
        uint256 rewardPerShare = almCore.rewardPerShare_() + net.fullMulDiv(1e18, almCore.totalSupply());
        uint256 owedA = almCore.getPendingReward(accountA)
            + uint256(sharesA).fullMulDiv(rewardPerShare - almCore.getRewardSnapshot(accountA), 1e18);
        uint256 owedB = almCore.getPendingReward(accountB)
            + uint256(sharesB).fullMulDiv(rewardPerShare - almCore.getRewardSnapshot(accountB), 1e18);
        uint256 highWater = almCore.getRewardHighWater();

        // When: The first holder transfers to the second.
        vm.prank(accountA);
        almCore.transfer(accountB, amount);

        // Then: Both were credited against the balances they held before the move.
        assertEq(almCore.getPendingReward(accountA), owedA);
        assertEq(almCore.getPendingReward(accountB), owedB);
        assertEq(almCore.balanceOf(accountA), sharesA - amount);
        assertEq(almCore.balanceOf(accountB), uint256(sharesB) + amount);

        // And: Both snapshots are at the raised accumulator, the high water took it in.
        assertEq(almCore.getRewardSnapshot(accountA), rewardPerShare);
        assertEq(almCore.getRewardSnapshot(accountB), rewardPerShare);
        assertEq(almCore.getRewardHighWater(), highWater + net);
    }

    function testFuzz_Success_transfer_NoGaugeWrite(
        PoolState memory poolState,
        uint96 sharesA,
        uint96 amount,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: A holder next to a supply the reward per share fits, and an accrual.
        uint256 accrued = bound(earned, 1, Constants.MAX_FUZZED_AMOUNT);
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(accrued.fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, sharesA);
        mockEarned(gauge, address(almCore), accrued);

        // And: Every gauge write reverts.
        vm.mockCallRevert(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.claimEmissions.selector), "");
        vm.mockCallRevert(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.deposit.selector), "");
        vm.mockCallRevert(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.withdraw.selector), "");
        amount = uint96(bound(amount, 0, sharesA));

        // When: Transferring.
        vm.prank(accountA);
        almCore.transfer(accountB, amount);

        // Then: The transfer went through, so no gauge write was made.
        assertEq(almCore.balanceOf(accountB), amount);
    }

    function testFuzz_Success_transfer_SecondHolderUnaffected(
        PoolState memory poolState,
        uint96 sharesA,
        uint96 sharesB,
        uint96 sharesC,
        uint96 amount,
        uint96 earned
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: Three holders and an accrual whose reward per share fits.
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        sharesB = uint96(bound(sharesB, 1, type(uint96).max));
        sharesC = uint96(bound(sharesC, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        almCore.mintShares(accountB, sharesB);
        almCore.mintShares(accountC, sharesC);
        uint256 supply = almCore.totalSupply();
        uint256 accrued = bound(
            earned, 1, FixedPointMathLib.min(Constants.MAX_FUZZED_AMOUNT, supply.fullMulDiv(type(uint128).max, 1e18))
        );
        mockEarned(gauge, address(almCore), accrued);
        uint256 net = accrued - accrued * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        uint256 owedC = almCore.getPendingReward(accountC)
            + uint256(sharesC)
                .fullMulDiv(
                    almCore.rewardPerShare_() + net.fullMulDiv(1e18, supply) - almCore.getRewardSnapshot(accountC), 1e18
                );
        amount = uint96(bound(amount, 0, sharesA));

        // When: The first holder transfers to the second.
        vm.prank(accountA);
        almCore.transfer(accountB, amount);

        // Then: The third holder is owed the same amount as before.
        assertEq(almCore.getRewardOwed(accountC), owedC);
    }

    function testFuzz_Success_transfer_CheckpointsOnce(
        PoolState memory poolState,
        uint96 sharesA,
        uint96 amount,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: Two holders next to a supply the reward per share fits, and an accrual.
        uint256 accrued = bound(earned, 1, Constants.MAX_FUZZED_AMOUNT);
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(accrued.fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, sharesA);
        almCore.mintShares(accountB, 1);
        mockEarned(gauge, address(almCore), accrued);
        amount = uint96(bound(amount, 0, sharesA));

        // When: The first holder transfers to the second.
        vm.expectCall(
            address(gauge), abi.encodeWithSelector(IMetadexCLGauge.deferredEmissions.selector, address(almCore)), 1
        );
        vm.prank(accountA);
        almCore.transfer(accountB, amount);

        // Then: The gauge was read once, so both sides shared a single checkpoint.
        assertEq(almCore.balanceOf(accountB), uint256(1) + amount);
    }

    function testFuzz_Success_transfer_NoInfinitePermit2Allowance(PoolState memory poolState, uint96 sharesA) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: A holder that approved nobody.
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);

        // When: Reading the allowance of the canonical Permit2.
        uint256 allowance = almCore.allowance(accountA, Constants.PERMIT2);

        // Then: Permit2 was granted nothing.
        assertEq(allowance, 0);
    }

    function testFuzz_Success_transfer_ToSelf(
        PoolState memory poolState,
        uint96 sharesA,
        uint96 amount,
        uint96 earned,
        uint256 seedShares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        // And: A holder next to a supply the reward per share fits, and an accrual.
        uint256 accrued = bound(earned, 1, Constants.MAX_FUZZED_AMOUNT);
        uint256 net = accrued - accrued * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        seedShares = bound(
            seedShares,
            FixedPointMathLib.max(net.fullMulDivUp(1e18, type(uint128).max), Constants.DEAD_SHARES),
            type(uint96).max
        );
        almCore.mintShares(address(1), seedShares);
        almCore.mintShares(accountA, sharesA);
        mockEarned(gauge, address(almCore), accrued);
        uint256 owedA = almCore.getPendingReward(accountA)
            + uint256(sharesA)
                .fullMulDiv(
                    almCore.rewardPerShare_() + net.fullMulDiv(1e18, almCore.totalSupply())
                        - almCore.getRewardSnapshot(accountA),
                    1e18
                );
        amount = uint96(bound(amount, 0, sharesA));

        // When: The holder transfers to itself.
        vm.prank(accountA);
        almCore.transfer(accountA, amount);

        // Then: It is credited once and its balance is unchanged.
        assertEq(almCore.getPendingReward(accountA), owedA);
        assertEq(almCore.balanceOf(accountA), sharesA);
    }

    function testFuzz_Success_transfer_ToSelfAboveTheCap(PoolState memory poolState, uint96 sharesA, uint96 amount)
        public
    {
        // Given: A pool at a fuzzed price, a holder and a per user cap of nothing.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 0, sharesA));

        // When: The holder transfers to itself.
        vm.prank(accountA);
        almCore.transfer(accountA, amount);

        // Then: It is not checked.
        assertEq(almCore.balanceOf(accountA), sharesA);
    }

    function testFuzz_Success_transfer_ToTheCoreAboveTheCap(PoolState memory poolState, uint96 sharesA, uint96 amount)
        public
    {
        // Given: A pool at a fuzzed price, a holder and a per user cap of nothing.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        amount = uint96(bound(amount, 1, sharesA));

        // When: The holder transfers to the core.
        vm.prank(accountA);
        almCore.transfer(address(almCore), amount);

        // Then: The core skips the check.
        assertEq(almCore.balanceOf(address(almCore)), amount);
    }

    function testFuzz_Success_transfer_InWindowCreditsBothSidesAtThePreCredit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 heldFor,
        uint256 emissions,
        uint96 sharesA,
        uint96 sharesB,
        uint96 amount
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked sides' emissions for a fuzzed window.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);

        // And: A seeded vault whose staked range opens its window now, and two holders.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        sharesB = uint96(bound(sharesB, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);
        almCore.mintShares(accountB, sharesB);

        // And: Emissions the window hides, up to a fuzzed block inside it.
        accrueForBlocks(pool, gauge, bound(heldFor, 1, window - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        uint256 perShare = FixedPointMathLib.fullMulDiv(hidden, 1e18, almCore.totalSupply());

        // When: The first holder transfers to the second inside the window.
        vm.prank(accountA);
        almCore.transfer(accountB, bound(amount, 0, sharesA));

        // Then: Both are credited the hidden accrual at their balances before the move.
        assertEq(almCore.getPendingReward(accountA), FixedPointMathLib.fullMulDiv(sharesA, perShare, 1e18));
        assertEq(almCore.getPendingReward(accountB), FixedPointMathLib.fullMulDiv(sharesB, perShare, 1e18));

        // And: The hidden accrual is recorded as pre-credited.
        assertEq(almCore.getPreCredited(), hidden);
    }

    function testFuzz_Success_transfer_BuyerInWindowEarnsOnlyItsBlocks(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 boughtAfter,
        uint256 emissions,
        uint96 sharesA,
        uint96 amount
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked sides' emissions for a fuzzed window.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);

        // And: A seeded vault whose staked range opens its window now, and a holder.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);

        // And: Emissions the window hides, up to a fuzzed block inside it.
        emissions = bound(emissions, 1, Constants.MAX_EMISSIONS);
        boughtAfter = bound(boughtAfter, 1, window - 1);
        accrueForBlocks(pool, gauge, boughtAfter, emissions);
        uint256 bps = almCore.protocolEmissionFeeBps_();
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * bps / almCore.BPS_DENOMINATOR_();

        // When: A buyer receives shares from the holder inside the window.
        amount = uint96(bound(amount, 1, sharesA));
        vm.prank(accountA);
        almCore.transfer(accountB, amount);

        // And: The window closes after more emissions.
        accrueForBlocks(pool, gauge, window - boughtAfter, emissions);

        // Then: The buyer is credited only what accrued while it held.
        uint256 lifetime = gauge.earned(address(almCore), almCore.stakedTokenIds());
        lifetime -= lifetime * bps / almCore.BPS_DENOMINATOR_();
        assertEq(
            almCore.getRewardOwed(accountB),
            FixedPointMathLib.fullMulDiv(
                amount, FixedPointMathLib.fullMulDiv(lifetime - hidden, 1e18, almCore.totalSupply()), 1e18
            )
        );
    }

    function testFuzz_Success_transfer_PreCreditsOnAnyChainStatus(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 heldFor,
        uint256 emissions,
        uint96 sharesA,
        uint96 amount,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked sides' emissions for a fuzzed window.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);

        // And: A seeded vault whose staked range opens its window now, and a holder.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        sharesA = uint96(bound(sharesA, 1, type(uint96).max));
        almCore.mintShares(accountA, sharesA);

        // And: Emissions the window hides, on any chain status.
        accrueForBlocks(pool, gauge, bound(heldFor, 1, window - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        setAnyStatus(status);
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 delta = FixedPointMathLib.fullMulDiv(hidden, 1e18, almCore.totalSupply());

        // When: The holder transfers to another account inside the window.
        vm.prank(accountA);
        almCore.transfer(accountB, bound(amount, 0, sharesA));

        // Then: The hidden accrual is pre-credited on any chain status.
        assertEq(almCore.getPreCredited(), hidden);
        assertEq(almCore.rewardPerShare_(), rewardPerShare + delta);

        // And: The holder is credited at the balance it held before the move.
        assertEq(almCore.getPendingReward(accountA), FixedPointMathLib.fullMulDiv(sharesA, delta, 1e18));
    }
}
