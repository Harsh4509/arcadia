/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { AsyncVaultGuard } from "../../../src/core/abstracts/mixins/AsyncVaultGuard.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Plan } from "../../utils/Plan.sol";
import { PoolTokensLib } from "../../../src/core/libraries/state/PoolTokensLib.sol";
import { QueueLib } from "../../../src/core/libraries/state/QueueLib.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "recordDepositRequest" of contract "ALMCore".
 */
contract RecordDepositRequest_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_recordDepositRequest_InvalidController(
        PoolState memory poolState,
        address caller,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: Any caller records a deposit with the core as its controller.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMCore.InvalidController.selector);
        almCore.recordDepositRequest(address(almCore), assets);
    }

    function testFuzz_Revert_recordDepositRequest_OnlyAsyncVault(
        PoolState memory poolState,
        address caller,
        address controller,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0) && controller != address(almCore));

        // And: A caller that is neither asynchronous vault.
        vm.assume(caller != asyncVault0 && caller != asyncVault1);

        // When: Calling recordDepositRequest().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(AsyncVaultGuard.OnlyAsyncVault.selector);
        almCore.recordDepositRequest(controller, assets);
    }

    function testFuzz_Revert_recordDepositRequest_OnlyAsyncVault_ZeroCaller(
        PoolState memory poolState,
        address controller,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(controller != address(almCore));

        // And: The zero address, which every unset vault lookup also answers.

        // When: It forwards a request.
        // Then: It reverts, rather than reading as the token0 vault.
        vm.prank(address(0));
        vm.expectRevert(AsyncVaultGuard.OnlyAsyncVault.selector);
        almCore.recordDepositRequest(controller, assets);
    }

    function testFuzz_Revert_recordDepositRequest_LastExchangeRateNotSet(
        PoolState memory poolState,
        address controller,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price, no exchange rate stored.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        almCore.setLastExchangeRate(0, 0);
        vm.assume(controller != address(almCore));

        // When: The token0 vault records a deposit.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(ShareLib.LastExchangeRateNotSet.selector);
        almCore.recordDepositRequest(controller, assets);
    }

    function testFuzz_Revert_recordDepositRequest_ZeroAddress(PoolState memory poolState, uint256 assets) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault forwarding a request held for nobody.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: It records it.
        // Then: It reverts, rather than recording a pile no one can claim.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.ZeroAddress.selector);
        almCore.recordDepositRequest(address(0), assets);
    }

    function testFuzz_Revert_recordDepositRequest_ZeroAmount(PoolState memory poolState, address controller) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0) && controller != address(almCore));

        // And: A vault forwarding a request for nothing.

        // When: It records it.
        // Then: It reverts, rather than recording an id no one can cancel.
        vm.prank(asyncVault0);
        vm.expectRevert(QueueLib.ZeroAmount.selector);
        almCore.recordDepositRequest(controller, 0);
    }

    function testFuzz_Revert_recordDepositRequest_AccountingMismatch(
        PoolState memory poolState,
        address controller,
        uint256 assets,
        uint256 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        vm.assume(controller != address(0) && controller != address(almCore));

        // And: No per user cap in the way.
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        // And: A vault forwarding a request for more assets than reached the core.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(address(almCore), bound(received, 0, assets - 1));

        // When: It records it.
        // Then: It reverts, the balance not covering the escrow.
        vm.prank(asyncVault0);
        vm.expectRevert(PoolTokensLib.AccountingMismatch.selector);
        almCore.recordDepositRequest(controller, assets);
    }

    function testFuzz_Revert_recordDepositRequest_PerUserCapExceeded(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState
    ) public {
        // Given: A vault whose rate a plan stored, a deposit and its pending aLP.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        runPlan(Plan.init());
        givenValidQueueState(queueState, 1, 0);
        uint256 assets = queueState.deposit0;
        (uint256 supplyPerValueX128, uint160 lastSqrtPrice) = almCore.lastExchangeRate_();
        uint256 upper = FixedPointMathLib.max(sqrtPriceX96(pool), lastSqrtPrice);
        uint256 pending =
            assets.fullMulDivUp(upper, 1 << 96).fullMulDivUp(upper, 1 << 96).fullMulDivUp(supplyPerValueX128, 1 << 128);

        // And: A per user cap one share short of the pending aLP.
        vm.prank(factory);
        almCore.setPerUserCap(pending - 1);
        token0.mint(address(almCore), assets);

        // When: The token0 vault records the deposit.
        // Then: It reverts.
        vm.prank(asyncVault0);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.recordDepositRequest(controller, assets);
    }

    function testFuzz_Revert_recordDepositRequest_PendingSharesPastUint96(
        PoolState memory poolState,
        uint256 first,
        uint256 assets
    ) public {
        // Given: A pool with depth, and an exchange rate reserving one aLP per token1.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setLastExchangeRate(1 << 128, sqrtPriceX96(pool));

        // And: A pending deposit, and a second taking the pending aLP past a uint96.
        first = bound(first, 1, type(uint96).max);
        recordDepositAt(asyncVault1, controller, first);
        assets = bound(assets, uint256(type(uint96).max) - first + 1, Constants.MAX_FUZZED_AMOUNT - first);
        token1.mint(address(almCore), assets);

        // When: The token1 vault records the second deposit.
        // Then: It reverts.
        vm.prank(asyncVault1);
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.recordDepositRequest(controller, assets);
    }

    function testFuzz_Revert_recordDepositRequest_AssetsPastInt128(
        PoolState memory poolState,
        uint256 supplyPerValueX128,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A deposit past an int128, its pending aLP within a uint96.
        assets = bound(assets, Constants.MAX_FUZZED_AMOUNT + 1, type(uint128).max);
        supplyPerValueX128 = bound(supplyPerValueX128, 1, (uint256(type(uint96).max) << 128) / assets);
        almCore.setLastExchangeRate(supplyPerValueX128, sqrtPriceX96(pool));
        token1.mint(address(almCore), assets);

        // When: The token1 vault records the deposit.
        // Then: It reverts.
        vm.prank(asyncVault1);
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.recordDepositRequest(controller, assets);
    }

    function testFuzz_Success_recordDepositRequest_PendingSharesAtUint96(PoolState memory poolState, uint256 first)
        public
    {
        // Given: A pool with depth, and an exchange rate reserving one aLP per token1.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setLastExchangeRate(1 << 128, sqrtPriceX96(pool));

        // And: A pending deposit.
        first = bound(first, 1, type(uint96).max - 1);
        recordDepositAt(asyncVault1, controller, first);

        // When: The token1 vault records a deposit taking the pending aLP to a uint96.
        recordDepositAt(asyncVault1, controller, type(uint96).max - first);

        // Then: The record reserves exactly the uint96 maximum.
        assertEq(almCore.depositRecord(asyncVault1, controller).pendingShares, type(uint96).max);
    }

    function testFuzz_Success_recordDepositRequest_Token0(
        PoolState memory poolState,
        address controller,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        vm.assume(controller != address(0) && controller != address(almCore));

        // And: The token0 vault has already moved the assets here.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: It records the request.
        recordDepositAt(asyncVault0, controller, assets);

        // Then: The record and the pending epoch hold the assets.
        assertEq(almCore.depositRecord(asyncVault0, controller).epoch, 0);
        assertEq(almCore.depositRecord(asyncVault0, controller).amountIn, assets);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, assets);

        // And: The assets are escrowed on the token0 side.
        uint256 escrowed0 = almCore.getEscrowed0();
        uint256 escrowed1 = almCore.getEscrowed1();
        assertEq(escrowed0, assets);
        assertEq(escrowed1, 0);

        // And: Every token the core holds is buffer, fee or escrow.
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0() + escrowed0);
    }

    function testFuzz_Success_recordDepositRequest_Token1(
        PoolState memory poolState,
        address controller,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        vm.assume(controller != address(0) && controller != address(almCore));

        // And: The token1 vault has already moved the assets here.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: It records the request.
        recordDepositAt(asyncVault1, controller, assets);

        // Then: The record and the pending epoch hold the assets.
        assertEq(almCore.depositRecord(asyncVault1, controller).epoch, 0);
        assertEq(almCore.depositRecord(asyncVault1, controller).amountIn, assets);
        assertEq(almCore.depositEpoch(asyncVault1, 0).amountIn, assets);

        // And: The assets are escrowed on the token1 side.
        uint256 escrowed0 = almCore.getEscrowed0();
        uint256 escrowed1 = almCore.getEscrowed1();
        assertEq(escrowed0, 0);
        assertEq(escrowed1, assets);

        // And: Every token the core holds is buffer, fee or escrow.
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1() + almCore.getProtocolFees1() + escrowed1);
    }

    function testFuzz_Success_recordDepositRequest_KeyedByVault(
        PoolState memory poolState,
        address controller,
        uint256 assets
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setPerUserCap(type(uint128).max);

        vm.assume(controller != address(0) && controller != address(almCore));

        // And: The same controller requests at both asynchronous vaults.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Both vaults record for it.
        recordDepositAt(asyncVault0, controller, assets);
        recordDepositAt(asyncVault1, controller, assets);

        // Then: The two queues stand apart, each denominated in its own vault's asset.
        assertEq(almCore.depositRecord(asyncVault0, controller).amountIn, assets);
        assertEq(almCore.depositRecord(asyncVault1, controller).amountIn, assets);
        uint256 escrowed0 = almCore.getEscrowed0();
        uint256 escrowed1 = almCore.getEscrowed1();
        assertEq(escrowed0, assets);
        assertEq(escrowed1, assets);
    }

    function testFuzz_Success_recordDepositRequest_CreditsTheSettledRecordFirst(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 settled
    ) public {
        // Given: A vault holding a range, and a deposit the keeper settled.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidQueueState(queueState, 2, 0);
        settled = bound(settled, 1, queueState.deposit0 - 1);
        uint256 assets = queueState.deposit0 - settled;
        recordDepositAt(asyncVault0, controller, settled);
        runPlan(Plan.init().clearAllRequests(true, true).settleRequests());
        uint256 shares = almCore.depositEpoch(asyncVault0, 0).amountOut;

        // When: The controller requests again.
        recordDepositAt(asyncVault0, controller, assets);

        // Then: The settled record is credited into the pile and the controller's escrow.
        assertEq(almCore.claimableDeposit(asyncVault0, controller).amountIn, settled);
        assertEq(almCore.claimableDeposit(asyncVault0, controller).amountOut, shares);
        assertEq(almCore.claimableSharesOf_(controller), shares);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountIn, 0);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, 0);

        // And: The new request lands in the new pending epoch.
        assertEq(almCore.depositRecord(asyncVault0, controller).epoch, 1);
        assertEq(almCore.depositRecord(asyncVault0, controller).amountIn, assets);
        assertEq(almCore.depositEpoch(asyncVault0, 1).amountIn, assets);
    }

    function testFuzz_Success_recordDepositRequest_AddsPendingShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A vault holding a range whose exchange rate a plan stored.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        runPlan(Plan.init());

        // And: A deposit, and the pending aLP the spot and the stored exchange rate give.
        givenValidQueueState(queueState, isToken0 ? 1 : 0, isToken0 ? 0 : 1);
        uint256 assets = isToken0 ? queueState.deposit0 : queueState.deposit1;
        (uint256 supplyPerValueX128, uint160 lastSqrtPrice) = almCore.lastExchangeRate_();
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 value;
        if (isToken0) {
            uint256 upper = FixedPointMathLib.max(sqrtPrice, lastSqrtPrice);
            value = assets.fullMulDivUp(upper, 1 << 96).fullMulDivUp(upper, 1 << 96);
        } else {
            value = sqrtPrice >= lastSqrtPrice
                ? assets
                : assets.fullMulDivUp(lastSqrtPrice, sqrtPrice).fullMulDivUp(lastSqrtPrice, sqrtPrice);
        }
        uint256 pending = value.fullMulDivUp(supplyPerValueX128, 1 << 128);
        address vault = isToken0 ? asyncVault0 : asyncVault1;

        // When: The vault records it.
        recordDepositAt(vault, controller, assets);

        // Then: The record and the controller both hold the pending aLP.
        assertEq(almCore.depositRecord(vault, controller).pendingShares, pending);
        assertEq(almCore.pendingShares_(controller), pending);
    }

    function testFuzz_Success_recordDepositRequest_AtThePerUserCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState
    ) public {
        // Given: A vault whose rate a plan stored, a deposit and its pending aLP.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        runPlan(Plan.init());
        givenValidQueueState(queueState, 1, 0);
        uint256 assets = queueState.deposit0;
        (uint256 supplyPerValueX128, uint160 lastSqrtPrice) = almCore.lastExchangeRate_();
        uint256 upper = FixedPointMathLib.max(sqrtPriceX96(pool), lastSqrtPrice);
        uint256 pending =
            assets.fullMulDivUp(upper, 1 << 96).fullMulDivUp(upper, 1 << 96).fullMulDivUp(supplyPerValueX128, 1 << 128);

        // And: A per user cap of exactly the pending aLP.
        vm.prank(factory);
        almCore.setPerUserCap(pending);
        token0.mint(address(almCore), assets);

        // When: The token0 vault records the deposit.
        vm.prank(asyncVault0);
        almCore.recordDepositRequest(controller, assets);

        // Then: The controller's cap balance sits at the cap.
        assertEq(almCore.pendingShares_(controller), almCore.perUserCap_());
    }

    function testFuzz_Success_recordDepositRequest_PendingSharesCoverTheCredit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        int256 tickOffset,
        bool isToken0,
        ConfigState memory configState
    ) public {
        // Given: A vault whose exchange rate a plan stored at the spot price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        runPlan(Plan.init());

        // And: A spot off the exchange rate's price, within a factor two of the TWAP.
        uint256 mean = almCore.meanSqrtPriceX96_();
        int24 tickFloor = TickMath.getTickAtSqrtPrice(uint160(mean / 2)) + 1;
        int24 tickCeiling =
            2 * mean < TickMath.MAX_SQRT_PRICE ? TickMath.getTickAtSqrtPrice(uint160(2 * mean)) : TickMath.MAX_TICK;
        tickOffset = bound(tickOffset, tickFloor - currentTick(pool), tickCeiling - currentTick(pool) - 1);
        if (tickOffset >= 0) ++tickOffset;
        int24 tick = int24(int256(currentTick(pool)) + tickOffset);
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(IMetadexCLPool.slot0.selector),
            abi.encode(TickMath.getSqrtPriceAtTick(tick), tick, uint16(0), uint16(1), uint16(1), true)
        );

        // And: A deposit recorded at that spot price.
        givenValidQueueState(queueState, isToken0 ? 1 : 0, isToken0 ? 0 : 1);
        uint256 assets = isToken0 ? queueState.deposit0 : queueState.deposit1;
        address vault = isToken0 ? asyncVault0 : asyncVault1;
        recordDepositAt(vault, controller, assets);
        vm.clearMockedCalls();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper settles the epoch at the same price.
        runPlan(Plan.init().clearAllRequests(isToken0, true).settleRequests());

        // Then: The pending aLP is at least what the epoch credits the record.
        assertGe(almCore.depositRecord(vault, controller).pendingShares, almCore.depositEpoch(vault, 0).amountOut);
    }

    function testFuzz_Success_recordDepositRequest_ExemptPastTheCap(PoolState memory poolState, uint256 assets) public {
        // Given: A pool at a fuzzed price, a zero per user cap and an exempt controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        almCore.setLastExchangeRate(1 << 128, sqrtPriceX96(pool));
        vm.startPrank(factory);
        almCore.setPerUserCap(0);
        almCore.setCapExempt(controller, true);
        vm.stopPrank();
        assets = bound(assets, 1, type(uint96).max);

        // When: The token1 vault records a deposit for it.
        token1.mint(address(almCore), assets);
        vm.prank(asyncVault1);
        almCore.recordDepositRequest(controller, assets);

        // Then: It is not checked, and its pending aLP still moves, one per token1.
        assertEq(almCore.pendingShares_(controller), assets);
    }

    function testFuzz_Success_recordDepositRequest_DoesNotEnrichHolders(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        address controller_
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(controller_ != address(0) && controller_ != address(almCore));

        // And: A vault holding a range, its range principal and buffers.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        (uint256 before0, uint256 before1) = amountsRoundedDown(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        (before0, before1) = (before0 + almCore.bufferAmount0(), before1 + almCore.bufferAmount1());

        // And: A deposit the token0 vault moved to the core.
        givenValidQueueState(queueState, 1, 0);
        token0.mint(address(almCore), queueState.deposit0);

        // When: The token0 vault records the request.
        vm.prank(asyncVault0);
        almCore.recordDepositRequest(controller_, queueState.deposit0);

        // Then: What the existing holders own did not move.
        Range memory staged = almCore.getRange(range.index);
        (uint256 after0, uint256 after1) = amountsRoundedDown(
            uint160(sqrtPriceX96(pool)),
            staged.tickLower,
            staged.tickUpper,
            positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
        );
        assertEq(after0 + almCore.bufferAmount0(), before0);
        assertEq(after1 + almCore.bufferAmount1(), before1);
    }
}
