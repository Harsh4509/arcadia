/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { Plan } from "../../utils/Plan.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { stdError } from "@forge-std/StdError.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the command "SWAP_VIA_POOL" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract SwapViaPool_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_swapViaPool_OnlyKeeper(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address caller,
        bool zeroForOne,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The caller is not a keeper.
        vm.assume(caller != users.keeper);
        Plan.Steps memory plan = Plan.init().swapViaPool(zeroForOne, amountIn, priceLimit(zeroForOne), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling swap().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool zeroForOne,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The vault is paused.
        vm.prank(factory);
        almCore.pause();
        Plan.Steps memory plan = Plan.init().swapViaPool(zeroForOne, amountIn, priceLimit(zeroForOne), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls swap().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_InvalidPayload_OpenBalance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool zeroForOne,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: An open buffer flag on a remainder above the bps denominator.
        bps = bound(bps, ConfigLib.BPS_DENOMINATOR + 1, Sentinels.OPEN_BALANCE - 1);
        Plan.Steps memory plan =
            Plan.init().swapViaPool(zeroForOne, Sentinels.OPEN_BALANCE | bps, priceLimit(zeroForOne), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_InvalidPayload_TargetRatio(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool zeroForOne,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A target ratio flag on a remainder above the bps denominator.
        bps = bound(bps, ConfigLib.BPS_DENOMINATOR + 1, Sentinels.TO_TARGET_RATIO - 1);
        Plan.Steps memory plan =
            Plan.init().swapViaPool(zeroForOne, Sentinels.TO_TARGET_RATIO | bps, priceLimit(zeroForOne), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_InvalidPayload_BothSentinels(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool zeroForOne,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Both sentinel flags on any remainder.
        bps = bound(bps, 0, Sentinels.TO_TARGET_RATIO - 1);
        Plan.Steps memory plan = Plan.init()
            .swapViaPool(
                zeroForOne, Sentinels.OPEN_BALANCE | Sentinels.TO_TARGET_RATIO | bps, priceLimit(zeroForOne), 0
            );
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_TransferFailed_InputAboveTheBalance(
        PoolState memory poolState,
        uint256 buffer0,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A token0 buffer, and an input above it the pool can fill.
        uint256 capacity = SqrtPriceMath.getAmount0Delta(
            TickMath.getSqrtPriceAtTick(-bandTick(poolState.tickSpacing)), sqrtPriceX96(pool), pool.liquidity(), false
        );
        fundBuffer(bound(buffer0, 0, capacity - 1), 0);
        amountIn = bound(amountIn, token0.balanceOf(address(almCore)) + 1, capacity);
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps.
        // Then: It reverts on paying the pool.
        vm.prank(users.keeper);
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_ArithmeticError_InputWithinTheEscrow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 capacity0 = SqrtPriceMath.getAmount0Delta(
            uint160(poolState.sqrtPrice / 2), uint160(poolState.sqrtPrice), poolState.liquidityPool, false
        );

        // And: A seeded vault with a range, its spare token0 within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        (uint256 amount0,) = amountsRoundedUp(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        coreState.buffer0 = amount0
            + bound(
                coreState.buffer0 - amount0,
                amount0 > 0 ? 0 : 1,
                FixedPointMathLib.min(amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4, capacity0 / 2)
            );
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: A pending token0 deposit of the least input or more, in escrow.
        uint256 least = leastSwapIn(true);
        givenValidQueueState(queueState, FixedPointMathLib.max(least, 1), 0);
        setQueueState(queueState);

        // And: A token0 input over the buffer and the least, within escrow and depth.
        least = FixedPointMathLib.max(almCore.bufferAmount0() + 1, least);
        amountIn = bound(
            amountIn,
            least,
            FixedPointMathLib.max(least, FixedPointMathLib.min(token0.balanceOf(address(almCore)), capacity0))
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: A max swap cost the swap fits.
        givenValidPlanLimits(configState, 0, leastSwapCostBps(true, amountIn, poolSwapOut(true, amountIn)));
        setPlanLimits(configState);

        // When: The keeper swaps.
        // Then: The buffer ledger underflows.
        vm.prank(users.keeper);
        vm.expectRevert(stdError.arithmeticError);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_TooManySwaps(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 amountIn,
        bool firstViaRouter,
        bool withClose,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, and at least a wei of token0 in the buffer.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A pending token1 deposit.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit1 = bound(queueState.deposit1, 1, Constants.MAX_FUZZED_AMOUNT / 4);
        setQueueState(queueState);

        // And: A first input inside the current tick spacing, in the buffer.
        amountIn = spacingSwapIn(amountIn, true);
        fundShortfall(amountIn, 0);

        // And: A plan, with or without a clear step, that swaps twice in the pool.
        Plan.Steps memory plan = withClose ? Plan.init().clearAllRequests(false, true) : Plan.init();
        plan = firstViaRouter
            ? plan.swapAtRate(
                address(token0),
                address(token1),
                address(routerTrampoline),
                true,
                amountIn,
                token0ToToken1(poolState.sqrtPrice, amountIn)
            )
            : plan.swapViaPool(true, amountIn, priceLimit(true), 0);
        plan = plan.settleRequests().swapViaPool(true, amountIn, priceLimit(true), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: A max swap cost the first swap fits.
        givenValidPlanLimits(
            configState, 0, firstViaRouter ? 0 : leastSwapCostBps(true, amountIn, poolSwapOut(true, amountIn))
        );
        setPlanLimits(configState);

        // When: The keeper runs the plan.
        // Then: It reverts on the second swap.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.TooManySwaps.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_AS_OpenBalanceOfABufferWhollyOwed(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, its spare token0 an eighth amount at most.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        (uint256 amount0,) = amountsRoundedUp(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        coreState.buffer0 = amount0
            + bound(
                coreState.buffer0 - amount0,
                amount0 > 0 ? 0 : 1,
                FixedPointMathLib.min(
                    amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                    token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                )
            );
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: A token1 buffer worth more than twice the token0 buffer.
        uint256 worth0 = almCore.bufferAmount0().fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
        fundShortfall(0, 2 * worth0 + 1);

        // And: A token0 redeem owed the whole token0 buffer or more.
        uint256 value;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
        }
        uint256 supply = almCore.totalSupply();
        shares = bound(shares, FixedPointMathLib.max(1, worth0.fullMulDivUp(supply, value - worth0)), supply);
        recordRedeemAt(asyncVault0, controller, shares);

        // And: A sale of a share of the open buffer of token0.
        bps = bound(bps, 1, ConfigLib.BPS_DENOMINATOR);
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, false)
            .swapViaPool(true, Sentinels.OPEN_BALANCE | bps, priceLimit(true), 0)
            .settleRequests();
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper clears the redeem and swaps.
        // Then: The pool rejects the zero input.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("AS"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_AS_TargetRatioNeedingNoSale(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, and at least a wei of token1 in the buffer.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        fundShortfall(0, 1);

        // And: A target share of token0 at or above its share of the buffer.
        uint256 buffer0 = almCore.bufferAmount0();
        bps = bound(
            bps,
            buffer0.fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192)
                .fullMulDivUp(
                    ConfigLib.BPS_DENOMINATOR, token0ToToken1(poolState.sqrtPrice, buffer0) + almCore.bufferAmount1()
                ),
            ConfigLib.BPS_DENOMINATOR
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(true, Sentinels.TO_TARGET_RATIO | bps, priceLimit(true), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper sells token0 to the target ratio.
        // Then: The pool rejects the zero input.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("AS"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_AS_OpenBalanceAtZeroBps(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool zeroForOne,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A sale of no share of the open buffer.
        Plan.Steps memory plan = Plan.init().swapViaPool(zeroForOne, Sentinels.OPEN_BALANCE, priceLimit(zeroForOne), 0);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps.
        // Then: The pool rejects the zero input.
        vm.prank(users.keeper);
        vm.expectRevert(bytes("AS"));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_MaxSwapCostExceeded_ZeroForOne(
        PoolState memory poolState,
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price, a max swap cost and a trusted price near spot.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            spot.fullMulDivUp(1e18, 1e18 + Constants.WIDE_DEVIATION),
            spot.fullMulDiv(1e18 + Constants.WIDE_DEVIATION, 1e18)
        );

        // And: A token0 sale worth a token1 wei, filled a wei below its spot floor.
        amountIn = bound(
            amountIn,
            uint256(1).fullMulDivUp(1 << 192, spot * spot),
            FixedPointMathLib.min(token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT), Constants.MAX_FUZZED_AMOUNT)
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(amountIn, 0);
        token1.mint(address(almCore), floor - 1);
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.swap, (address(almCore), true, int256(amountIn), priceLimit(true), bytes(""))),
            abi.encode(int256(amountIn), -int256(floor - 1))
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.MaxSwapCostExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));
    }

    function testFuzz_Revert_swapViaPool_MaxSwapCostExceeded_OneForZero(
        PoolState memory poolState,
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price, a max swap cost and a trusted price near spot.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            spot.fullMulDivUp(1e18, 1e18 + Constants.WIDE_DEVIATION),
            spot.fullMulDiv(1e18 + Constants.WIDE_DEVIATION, 1e18)
        );

        // And: A token0 purchase worth a token0 wei, filled a wei below its spot floor.
        amountIn = bound(
            amountIn,
            uint256(1).fullMulDivUp(spot * spot, 1 << 192),
            FixedPointMathLib.min(token0ToToken1(spot, Constants.MAX_FUZZED_AMOUNT), Constants.MAX_FUZZED_AMOUNT)
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, 1 << 192, spot * spot),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(0, amountIn);
        token0.mint(address(almCore), floor - 1);
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.swap, (address(almCore), false, int256(amountIn), priceLimit(false), bytes(""))),
            abi.encode(-int256(floor - 1), int256(amountIn))
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(false, amountIn, priceLimit(false), 0);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.MaxSwapCostExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));
    }

    function testFuzz_Revert_swapViaPool_MaxSwapCostExceeded_PartialFill(
        PoolState memory poolState,
        uint256 amountIn,
        uint256 amountInUsed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a max swap cost.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);

        // And: A token0 sale cut short by the limit, filled a wei below its used floor.
        uint256 minAmountIn = uint256(1).fullMulDivUp(1 << 192, spot * spot);
        amountIn = bound(
            amountIn,
            minAmountIn + 1,
            FixedPointMathLib.min(token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT), Constants.MAX_FUZZED_AMOUNT)
        );
        amountInUsed = bound(amountInUsed, minAmountIn, amountIn - 1);
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountInUsed, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(amountIn, 0);
        token1.mint(address(almCore), floor - 1);
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.swap, (address(almCore), true, int256(amountIn), priceLimit(true), bytes(""))),
            abi.encode(int256(amountInUsed), -int256(floor - 1))
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.MaxSwapCostExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, uint160(spot));
    }

    function testFuzz_Revert_swapViaPool_InsufficientOutput(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool zeroForOne,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: An input in the buffer, inside the current tick spacing and a TokenDelta.
        int24 tickBelow = poolState.tickCurrent
            - (poolState.tickCurrent % poolState.tickSpacing + poolState.tickSpacing) % poolState.tickSpacing;
        uint160 edge = TickMath.getSqrtPriceAtTick(zeroForOne ? tickBelow : tickBelow + poolState.tickSpacing);
        uint256 ceiling = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(edge, sqrtPriceX96(pool), pool.liquidity(), true)
            : SqrtPriceMath.getAmount1Delta(sqrtPriceX96(pool), edge, pool.liquidity(), true);
        amountIn = bound(amountIn, 1, FixedPointMathLib.min(ceiling - 1, Constants.MAX_FUZZED_AMOUNT));
        fundBuffer(zeroForOne ? amountIn : 0, zeroForOne ? 0 : amountIn);

        // And: The output of the pool's swap step for that input.
        uint256 amountOut = swapStepOut(pool, amountIn, edge);
        Plan.Steps memory plan = Plan.init().swapViaPool(zeroForOne, amountIn, priceLimit(zeroForOne), amountOut + 1);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls swap() demanding one wei more.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InsufficientOutput.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaPool_InsufficientOutput_TighterAmountOutMinStillBinds(
        PoolState memory poolState,
        uint256 amountIn,
        uint256 margin,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a max swap cost.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);

        // And: A minimum output above the floor, and a token0 sale filled a wei below it.
        amountIn = bound(
            amountIn,
            1,
            FixedPointMathLib.min(token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT), Constants.MAX_FUZZED_AMOUNT)
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        uint256 minAmountOut = floor + bound(margin, 1, Constants.MAX_FUZZED_AMOUNT);
        fundBuffer(amountIn, 0);
        token1.mint(address(almCore), minAmountOut - 1);
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.swap, (address(almCore), true, int256(amountIn), priceLimit(true), bytes(""))),
            abi.encode(int256(amountIn), -int256(minAmountOut - 1))
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amountIn, priceLimit(true), minAmountOut);

        // When: The keeper swaps.
        // Then: It reverts on the minimum output.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InsufficientOutput.selector);
        almCore.execute(plan.commands, plan.inputs, uint160(spot));
    }

    function testFuzz_Success_swapViaPool_ZeroForOne(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        uint256 surplus1,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A buffer with an input inside the current tick spacing, and some token1.
        int24 tickBelow = poolState.tickCurrent
            - (poolState.tickCurrent % poolState.tickSpacing + poolState.tickSpacing) % poolState.tickSpacing;
        uint160 edge = TickMath.getSqrtPriceAtTick(tickBelow);
        amountIn = spacingSwapIn(amountIn, true);
        surplus1 = bound(surplus1, 0, Constants.MAX_FUZZED_AMOUNT);
        fundBuffer(amountIn, surplus1);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        uint256 amountOut = swapStepOut(pool, amountIn, edge);

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, true, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager swaps the whole input.
        runPlan(Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0));

        // Then: The input left the buffer and the pool's output arrived in it.
        assertEq(almCore.bufferAmount0(), buffer0Before - amountIn);
        assertEq(almCore.bufferAmount1(), buffer1Before + amountOut);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_swapViaPool_OneForZero(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        uint256 surplus0,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A buffer with an input inside the current tick spacing, and some token0.
        int24 tickBelow = poolState.tickCurrent
            - (poolState.tickCurrent % poolState.tickSpacing + poolState.tickSpacing) % poolState.tickSpacing;
        uint160 edge = TickMath.getSqrtPriceAtTick(tickBelow + poolState.tickSpacing);
        amountIn = spacingSwapIn(amountIn, false);
        surplus0 = bound(surplus0, 0, Constants.MAX_FUZZED_AMOUNT);
        fundBuffer(surplus0, amountIn);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        uint256 amountOut = swapStepOut(pool, amountIn, edge);

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, false, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager swaps the whole input.
        runPlan(Plan.init().swapViaPool(false, amountIn, priceLimit(false), 0));

        // Then: The input left the buffer and the pool's output arrived in it.
        assertEq(almCore.bufferAmount1(), buffer1Before - amountIn);
        assertEq(almCore.bufferAmount0(), buffer0Before + amountOut);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_swapViaPool_MeetsAmountOutMin(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: An input in the buffer, inside the current tick spacing and a TokenDelta.
        int24 tickBelow = poolState.tickCurrent
            - (poolState.tickCurrent % poolState.tickSpacing + poolState.tickSpacing) % poolState.tickSpacing;
        uint160 edge = TickMath.getSqrtPriceAtTick(tickBelow);
        amountIn = spacingSwapIn(amountIn, true);
        fundBuffer(amountIn, 0);
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: The output of the pool's swap step for that input.
        uint256 amountOut = swapStepOut(pool, amountIn, edge);

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, true, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager calls swap() demanding exactly that.
        runPlan(Plan.init().swapViaPool(true, amountIn, priceLimit(true), amountOut));

        // Then: The output is credited.
        assertEq(almCore.bufferAmount1() - buffer1Before, amountOut);
    }

    function testFuzz_Success_swapViaPool_OpenBalance(
        uint256 amountIn,
        uint256 surplus1,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, its spare token0 inside the current spacing.
        uint160 edge = TickMath.getSqrtPriceAtTick(
            poolState.tickCurrent - (poolState.tickCurrent % poolState.tickSpacing + poolState.tickSpacing)
                % poolState.tickSpacing
        );
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        (uint256 amount0,) = amountsRoundedUp(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        {
            uint256 most = FixedPointMathLib.max(
                amount0 > 0 ? 0 : 1,
                FixedPointMathLib.min(
                    amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                    SqrtPriceMath.getAmount0Delta(edge, uint160(poolState.sqrtPrice), poolState.liquidityPool, true) / 2
                )
            );
            coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, amount0 > 0 ? 0 : 1, most);
        }
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: The least token0 input or more inside the spacing, and some token1.
        uint256 ceiling = SqrtPriceMath.getAmount0Delta(edge, sqrtPriceX96(pool), pool.liquidity(), true);
        amountIn = bound(
            amountIn,
            leastSwapIn(true),
            FixedPointMathLib.min(ceiling - 1, Constants.MAX_FUZZED_AMOUNT) - almCore.bufferAmount0()
        );
        surplus1 = bound(surplus1, 0, Constants.MAX_FUZZED_AMOUNT);
        fundBuffer(amountIn, surplus1);
        uint256 buffer1Before = almCore.bufferAmount1();
        uint256 amountOut = swapStepOut(pool, almCore.bufferAmount0(), edge);

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, true, almCore.bufferAmount0(), amountOut);
        setPlanLimits(configState);

        // When: The manager swaps the buffer's balance of token0.
        runPlan(Plan.init().swapViaPool(true, Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR, priceLimit(true), 0));

        // Then: The whole token0 buffer left and the pool's output arrived in the buffer.
        assertEq(almCore.bufferAmount0(), 0);
        assertEq(almCore.bufferAmount1(), buffer1Before + amountOut);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_swapViaPool_OpenBalanceShare(
        bool zeroForOne,
        uint256 bps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, its spare tokens within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = amount0
                + bound(
                    coreState.buffer0 - amount0,
                    amount0 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        SqrtPriceMath.getAmount0Delta(
                            uint160(poolState.sqrtPrice / 2),
                            uint160(poolState.sqrtPrice),
                            poolState.liquidityPool,
                            false
                        ) / 2
                    )
                );
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    amount1 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                        SqrtPriceMath.getAmount1Delta(
                            uint160(poolState.sqrtPrice),
                            uint160(2 * poolState.sqrtPrice),
                            poolState.liquidityPool,
                            false
                        ) / 2
                    )
                );
        }
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: The least input of each token in the buffer at the least.
        fundShortfall(leastSwapIn(true), leastSwapIn(false));
        ERC20Mock tokenIn = zeroForOne ? token0 : token1;
        uint256 bufferIn = zeroForOne ? almCore.bufferAmount0() : almCore.bufferAmount1();
        uint256 poolBalanceIn = tokenIn.balanceOf(address(pool));

        // And: A share of the open buffer that sells the least input at the least.
        bps = bound(
            bps, (leastSwapIn(zeroForOne) * ConfigLib.BPS_DENOMINATOR).divUp(bufferIn), ConfigLib.BPS_DENOMINATOR
        );

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = bufferIn * bps / ConfigLib.BPS_DENOMINATOR;
            givenValidPlanLimits(configState, 1, zeroForOne, sale, poolSwapOut(zeroForOne, sale));
        }
        setPlanLimits(configState);

        // When: The keeper sells that share of the input token's open buffer.
        runPlan(Plan.init().swapViaPool(zeroForOne, Sentinels.OPEN_BALANCE | bps, priceLimit(zeroForOne), 0));

        // Then: The pool took that share of the input token's buffer, out of the buffer.
        uint256 sold = bufferIn * bps / ConfigLib.BPS_DENOMINATOR;
        assertEq(tokenIn.balanceOf(address(pool)), poolBalanceIn + sold);
        assertEq(zeroForOne ? almCore.bufferAmount0() : almCore.bufferAmount1(), bufferIn - sold);
    }

    function testFuzz_Success_swapViaPool_OpenBalanceShareIsOfTheBufferLessThePayout(
        bool zeroForOne,
        uint256 bps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, its spare tokens within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = amount0
                + bound(
                    coreState.buffer0 - amount0,
                    amount0 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        SqrtPriceMath.getAmount0Delta(
                            uint160(poolState.sqrtPrice / 2),
                            uint160(poolState.sqrtPrice),
                            poolState.liquidityPool,
                            false
                        ) / 2
                    )
                );
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    amount1 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                        SqrtPriceMath.getAmount1Delta(
                            uint160(poolState.sqrtPrice),
                            uint160(2 * poolState.sqrtPrice),
                            poolState.liquidityPool,
                            false
                        ) / 2
                    )
                );
        }
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        uint256 open;
        {
            // And: Twice the least input, the output token worth two token1 wei.
            uint256 least = leastSwapIn(zeroForOne);
            fundShortfall(
                zeroForOne ? 2 * least : uint256(2).fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice),
                zeroForOne ? 2 : 2 * least
            );

            // And: Queued deposits, and a redeem of the input token its buffer covers.
            givenValidQueueState(queueState, 0, 0);
            {
                uint256 value;
                {
                    (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                        uint160(poolState.sqrtPrice),
                        range.tickLower,
                        range.tickUpper,
                        range.liquidity + range.liquidityStaked
                    );
                    value = principal1 + almCore.bufferAmount1()
                        + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
                }
                uint256 bufferIn = zeroForOne ? almCore.bufferAmount0() : almCore.bufferAmount1();
                uint256 shares = zeroForOne ? token0ToToken1(poolState.sqrtPrice, bufferIn - least) : bufferIn - least;
                shares = FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2, shares.fullMulDiv(coreState.supply, value)
                );
                shares = bound(zeroForOne ? queueState.redeem0 : queueState.redeem1, 0, shares);
                queueState.redeem0 = zeroForOne ? shares : 0;
                queueState.redeem1 = zeroForOne ? 0 : shares;
                setQueueState(queueState);
                open = bufferIn
                    - (zeroForOne
                            ? token1ToToken0(poolState.sqrtPrice, shares.fullMulDiv(value, coreState.supply))
                            : shares.fullMulDiv(value, coreState.supply));
            }

            // And: A share of the open buffer that sells the least input at the least.
            bps = bound(bps, (least * ConfigLib.BPS_DENOMINATOR).divUp(open), ConfigLib.BPS_DENOMINATOR);
        }
        uint256 poolBalanceIn = (zeroForOne ? token0 : token1).balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = open * bps / ConfigLib.BPS_DENOMINATOR;
            uint256 out = poolSwapOut(zeroForOne, sale);
            givenValidPlanLimits(configState, 3, zeroForOne, sale, out);
        }
        setPlanLimits(configState);

        // When: The keeper clears the output deposit and the redeem, selling that share.
        Plan.Steps memory plan = Plan.init().clearAllRequests(!zeroForOne, true).clearAllRequests(zeroForOne, false);
        runPlan(plan.swapViaPool(zeroForOne, Sentinels.OPEN_BALANCE | bps, priceLimit(zeroForOne), 0).settleRequests());

        // Then: The pool took that share of the buffer less the redeem's payout.
        assertEq(
            (zeroForOne ? token0 : token1).balanceOf(address(pool)),
            poolBalanceIn + open * bps / ConfigLib.BPS_DENOMINATOR
        );
    }

    function testFuzz_Success_swapViaPool_OpenBalanceLeavesThePayouts(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, its spare token0 within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = amount0
                + bound(
                    coreState.buffer0 - amount0,
                    amount0 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        SqrtPriceMath.getAmount0Delta(
                            uint160(poolState.sqrtPrice / 2),
                            uint160(poolState.sqrtPrice),
                            poolState.liquidityPool,
                            false
                        ) / 2
                    )
                );
        }
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: Twice the least token0 input and a wei of token1 in the buffer.
        uint256 least = leastSwapIn(true);
        fundShortfall(2 * least, 1);

        // And: Queued deposits, and a token0 redeem the token0 buffer covers.
        givenValidQueueState(queueState, 0, 0);
        uint256 value;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
        }
        queueState.redeem0 = bound(
            queueState.redeem0,
            0,
            FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2,
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() - least).fullMulDiv(coreState.supply, value)
            )
        );
        setQueueState(queueState);
        uint256 open0 = almCore.bufferAmount0()
            - token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, coreState.supply));
        uint256 poolBalance0 = token0.balanceOf(address(pool));
        uint256 poolBalance1 = token1.balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = open0;
            givenValidPlanLimits(configState, 3, true, sale, poolSwapOut(true, sale));
        }
        setPlanLimits(configState);

        // When: The keeper clears a deposit and the redeem, and sells all open token0.
        runPlan(
            Plan.init()
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .swapViaPool(true, Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR, priceLimit(true), 0)
                .settleRequests()
        );

        // Then: The pool took the token0 buffer less the token0 the redeem is owed.
        assertEq(token0.balanceOf(address(pool)), poolBalance0 + open0);

        // And: The redeem settles at the value after the fill, its payout in escrow.
        {
            uint256 owed0 = token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, coreState.supply));
            value = FixedPointMathLib.min(
                value,
                (value + poolBalance1 - token1.balanceOf(address(pool)))
                .zeroFloorSub(open0.fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192))
            );
            assertEq(
                almCore.redeemEpoch(asyncVault0, 0).amountOut,
                token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, coreState.supply))
            );
            assertEq(almCore.bufferAmount0(), owed0 - almCore.redeemEpoch(asyncVault0, 0).amountOut);
        }
        assertEq(almCore.getEscrowed0() - queueState.deposit0, almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaPool_OpenBalanceSlackLeavesThePayoutsAndTheLevy(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 slack,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 capacity0 = SqrtPriceMath.getAmount0Delta(
            uint160(poolState.sqrtPrice / 2), uint160(poolState.sqrtPrice), poolState.liquidityPool, false
        );

        // And: A seeded vault with a range, its spare token0 within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        (uint256 amount0,) = amountsRoundedUp(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        coreState.buffer0 = amount0
            + bound(
                coreState.buffer0 - amount0,
                amount0 > 0 ? 0 : 1,
                FixedPointMathLib.min(amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4, capacity0 / 2)
            );
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: Token0 a bps of which covers a token1 wei of payout, and a wei of token1.
        uint256 floor0 = FixedPointMathLib.max(token1ToToken0(poolState.sqrtPrice, 1) + 2, leastSwapIn(true))
            * ConfigLib.BPS_DENOMINATOR;
        fundShortfall(floor0, 1);

        // And: Queued deposits, token0 ones worth less than the token1 buffer.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit0 = bound(
            queueState.deposit0,
            0,
            FixedPointMathLib.min(
                capacity0.zeroFloorSub(almCore.bufferAmount0()),
                token1ToToken0(poolState.sqrtPrice, almCore.bufferAmount1() - 1)
            )
        );

        // And: A token0 redeem whose payout leaves that much of the token0 buffer.
        uint256 value;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
        }
        {
            uint256 most = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() - floor0)
                .fullMulDiv(coreState.supply, value);
            most = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, most);
            queueState.redeem0 = bound(queueState.redeem0, 0, most);
        }
        setQueueState(queueState);
        uint256 open0 = almCore.bufferAmount0() + queueState.deposit0
            - token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, coreState.supply));

        // And: A slack of any share short of the whole.
        slack = bound(slack, 1, ConfigLib.BPS_DENOMINATOR - 1);
        uint256 poolBalance0 = token0.balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = open0 * (ConfigLib.BPS_DENOMINATOR - slack) / ConfigLib.BPS_DENOMINATOR;
            givenValidPlanLimits(configState, 5, true, sale, poolSwapOut(true, sale));
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and sells the open token0 less the slack.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .swapViaPool(true, Sentinels.OPEN_BALANCE | (ConfigLib.BPS_DENOMINATOR - slack), priceLimit(true), 0)
                .settleRequests()
        );

        // Then: The pool took the open token0 less the slack.
        assertEq(
            token0.balanceOf(address(pool)),
            poolBalance0 + open0 * (ConfigLib.BPS_DENOMINATOR - slack) / ConfigLib.BPS_DENOMINATOR
        );

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaPool_TargetRatioPastTheExactSellsToken0AndSettles(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 capacity0 = SqrtPriceMath.getAmount0Delta(
            uint160(poolState.sqrtPrice / 2), uint160(poolState.sqrtPrice), poolState.liquidityPool, false
        );

        // And: A seeded vault with a range, its spare token0 within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = amount0
                + bound(
                    coreState.buffer0 - amount0,
                    amount0 > 0 ? 0 : 1,
                    FixedPointMathLib.min(amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4, capacity0 / 2)
                );
        }
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: A wei of token0 and two of token1 in the buffer at the least.
        uint256 least0 = leastSwapIn(true);
        fundShortfall(2 * least0, 2);

        // And: Queued deposits, token0 ones worth less than the token1 buffer.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit0 = bound(
            queueState.deposit0,
            0,
            FixedPointMathLib.min(
                capacity0.zeroFloorSub(almCore.bufferAmount0()),
                token1ToToken0(poolState.sqrtPrice, almCore.bufferAmount1() - 1)
            )
        );

        // And: A token1 redeem the token1 buffer covers with two wei to spare.
        uint256 value;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
        }
        queueState.redeem1 = bound(
            queueState.redeem1,
            0,
            FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2, (almCore.bufferAmount1() - 2).fullMulDiv(coreState.supply, value)
            )
        );
        setQueueState(queueState);
        uint256 buffer0 = almCore.bufferAmount0() + queueState.deposit0;
        uint256 open = (token0ToToken1(poolState.sqrtPrice, buffer0) + almCore.bufferAmount1() + queueState.deposit1)
        .zeroFloorSub(queueState.redeem1.fullMulDiv(value, coreState.supply));

        // And: A target share of token0 at which it sells.
        {
            uint256 most =
                token0ToToken1(poolState.sqrtPrice, buffer0 - least0).fullMulDiv(ConfigLib.BPS_DENOMINATOR, open);
            most = FixedPointMathLib.min(ConfigLib.BPS_DENOMINATOR, most);
            bps = bound(bps, 0, most);
        }
        uint256 poolBalance0 = token0.balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = buffer0 - token1ToToken0(poolState.sqrtPrice, open * bps / ConfigLib.BPS_DENOMINATOR);
            givenValidPlanLimits(configState, 5, true, sale, poolSwapOut(true, sale));
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and sells token0 to the target ratio.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(false, false)
                .swapViaPool(true, Sentinels.TO_TARGET_RATIO | bps, priceLimit(true), 0)
                .settleRequests()
        );

        // Then: The pool took the token0 above the target share of the open buffer.
        assertEq(
            token0.balanceOf(address(pool)),
            poolBalance0 + buffer0 - token1ToToken0(poolState.sqrtPrice, open * bps / ConfigLib.BPS_DENOMINATOR)
        );

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);
    }

    function testFuzz_Success_swapViaPool_TargetRatioPastTheExactBuysToken0AndSettles(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 capacity1 = SqrtPriceMath.getAmount1Delta(
            uint160(poolState.sqrtPrice), uint160(2 * poolState.sqrtPrice), poolState.liquidityPool, false
        );

        // And: A seeded vault with a range, its spare token1 within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    amount1 > 0 ? 0 : 1,
                    FixedPointMathLib.min(amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4, capacity1 / 2)
                );
        }
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: Token0 worth a token1 wei past a payout's rise, and a wei of token1.
        uint256 floor0 = token1ToToken0(poolState.sqrtPrice, 1) + 1;
        uint256 least1 = leastSwapIn(false);
        fundShortfall(floor0, 2 * least1);

        // And: Queued deposits, token1 ones worth less than the token0 buffer.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit1 = bound(
            queueState.deposit1,
            0,
            FixedPointMathLib.min(
                capacity1.zeroFloorSub(almCore.bufferAmount1()),
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()) - 1
            )
        );

        // And: A token0 redeem whose payout leaves that much of the token0 buffer.
        uint256 value;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
        }
        {
            uint256 most = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() - floor0)
                .fullMulDiv(coreState.supply, value);
            most = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, most);
            queueState.redeem0 = bound(queueState.redeem0, 0, most);
        }
        setQueueState(queueState);
        uint256 buffer1 = almCore.bufferAmount1() + queueState.deposit1;
        uint256 open = queueState.redeem0.fullMulDiv(value, coreState.supply);
        open = token0ToToken1(poolState.sqrtPrice, token1ToToken0(poolState.sqrtPrice, open));
        open = (token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0) + buffer1)
        .zeroFloorSub(open);

        // And: A target share of token0 at which token1 sells.
        bps = bound(
            bps,
            (open.zeroFloorSub(buffer1 - least1) * ConfigLib.BPS_DENOMINATOR).divUp(open),
            ConfigLib.BPS_DENOMINATOR
        );
        uint256 poolBalance1 = token1.balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = buffer1 - (open - open * bps / ConfigLib.BPS_DENOMINATOR);
            givenValidPlanLimits(configState, 5, false, sale, poolSwapOut(false, sale));
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and buys token0 to the target ratio.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .swapViaPool(false, Sentinels.TO_TARGET_RATIO | bps, priceLimit(false), 0)
                .settleRequests()
        );

        // Then: The pool took the token1 above the target share of the open buffer.
        assertEq(
            token1.balanceOf(address(pool)), poolBalance1 + buffer1 - (open - open * bps / ConfigLib.BPS_DENOMINATOR)
        );

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaPool_TargetRatioSellsToken0AboveItsPayout(
        uint256 bps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 margin;
        uint256 floor0;
        {
            uint256 capacity0 = SqrtPriceMath.getAmount0Delta(
                uint160(poolState.sqrtPrice / 2), uint160(poolState.sqrtPrice), poolState.liquidityPool, false
            );

            // And: A seeded vault with a range, its spare tokens within the pool's depth.
            givenValidRangeState(range, poolState, false);
            givenValidCoreState(coreState, poolState, range, 0, 0, 0);
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                coreState.buffer0 = amount0
                    + bound(
                        coreState.buffer0 - amount0,
                        amount0 > 0 ? 0 : 1,
                        FixedPointMathLib.min(amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4, capacity0 / 2)
                    );
                coreState.buffer1 = amount1
                    + bound(
                        coreState.buffer1 - amount1,
                        amount1 > 0 ? 0 : 1,
                        FixedPointMathLib.min(
                            amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                            token0ToToken1(poolState.sqrtPrice, capacity0)
                        )
                    );
            }
            coreState.supply = bound(
                coreState.supply,
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.max(
                    almCore.DEAD_SHARES_(),
                    FixedPointMathLib.min(
                        Constants.MAX_FUZZED_AMOUNT,
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                    )
                )
            );
            setCoreState(coreState);
            setRangeState(range);

            // And: Queued deposits, token1 ones worth at most the pool's token0 depth.
            givenValidQueueState(queueState, 0, 0);
            queueState.deposit1 = bound(queueState.deposit1, 0, token0ToToken1(poolState.sqrtPrice, capacity0));

            // And: A wei of token1, and token0 past a payout's rise by a bps of buffers.
            margin = (token1ToToken0(poolState.sqrtPrice, 1) + 1)
            .fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
            fundShortfall(0, 1);
            floor0 = (((margin + 1)
                        * ConfigLib.BPS_DENOMINATOR
                        + token0ToToken1(poolState.sqrtPrice, 1)
                        + 2
                        + almCore.bufferAmount1()
                        + queueState.deposit1)
                    .divUp(ConfigLib.BPS_DENOMINATOR - 1))
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 1;
            floor0 += 2 * leastSwapIn(true);
            fundShortfall(floor0, 1);

            // And: Token0 deposits under the token1 buffer, a token0 redeem leaving that.
            queueState.deposit0 = bound(
                queueState.deposit0,
                0,
                FixedPointMathLib.min(
                    capacity0.zeroFloorSub(almCore.bufferAmount0()),
                    token1ToToken0(poolState.sqrtPrice, almCore.bufferAmount1() - 1)
                )
            );
        }
        uint256 open0;
        uint256 open;
        {
            uint256 value;
            {
                (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = principal1 + almCore.bufferAmount1()
                    + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
            }
            {
                uint256 most = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() - floor0)
                    .fullMulDiv(coreState.supply, value);
                most = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, most);
                queueState.redeem0 = bound(queueState.redeem0, 0, most);
            }
            setQueueState(queueState);
            uint256 owed0 = token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, coreState.supply));
            open0 = almCore.bufferAmount0() + queueState.deposit0 - owed0;
            open = (token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                    + almCore.bufferAmount1() + queueState.deposit1)
            .zeroFloorSub(token0ToToken1(poolState.sqrtPrice, owed0));
        }

        // And: A target share of token0 that sells it and keeps that rise.
        {
            uint256 mostBps = FixedPointMathLib.min(
                ConfigLib.BPS_DENOMINATOR,
                token0ToToken1(poolState.sqrtPrice, open0 - leastSwapIn(true))
                    .fullMulDiv(ConfigLib.BPS_DENOMINATOR, open)
            );
            bps = bound(bps, margin.fullMulDivUp(ConfigLib.BPS_DENOMINATOR, open), mostBps);
        }
        uint256 poolBalance0 = token0.balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = open0 - token1ToToken0(poolState.sqrtPrice, open * bps / ConfigLib.BPS_DENOMINATOR);
            givenValidPlanLimits(configState, 5, true, sale, poolSwapOut(true, sale));
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and sells token0 to the target ratio.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .swapViaPool(true, Sentinels.TO_TARGET_RATIO | bps, priceLimit(true), 0)
                .settleRequests()
        );

        // Then: The pool took the token0 above the payout and the target share.
        assertEq(
            token0.balanceOf(address(pool)),
            poolBalance0 + open0 - token1ToToken0(poolState.sqrtPrice, open * bps / ConfigLib.BPS_DENOMINATOR)
        );

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaPool_TargetRatioBuysToken0WithToken1AboveItsPayout(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 capacity1 = SqrtPriceMath.getAmount1Delta(
            uint160(poolState.sqrtPrice), uint160(2 * poolState.sqrtPrice), poolState.liquidityPool, false
        );

        // And: A seeded vault with a range, its spare tokens within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = amount0
                + bound(
                    coreState.buffer0 - amount0,
                    amount0 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, capacity1)
                    )
                );
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    amount1 > 0 ? 0 : 1,
                    FixedPointMathLib.min(amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4, capacity1 / 2)
                );
        }
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: Queued deposits, token0 ones worth at most the pool's token1 depth.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit0 = bound(queueState.deposit0, 0, token1ToToken0(poolState.sqrtPrice, capacity1));

        // And: Token0 worth a wei, token1 past its payout by a bps and the least input.
        uint256 least1;
        uint256 floor1;
        {
            uint256 one0 = uint256(1).fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
            fundShortfall(one0, 0);
            least1 = leastSwapIn(false);
            floor1 = (token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                    + ConfigLib.BPS_DENOMINATOR * (least1 + 1))
            .divUp(ConfigLib.BPS_DENOMINATOR - 1);
            fundShortfall(one0, floor1);
        }

        // And: Token1 deposits under the token0 buffer, and a token1 redeem leaving that.
        queueState.deposit1 = bound(
            queueState.deposit1,
            0,
            FixedPointMathLib.min(
                capacity1.zeroFloorSub(almCore.bufferAmount1()),
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()) - 1
            )
        );
        uint256 value;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
        }
        queueState.redeem1 = bound(
            queueState.redeem1,
            0,
            FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2,
                (almCore.bufferAmount1() - floor1).fullMulDiv(coreState.supply, value)
            )
        );
        setQueueState(queueState);
        uint256 open1 =
            almCore.bufferAmount1() + queueState.deposit1 - queueState.redeem1.fullMulDiv(value, coreState.supply);
        uint256 open = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0) + open1;

        // And: A target share of token0 that sells the least token1 input and more.
        bps = bound(
            bps, ((open + least1 - open1) * ConfigLib.BPS_DENOMINATOR).divUp(open), ConfigLib.BPS_DENOMINATOR - 1
        );
        uint256 poolBalance1 = token1.balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = open1 - (open - open * bps / ConfigLib.BPS_DENOMINATOR);
            givenValidPlanLimits(configState, 5, false, sale, poolSwapOut(false, sale));
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and buys token0 to the target ratio.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(false, false)
                .swapViaPool(false, Sentinels.TO_TARGET_RATIO | bps, priceLimit(false), 0)
                .settleRequests()
        );

        // Then: The pool took the token1 above the payout and the target share.
        assertEq(
            token1.balanceOf(address(pool)), poolBalance1 + open1 - (open - open * bps / ConfigLib.BPS_DENOMINATOR)
        );

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);
    }

    function testFuzz_Success_swapViaPool_TargetRatioWithRedeemsInBothVaultsSettles(
        uint256 bps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 margin;
        uint256 floor0;
        {
            uint256 capacity0 = SqrtPriceMath.getAmount0Delta(
                uint160(poolState.sqrtPrice / 2), uint160(poolState.sqrtPrice), poolState.liquidityPool, false
            );

            // And: A seeded vault with a range, its spare tokens within the pool's depth.
            givenValidRangeState(range, poolState, false);
            givenValidCoreState(coreState, poolState, range, 0, 0, 0);
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                coreState.buffer0 = amount0
                    + bound(
                        coreState.buffer0 - amount0,
                        amount0 > 0 ? 0 : 1,
                        FixedPointMathLib.min(amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4, capacity0 / 2)
                    );
                coreState.buffer1 = amount1
                    + bound(
                        coreState.buffer1 - amount1,
                        amount1 > 0 ? 0 : 1,
                        FixedPointMathLib.min(
                            amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                            token0ToToken1(poolState.sqrtPrice, capacity0)
                        )
                    );
            }
            coreState.supply = bound(
                coreState.supply,
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.max(
                    almCore.DEAD_SHARES_(),
                    FixedPointMathLib.min(
                        Constants.MAX_FUZZED_AMOUNT,
                        coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                    )
                )
            );
            setCoreState(coreState);
            setRangeState(range);

            // And: Queued deposits, token1 ones worth at most the pool's token0 depth.
            givenValidQueueState(queueState, 0, 0);
            queueState.deposit1 = bound(queueState.deposit1, 0, token0ToToken1(poolState.sqrtPrice, capacity0));

            // And: Two wei of token1, token0 past a payout's rise by a bps of buffers.
            margin = (token1ToToken0(poolState.sqrtPrice, 2) + 1)
            .fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
            fundShortfall(0, 2);
            floor0 = (((margin + 1)
                        * ConfigLib.BPS_DENOMINATOR
                        + token0ToToken1(poolState.sqrtPrice, 1)
                        + 2
                        + almCore.bufferAmount1()
                        + queueState.deposit1)
                    .divUp(ConfigLib.BPS_DENOMINATOR - 1))
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 1;
            floor0 += 2 * leastSwapIn(true);
            fundShortfall(floor0, 2);

            // And: Token0 deposits under the token1 buffer, and redeems leaving those.
            queueState.deposit0 = bound(
                queueState.deposit0,
                0,
                FixedPointMathLib.min(
                    capacity0.zeroFloorSub(almCore.bufferAmount0()),
                    token1ToToken0(poolState.sqrtPrice, almCore.bufferAmount1() - 1)
                )
            );
        }
        uint256 open0;
        uint256 open;
        {
            uint256 value;
            {
                (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = principal1 + almCore.bufferAmount1()
                    + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
            }
            {
                uint256 most = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() - floor0)
                    .fullMulDiv(coreState.supply, value);
                most = FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, most);
                queueState.redeem0 = bound(queueState.redeem0, 0, most);
            }
            queueState.redeem1 = bound(
                queueState.redeem1,
                0,
                FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2,
                    (almCore.bufferAmount1() - 2).fullMulDiv(coreState.supply, value)
                )
            );
            setQueueState(queueState);
            uint256 owed0 = token1ToToken0(poolState.sqrtPrice, queueState.redeem0.fullMulDiv(value, coreState.supply));
            open0 = almCore.bufferAmount0() + queueState.deposit0 - owed0;
            open = (token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                    + almCore.bufferAmount1() + queueState.deposit1)
            .zeroFloorSub(
                token0ToToken1(poolState.sqrtPrice, owed0) + queueState.redeem1.fullMulDiv(value, coreState.supply)
            );
        }

        // And: A target share of token0 that sells it and keeps that rise.
        {
            uint256 mostBps = FixedPointMathLib.min(
                ConfigLib.BPS_DENOMINATOR,
                token0ToToken1(poolState.sqrtPrice, open0 - leastSwapIn(true))
                    .fullMulDiv(ConfigLib.BPS_DENOMINATOR, open)
            );
            bps = bound(bps, margin.fullMulDivUp(ConfigLib.BPS_DENOMINATOR, open), mostBps);
        }
        uint256 poolBalance0 = token0.balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = open0 - token1ToToken0(poolState.sqrtPrice, open * bps / ConfigLib.BPS_DENOMINATOR);
            givenValidPlanLimits(configState, 5, true, sale, poolSwapOut(true, sale));
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and sells token0 to the target ratio.
        runPlan(
            Plan.init()
                .clearAllRequests(true, true)
                .clearAllRequests(false, true)
                .clearAllRequests(true, false)
                .clearAllRequests(false, false)
                .swapViaPool(true, Sentinels.TO_TARGET_RATIO | bps, priceLimit(true), 0)
                .settleRequests()
        );

        // Then: The pool took the token0 above the payout and the target share.
        assertEq(
            token0.balanceOf(address(pool)),
            poolBalance0 + open0 - token1ToToken0(poolState.sqrtPrice, open * bps / ConfigLib.BPS_DENOMINATOR)
        );

        // And: Both redeems settle with their payouts in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);
    }

    function testFuzz_Success_swapViaPool_CancelBeforeThePlanTargetsTheWholeBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 shares,
        uint256 bps,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 capacity1 = SqrtPriceMath.getAmount1Delta(
            uint160(poolState.sqrtPrice), uint160(2 * poolState.sqrtPrice), poolState.liquidityPool, false
        );

        // And: A seeded vault with a range, its spare tokens within the pool's depth.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer0 = amount0
                + bound(
                    coreState.buffer0 - amount0,
                    amount0 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, capacity1)
                    )
                );
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    amount1 > 0 ? 0 : 1,
                    FixedPointMathLib.min(amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4, capacity1 / 2)
                );
        }
        coreState.supply = bound(
            coreState.supply,
            almCore.DEAD_SHARES_(),
            FixedPointMathLib.max(
                almCore.DEAD_SHARES_(),
                FixedPointMathLib.min(
                    Constants.MAX_FUZZED_AMOUNT,
                    coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0)
                )
            )
        );
        setCoreState(coreState);
        setRangeState(range);

        // And: Deposits, token0 ones within the pool's token1 depth, and pending redeems.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit0 = bound(queueState.deposit0, 0, token1ToToken0(poolState.sqrtPrice, capacity1));

        // And: Token0 worth a wei, token1 a bps past the least input and four floors.
        fundShortfall(uint256(1).fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice), 0);
        uint256 floor = (2 * ConfigLib.BPS_DENOMINATOR)
            .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice)
            .fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
        fundShortfall(
            0,
            FixedPointMathLib.max(
                (token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
                        + ConfigLib.BPS_DENOMINATOR * (leastSwapIn(false) + 1))
                .divUp(ConfigLib.BPS_DENOMINATOR - 1),
                4 * floor
            )
        );

        // And: Token1 deposits worth less than the token0 buffer.
        queueState.deposit1 = bound(
            queueState.deposit1,
            0,
            FixedPointMathLib.min(
                capacity1.zeroFloorSub(almCore.bufferAmount1()),
                token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0()) - 1
            )
        );
        setQueueState(queueState);

        // And: A token0 redeem worth two bps denominators, paid from the token0 buffer.
        uint256 value;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0());
        }
        uint256 supply = almCore.totalSupply();
        uint256 ceiling = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0)
            .fullMulDiv(supply, value);
        ceiling = FixedPointMathLib.min(supply / 2, ceiling);
        // And: A token0 buffer worth the floor in shares, a hole when a share outweighs it.
        vm.assume(floor.fullMulDivUp(supply, value - floor) <= ceiling);
        shares = bound(shares, floor.fullMulDivUp(supply, value - floor), ceiling);
        recordRedeemAt(asyncVault0, controller, shares);
        uint256 buffer1 = almCore.bufferAmount1() + queueState.deposit1;
        uint256 open = token0ToToken1(poolState.sqrtPrice, almCore.bufferAmount0() + queueState.deposit0) + buffer1;

        // And: A token0 purchase to a target under the whole, selling the least or more.
        bps = bound(
            bps,
            ((open - buffer1 + leastSwapIn(false)) * ConfigLib.BPS_DENOMINATOR).divUp(open),
            ConfigLib.BPS_DENOMINATOR - 1
        );
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .clearAllRequests(false, true)
            .swapViaPool(false, Sentinels.TO_TARGET_RATIO | bps, priceLimit(false), 0)
            .settleRequests();
        uint256 poolBalance1 = token1.balanceOf(address(pool));

        // And: Plan limits above the pool's cost for the sale and the plan's loss.
        {
            uint256 sale = buffer1 - (open - open * bps / ConfigLib.BPS_DENOMINATOR);
            givenValidPlanLimits(configState, 5, false, sale, poolSwapOut(false, sale));
        }
        setPlanLimits(configState);

        // When: The redeem is canceled before the plan runs.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, controller, controller);
        runPlan(plan);

        // Then: The purchase takes the token1 above the target of the whole buffer.
        assertEq(
            token1.balanceOf(address(pool)) - poolBalance1, buffer1 - (open - open * bps / ConfigLib.BPS_DENOMINATOR)
        );
    }

    function testFuzz_Success_swapViaPool_AtTheFloor_ZeroForOne(
        PoolState memory poolState,
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price, a max swap cost and a trusted price near spot.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            spot.fullMulDivUp(1e18, 1e18 + Constants.WIDE_DEVIATION),
            spot.fullMulDiv(1e18 + Constants.WIDE_DEVIATION, 1e18)
        );

        // And: A token0 sale filled at its spot value less the max swap cost.
        amountIn = bound(
            amountIn,
            uint256(1).fullMulDivUp(1 << 192, spot * spot),
            FixedPointMathLib.min(token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT), Constants.MAX_FUZZED_AMOUNT)
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(amountIn, 0);
        uint256 buffer1Before = almCore.bufferAmount1();
        token1.mint(address(almCore), floor);
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.swap, (address(almCore), true, int256(amountIn), priceLimit(true), bytes(""))),
            abi.encode(int256(amountIn), -int256(floor))
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0);

        // And: A max shortfall above the plan's loss at the trusted price.
        uint256 value = token0ToToken1(trustedSqrtPriceX96, amountIn);
        givenValidPlanLimits(
            configState,
            value > floor ? (value - floor).fullMulDivUp(ConfigLib.BPS_DENOMINATOR, value) : 0,
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper swaps at the trusted price.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));

        // Then: The output arrived in the buffer.
        assertEq(almCore.bufferAmount1(), buffer1Before + floor);
    }

    function testFuzz_Success_swapViaPool_AtTheFloor_OneForZero(
        PoolState memory poolState,
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price, a max swap cost and a trusted price near spot.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            spot.fullMulDivUp(1e18, 1e18 + Constants.WIDE_DEVIATION),
            spot.fullMulDiv(1e18 + Constants.WIDE_DEVIATION, 1e18)
        );

        // And: Twice the input in the buffer, and a token0 purchase at its spot floor.
        amountIn = bound(
            amountIn,
            uint256(1).fullMulDivUp(spot * spot, 1 << 192),
            FixedPointMathLib.min(token0ToToken1(spot, Constants.MAX_FUZZED_AMOUNT), Constants.MAX_FUZZED_AMOUNT / 2)
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, 1 << 192, spot * spot),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(0, 2 * amountIn);
        uint256 buffer0Before = almCore.bufferAmount0();
        token0.mint(address(almCore), floor);
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.swap, (address(almCore), false, int256(amountIn), priceLimit(false), bytes(""))),
            abi.encode(-int256(floor), int256(amountIn))
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(false, amountIn, priceLimit(false), 0);

        // And: A max shortfall above the plan's loss at the trusted price.
        uint256 kept = amountIn + token0ToToken1(trustedSqrtPriceX96, floor);
        givenValidPlanLimits(
            configState,
            2 * amountIn > kept ? (2 * amountIn - kept).fullMulDivUp(ConfigLib.BPS_DENOMINATOR, 2 * amountIn) : 0,
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper swaps at the trusted price.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));

        // Then: The output arrived in the buffer.
        assertEq(almCore.bufferAmount0(), buffer0Before + floor);
    }

    function testFuzz_Success_swapViaPool_PartialFillAtItsFloor(
        PoolState memory poolState,
        uint256 amountIn,
        uint256 amountInUsed,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a max swap cost.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);

        // And: A token0 sale cut short by the limit, filled at its used input's floor.
        uint256 minAmountIn = uint256(1).fullMulDivUp(1 << 192, spot * spot);
        amountIn = bound(
            amountIn,
            minAmountIn + 1,
            FixedPointMathLib.min(token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT), Constants.MAX_FUZZED_AMOUNT)
        );
        amountInUsed = bound(amountInUsed, minAmountIn, amountIn - 1);
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountInUsed, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(amountIn, 0);
        uint256 buffer0Before = almCore.bufferAmount0();
        token1.mint(address(almCore), floor);
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.swap, (address(almCore), true, int256(amountIn), priceLimit(true), bytes(""))),
            abi.encode(int256(amountInUsed), -int256(floor))
        );
        Plan.Steps memory plan = Plan.init().swapViaPool(true, amountIn, priceLimit(true), 0);

        // And: A max shortfall above the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(1, (token0ToToken1(spot, amountInUsed) + 1).zeroFloorSub(floor)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper swaps.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(spot));

        // Then: Only the input used left the buffer.
        assertEq(almCore.bufferAmount0(), buffer0Before - amountInUsed);
    }

    function testFuzz_Success_swapViaPool_SpotFarFromTheTwapPasses(
        PoolState memory poolState,
        uint256 amountIn,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 twap = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: Spot pushed to the first spacing tick about a percent above the TWAP.
        uint160 spot;
        uint160 edge;
        {
            int24 tick = TickMath.getTickAtSqrtPrice(uint160(twap * 1008 / 1000));
            tick += (poolState.tickSpacing
                    - (tick % poolState.tickSpacing + poolState.tickSpacing)
                    % poolState.tickSpacing) % poolState.tickSpacing;
            spot = TickMath.getSqrtPriceAtTick(tick);
            edge = TickMath.getSqrtPriceAtTick(tick + poolState.tickSpacing);
            uint256 push = SqrtPriceMath.getAmount1Delta(sqrtPriceX96(pool), edge, pool.liquidity(), true)
                .fullMulDivUp(MAX_PIPS, MAX_PIPS - poolState.fee);
            token1.mint(users.unprivilegedAddress, push);
            swapAsActor(pool, users.unprivilegedAddress, address(token1), address(token0), push, spot);
        }

        // And: Spot and TWAP bands that hold a trusted price between the two.
        uint256 trusted = FixedPointMathLib.sqrt(twap * spot);
        {
            uint256 deviation = FixedPointMathLib.max(
                (spot - trusted).fullMulDivUp(1e18, trusted), (trusted - twap).fullMulDivUp(1e18, twap)
            ) + 1;
            setTrustedDeviation(deviation, deviation);
        }

        // And: A token0 purchase inside the spacing, past the price's rounding by a bps.
        amountIn = bound(
            amountIn,
            FixedPointMathLib.max(
                ConfigLib.BPS_DENOMINATOR.fullMulDivUp(uint256(spot) * spot, 1 << 192),
                (ConfigLib.BPS_DENOMINATOR * pool.liquidity()).fullMulDivUp(MAX_PIPS, (MAX_PIPS - poolState.fee) << 96)
            ),
            SqrtPriceMath.getAmount1Delta(spot, edge, pool.liquidity(), true) - 1
        );
        fundBuffer(0, amountIn);
        uint256 amountOut = swapStepOut(pool, amountIn, edge);

        // And: A max swap cost covering the pool's cost at spot, not at the trusted one.
        {
            uint256 value = amountIn.fullMulDiv(1 << 192, trusted * trusted);
            givenValidPlanLimits(configState, 0, 0);
            configState.maxSwapCostBps = uint16(
                bound(
                    configState.maxSwapCostBps,
                    ConfigLib.BPS_DENOMINATOR - amountOut * ConfigLib.BPS_DENOMINATOR
                        / amountIn.fullMulDiv(1 << 192, uint256(spot) * spot),
                    (value - amountOut).fullMulDivUp(ConfigLib.BPS_DENOMINATOR, value) - 1
                )
            );
        }

        // And: A max shortfall above the purchase's loss at the trusted price.
        {
            uint256 value = token0ToToken1(trusted, almCore.bufferAmount0()) + almCore.bufferAmount1();
            uint256 loss = (amountIn + 2).zeroFloorSub(token0ToToken1(trusted, amountOut));
            givenValidPlanLimits(
                configState,
                FixedPointMathLib.min(loss.fullMulDivUp(ConfigLib.BPS_DENOMINATOR, value), ConfigLib.BPS_DENOMINATOR),
                configState.maxSwapCostBps
            );
            setPlanLimits(configState);
        }

        // When: The keeper buys token0 at the trusted price.
        uint256 buffer0Before = almCore.bufferAmount0();
        {
            Plan.Steps memory plan = Plan.init().swapViaPool(false, amountIn, priceLimit(false), 0);
            vm.prank(users.keeper);
            almCore.execute(plan.commands, plan.inputs, uint160(trusted));
        }

        // Then: The pool's output arrived in the buffer.
        assertEq(almCore.bufferAmount0(), buffer0Before + amountOut);

        // And: It passed, where a floor at the trusted price would have reverted.
        assertLt(
            amountOut,
            amountIn.fullMulDiv(1 << 192, trusted * trusted)
                .fullMulDivUp(ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps, ConfigLib.BPS_DENOMINATOR)
        );
    }

    function testFuzz_Success_swapViaPool_RecordsTheSwapDelta(
        CoreState memory coreState,
        PoolState memory poolState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 sold,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, and token1 worth more than a wei of token0.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        fundShortfall(0, uint256(1).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192) + 1);

        // And: A token0 deposit worth less than the token1 buffer, and pending redeems.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit0 =
            bound(queueState.deposit0, 1, token1ToToken0(poolState.sqrtPrice, almCore.bufferAmount1() - 1));
        setQueueState(queueState);

        // And: A token0 sale worth up to a quarter amount, paying up to the top pool fee.
        sold = bound(
            sold,
            1,
            FixedPointMathLib.min(
                almCore.bufferAmount0() + queueState.deposit0,
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 4)
            )
        );
        uint256 swapped = token0ToToken1(poolState.sqrtPrice, sold);
        fee = bound(fee, 0, swapped.fullMulDiv(Constants.MAX_POOL_FEE, MAX_PIPS));
        uint256 depositSwap;
        uint256 valueUp;
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            valueUp = principal1 + almCore.bufferAmount1()
                + CLMath.convert(poolState.sqrtPrice, true, principal0 + almCore.bufferAmount0(), true) - fee;
            uint256 held0 =
                token0ToToken1(poolState.sqrtPrice, principal0 + almCore.bufferAmount0() + queueState.deposit0 - sold);
            uint256 held1 = principal1 + almCore.bufferAmount1() + swapped - fee;
            depositSwap = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
            depositSwap = depositSwap.fullMulDiv(held1, held0 + held1);
        }
        uint256 cost = CLMath.convert(poolState.sqrtPrice, true, sold, true) - (swapped - fee);
        uint256 supply = almCore.totalSupply();
        token1.mint(address(almCore), swapped - fee);
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.swap, (address(almCore), true, int256(sold), priceLimit(true), bytes(""))),
            abi.encode(int256(sold), -int256(swapped - fee))
        );

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 2, true, sold, swapped - fee);
        setPlanLimits(configState);

        // When: The keeper settles the deposit and swaps.
        runPlan(Plan.init().clearAllRequests(true, true).swapViaPool(true, sold, priceLimit(true), 0).settleRequests());

        // Then: The deposit pays the swap's cost and is minted at the value, rounded up.
        uint256 deposit = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        uint256 levy = swapped == 0 || depositSwap == 0
            ? 0
            : FixedPointMathLib.min(cost.fullMulDivUp(FixedPointMathLib.min(depositSwap, swapped), swapped), deposit);
        assertEq(almCore.depositEpoch(asyncVault0, 0).amountOut, (deposit - levy).fullMulDiv(supply, valueUp + levy));
    }
}
