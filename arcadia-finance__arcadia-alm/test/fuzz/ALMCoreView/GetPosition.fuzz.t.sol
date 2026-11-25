/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Claimable, Epoch, Record } from "../../../src/core/types/State.sol";
import { Constants } from "../../utils/Constants.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { Plan } from "../../utils/Plan.sol";
import { Position } from "../../../src/periphery/types/Position.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "getPosition" of contract "ALMCoreView".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetPosition_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getPosition_CoreNotValid(PoolState memory poolState, address notCore, address account)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getPosition(notCore, account);
    }

    function testFuzz_Revert_getPosition_CoreNotValid_HalfCreated(PoolState memory poolState, address account) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A pool whose creation stopped with its four vaults deployed and no core.
        address core = BaseVault(halfCreatedVaults()[0]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getPosition(core, account);
    }

    function testFuzz_Revert_getPosition_Reentrancy(
        PoolState memory poolState,
        CoreState memory coreState,
        address account
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, 0, 0, 0);
        setCoreState(coreState);

        // And: The core's lock is held.
        almCore.lock_();

        // When: Reading a position through the lens.
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        coreView.getPosition(address(almCore), account);
    }

    function testFuzz_Success_getPosition_EmptyCoreIsOnlyItsIdAndPool(PoolState memory poolState, address account)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // When: Reading a position on the unseeded core.
        Position memory position = coreView.getPosition(address(almCore), account);

        // Then: Only the id and the pool are set.
        Position memory expected;
        (expected.id, expected.lp) = (uint160(address(almCore)), address(pool));
        assertEq(abi.encode(position), abi.encode(expected));
    }

    function testFuzz_Success_getPosition_NonHolderIsOnlyItsIdAndPool(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address account
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: An account that holds no aLP and no request.
        vm.assume(account != users.steward && account != deadAddress && account != address(almCore));

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), account);

        // Then: Only the id and the pool are set.
        Position memory expected;
        (expected.id, expected.lp) = (uint160(address(almCore)), address(pool));
        assertEq(abi.encode(position), abi.encode(expected));
    }

    function testFuzz_Success_getPosition_FormerHolderIsOnlyItsEmissions(
        PoolState memory poolState,
        CoreState memory coreState,
        uint128 owed
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, 0, 0, 0);
        setCoreState(coreState);

        // And: An account without aLP that is still owed emissions.
        almCore.setPendingReward(accountA, owed);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Only the id, the pool and the emissions it is owed are set.
        Position memory expected;
        (expected.id, expected.lp, expected.emissionsEarned) = (uint160(address(almCore)), address(pool), owed);
        assertEq(abi.encode(position), abi.encode(expected));
    }

    function testFuzz_Success_getPosition_UnstakedRangeIsItsShareOfTheRangeAndTheBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a range without a staked leg.
        givenValidRangeState(range, poolState, false, false);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder of only aLP.
        held = bound(held, 1, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Its liquidity is its share of the range's, rounded down.
        uint256 supply = almCore.totalSupply();
        uint128 liquidity = uint128(FullMath.mulDiv(range.liquidity, held, supply));
        assertEq(position.liquidity, liquidity);
        assertEq(position.staked, 0);

        // And: Its amounts are that liquidity at spot plus its share of the buffer.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        assertEq(position.amount0, amount0 + FullMath.mulDiv(almCore.bufferAmount0(), held, supply));
        assertEq(position.amount1, amount1 + FullMath.mulDiv(almCore.bufferAmount1(), held, supply));
        assertEq(position.staked0, 0);
        assertEq(position.staked1, 0);

        // And: It has not earned fees or emissions.
        assertEq(position.unstakedEarned0, 0);
        assertEq(position.unstakedEarned1, 0);
        assertEq(position.emissionsEarned, 0);

        // And: Its id, pool and ticks are the core's.
        assertEq(position.id, uint160(address(almCore)));
        assertEq(position.lp, address(pool));
        assertEq(position.tickLower, range.tickLower);
        assertEq(position.tickUpper, range.tickUpper);
        assertEq(position.sqrtRatioLower, TickMath.getSqrtPriceAtTick(range.tickLower));
        assertEq(position.sqrtRatioUpper, TickMath.getSqrtPriceAtTick(range.tickUpper));
    }

    function testFuzz_Success_getPosition_StakedRangeSplitsItsShareIntoTheStakedLeg(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY * 4) / 4
            )
        );
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder of only aLP.
        held = bound(held, 1, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Each leg's liquidity is its share of that leg's, rounded down.
        uint256 supply = almCore.totalSupply();
        uint128 liquidity = uint128(FullMath.mulDiv(range.liquidity, held, supply));
        uint128 staked = uint128(FullMath.mulDiv(range.liquidityStaked, held, supply));
        assertEq(position.liquidity, liquidity);
        assertEq(position.staked, staked);

        // And: The unstaked leg and the buffer are its amounts, the staked leg apart.
        (uint256 amount0, uint256 amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        assertEq(position.amount0, amount0 + FullMath.mulDiv(almCore.bufferAmount0(), held, supply));
        assertEq(position.amount1, amount1 + FullMath.mulDiv(almCore.bufferAmount1(), held, supply));
        (amount0, amount1) = amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, staked);
        assertEq(position.staked0, amount0);
        assertEq(position.staked1, amount1);
    }

    function testFuzz_Success_getPosition_MultipleRangesSumAndSpanTheirTicks(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding two ranges.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(second, poolState, false);
        setRangeState(second);

        // And: A holder of only aLP.
        held = bound(held, 1, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: It sums its share of each range's legs and of the buffer.
        Position memory expected;
        uint256 supply = almCore.totalSupply();
        for (uint256 i; i < 2; ++i) {
            Range memory staged = almCore.getRange(i);
            uint128 liquidity = uint128(FullMath.mulDiv(positionLiquidity(staged.unstakedTokenId), held, supply));
            (uint256 amount0, uint256 amount1) =
                amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, liquidity);
            (expected.liquidity, expected.amount0, expected.amount1) =
            (expected.liquidity + liquidity, expected.amount0 + amount0, expected.amount1 + amount1);
            liquidity = uint128(FullMath.mulDiv(staged.stakedLiquidity, held, supply));
            (amount0, amount1) = amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, liquidity);
            (expected.staked, expected.staked0, expected.staked1) =
            (expected.staked + liquidity, expected.staked0 + amount0, expected.staked1 + amount1);
        }
        assertEq(position.liquidity, expected.liquidity);
        assertEq(position.staked, expected.staked);
        assertEq(position.amount0, expected.amount0 + FullMath.mulDiv(almCore.bufferAmount0(), held, supply));
        assertEq(position.amount1, expected.amount1 + FullMath.mulDiv(almCore.bufferAmount1(), held, supply));
        assertEq(position.staked0, expected.staked0);
        assertEq(position.staked1, expected.staked1);

        // And: Its ticks span the lowest lower tick and the highest upper tick.
        expected.tickLower = range.tickLower < second.tickLower ? range.tickLower : second.tickLower;
        expected.tickUpper = range.tickUpper > second.tickUpper ? range.tickUpper : second.tickUpper;
        assertEq(position.tickLower, expected.tickLower);
        assertEq(position.tickUpper, expected.tickUpper);
        assertEq(position.sqrtRatioLower, TickMath.getSqrtPriceAtTick(expected.tickLower));
        assertEq(position.sqrtRatioUpper, TickMath.getSqrtPriceAtTick(expected.tickUpper));
    }

    function testFuzz_Success_getPosition_EarnedFeesAreItsShareOfTheNetFees(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 held,
        uint256 amountIn,
        uint16 feeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A range around the price without a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        }

        // And: A seeded vault holding it, and a holder of only aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        held = bound(held, 1, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: Swap fees the range earned, under a protocol share.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Its earned fees are its share of the range's fees, net of the protocol's.
        (uint256 gross0, uint256 gross1) = positionFees(pool, almCore.getRange(0).unstakedTokenId);
        uint256 supply = almCore.totalSupply();
        assertEq(position.unstakedEarned0, FullMath.mulDiv(gross0 - gross0 * feeBps / 10_000, held, supply));
        assertEq(position.unstakedEarned1, FullMath.mulDiv(gross1 - gross1 * feeBps / 10_000, held, supply));
    }

    function testFuzz_Success_getPosition_PendingDepositsAddTheirAssets(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer, and a holder of none to all the free aLP.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        held = bound(held, 0, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: The holder's pending deposit in each vault.
        givenValidQueueState(queueState, 1, 1);
        recordDepositAt(asyncVault0, accountA, queueState.deposit0);
        recordDepositAt(asyncVault1, accountA, queueState.deposit1);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Each deposit adds its assets once to its token, next to the buffer share.
        uint256 supply = almCore.totalSupply();
        assertEq(position.amount0, FullMath.mulDiv(almCore.bufferAmount0(), held, supply) + queueState.deposit0);
        assertEq(position.amount1, FullMath.mulDiv(almCore.bufferAmount1(), held, supply) + queueState.deposit1);
    }

    function testFuzz_Success_getPosition_PendingRedeemsKeepTheirShares(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer, and a holder of aLP.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, almCore.DEAD_SHARES_() + 2, 0, 0);
        setCoreState(coreState);
        held = bound(held, 2, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: The holder's pending redeem of part of its aLP in each vault.
        queueState.redeem0 = bound(queueState.redeem0, 1, held - 1);
        queueState.redeem1 = bound(queueState.redeem1, 1, held - queueState.redeem0);
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(accountA, accountA, accountA, queueState.redeem0);
        vm.prank(asyncVault1);
        almCore.recordRedeemRequest(accountA, accountA, accountA, queueState.redeem1);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Its amounts are the buffer share of all the aLP it held before.
        uint256 supply = almCore.totalSupply();
        assertEq(position.amount0, FullMath.mulDiv(almCore.bufferAmount0(), held, supply));
        assertEq(position.amount1, FullMath.mulDiv(almCore.bufferAmount1(), held, supply));
    }

    function testFuzz_Success_getPosition_SettledDepositCountsItsShares(
        PoolState memory poolState,
        CoreState memory coreState,
        Record memory record,
        Epoch memory epoch,
        bool isToken0,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer, and a holder of none to all the free aLP.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        held = bound(held, 0, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: The holder's settled deposit, part of its epoch, its aLP in escrow.
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = uint128(bound(epoch.amountIn, record.amountIn, type(uint96).max));
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        almCore.stageSettledDeposit(isToken0 ? asyncVault0 : asyncVault1, accountA, record, epoch);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Its share counts its balance and its pro rata part of the epoch's aLP.
        uint256 shares = held + FullMath.mulDiv(record.amountIn, epoch.amountOut, epoch.amountIn);
        uint256 supply = almCore.totalSupply();
        assertEq(position.amount0, FullMath.mulDiv(almCore.bufferAmount0(), shares, supply));
        assertEq(position.amount1, FullMath.mulDiv(almCore.bufferAmount1(), shares, supply));
    }

    function testFuzz_Success_getPosition_ClaimableDepositCountsItsShares(
        PoolState memory poolState,
        CoreState memory coreState,
        Claimable memory claimable,
        bool isToken0,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer, and a holder of none to all the free aLP.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        held = bound(held, 0, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: The holder's credited deposit pile, its aLP held in escrow.
        claimable.amountOut = uint128(bound(claimable.amountOut, 0, type(uint96).max));
        almCore.stageClaimableDeposit(
            isToken0 ? asyncVault0 : asyncVault1, accountA, claimable.amountIn, claimable.amountOut
        );

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Its share counts its balance and the pile's aLP.
        uint256 shares = held + claimable.amountOut;
        uint256 supply = almCore.totalSupply();
        assertEq(position.amount0, FullMath.mulDiv(almCore.bufferAmount0(), shares, supply));
        assertEq(position.amount1, FullMath.mulDiv(almCore.bufferAmount1(), shares, supply));
    }

    function testFuzz_Success_getPosition_SettledRedeemAddsItsAssets(
        PoolState memory poolState,
        CoreState memory coreState,
        Record memory record,
        Epoch memory epoch,
        bool isToken0,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer, and a holder of none to all the free aLP.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        held = bound(held, 0, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: The holder's settled redeem record, part of its epoch, its aLP burned.
        record.epoch = uint32(bound(record.epoch, 0, type(uint32).max - 1));
        record.amountIn = uint128(bound(record.amountIn, 1, type(uint96).max));
        epoch.amountIn = uint128(bound(epoch.amountIn, record.amountIn, type(uint96).max));
        epoch.amountOut = uint128(bound(epoch.amountOut, 0, type(uint96).max));
        almCore.stageSettledRedeem(isToken0 ? asyncVault0 : asyncVault1, accountA, record, epoch);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Its pro rata part of the epoch's assets adds once to the vault's token.
        uint256 assets = FullMath.mulDiv(record.amountIn, epoch.amountOut, epoch.amountIn);
        uint256 supply = almCore.totalSupply();
        assertEq(position.amount0, FullMath.mulDiv(almCore.bufferAmount0(), held, supply) + (isToken0 ? assets : 0));
        assertEq(position.amount1, FullMath.mulDiv(almCore.bufferAmount1(), held, supply) + (isToken0 ? 0 : assets));
    }

    function testFuzz_Success_getPosition_ClaimableRedeemAddsItsAssets(
        PoolState memory poolState,
        CoreState memory coreState,
        Claimable memory claimable,
        bool isToken0,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer, and a holder of none to all the free aLP.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        held = bound(held, 0, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: The holder's credited redeem pile, its assets held in escrow.
        claimable.amountOut = uint128(bound(claimable.amountOut, 0, Constants.MAX_FUZZED_AMOUNT));
        almCore.stageClaimableRedeem(
            isToken0 ? asyncVault0 : asyncVault1, accountA, claimable.amountIn, claimable.amountOut
        );

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: The pile's assets add once to the vault's token.
        uint256 supply = almCore.totalSupply();
        assertEq(
            position.amount0,
            FullMath.mulDiv(almCore.bufferAmount0(), held, supply) + (isToken0 ? claimable.amountOut : 0)
        );
        assertEq(
            position.amount1,
            FullMath.mulDiv(almCore.bufferAmount1(), held, supply) + (isToken0 ? 0 : claimable.amountOut)
        );
    }

    function testFuzz_Success_getPosition_PendingRedeemAndClaimableDepositInOneVaultAdd(
        PoolState memory poolState,
        CoreState memory coreState,
        uint256 redeemed,
        uint128 claimableOut,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer, and a holder of aLP.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, almCore.DEAD_SHARES_() + 2, 0, 0);
        setCoreState(coreState);
        held = bound(held, 2, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: A pending redeem of part of its aLP and a deposit pile, in one vault.
        redeemed = bound(redeemed, 1, held - 1);
        vm.prank(asyncVault0);
        almCore.recordRedeemRequest(accountA, accountA, accountA, redeemed);
        claimableOut = uint128(bound(claimableOut, 1, type(uint96).max));
        almCore.stageClaimableDeposit(asyncVault0, accountA, 0, claimableOut);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Its share counts the aLP it held and the pile's aLP.
        uint256 shares = held + claimableOut;
        uint256 supply = almCore.totalSupply();
        assertEq(position.amount0, FullMath.mulDiv(almCore.bufferAmount0(), shares, supply));
        assertEq(position.amount1, FullMath.mulDiv(almCore.bufferAmount1(), shares, supply));
    }

    function testFuzz_Success_getPosition_PendingDepositAndClaimableRedeemInOneVaultAdd(
        PoolState memory poolState,
        CoreState memory coreState,
        QueueState memory queueState,
        uint128 claimableOut,
        uint256 held
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a buffer, and a holder of none to all the free aLP.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        held = bound(held, 0, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        almCore.transfer(accountA, held);

        // And: In the token0 vault, its pending deposit and a credited redeem pile.
        givenValidQueueState(queueState, 1, 1);
        recordDepositAt(asyncVault0, accountA, queueState.deposit0);
        claimableOut = uint128(bound(claimableOut, 1, type(uint96).max));
        almCore.stageClaimableRedeem(asyncVault0, accountA, 0, claimableOut);

        // When: Reading its position.
        Position memory position = coreView.getPosition(address(almCore), accountA);

        // Then: Both add their assets to token0, next to the buffer share.
        uint256 supply = almCore.totalSupply();
        assertEq(
            position.amount0,
            FullMath.mulDiv(almCore.bufferAmount0(), held, supply) + queueState.deposit0 + claimableOut
        );
    }

    function testFuzz_Success_getPosition_SumOverEveryHolderStaysWithinTheCore(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        deployCoreView();

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests in both vaults, the token0 deposits settled.
        givenValidQueueState(queueState, 0, 0);
        setQueueState(queueState);
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());

        // When: Summing the position of every holder of aLP or a request.
        address[] memory holders = new address[](6);
        (holders[0], holders[1], holders[2]) = (deadAddress, users.steward, controller);
        (holders[3], holders[4], holders[5]) = (secondController, accountB, accountC);
        Position memory sum;
        for (uint256 i; i < holders.length; ++i) {
            Position memory position = coreView.getPosition(address(almCore), holders[i]);
            (sum.liquidity, sum.staked) = (sum.liquidity + position.liquidity, sum.staked + position.staked);
            (sum.amount0, sum.amount1) = (sum.amount0 + position.amount0, sum.amount1 + position.amount1);
            (sum.staked0, sum.staked1) = (sum.staked0 + position.staked0, sum.staked1 + position.staked1);
        }

        // Then: The liquidity stays within each leg of the range.
        Range memory staged = almCore.getRange(range.index);
        assertLe(sum.liquidity, positionLiquidity(staged.unstakedTokenId));
        assertLe(sum.staked, staged.stakedLiquidity);

        // And: The amounts stay within the legs at spot, the buffer and the escrow.
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(
            sqrtPriceX96(pool), range.tickLower, range.tickUpper, positionLiquidity(staged.unstakedTokenId)
        );
        assertLe(sum.amount0, amount0 + almCore.bufferAmount0() + almCore.getEscrowed0());
        assertLe(sum.amount1, amount1 + almCore.bufferAmount1() + almCore.getEscrowed1());
        (amount0, amount1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, staged.stakedLiquidity);
        assertLe(sum.staked0, amount0);
        assertLe(sum.staked1, amount1);
    }
}
