/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { BalanceRouterMock } from "../../utils/mocks/BalanceRouterMock.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { LockProbeRouterMock } from "../../utils/mocks/LockProbeRouterMock.sol";
import { Plan } from "../../utils/Plan.sol";
import { PlanCacheLib } from "../../../src/core/types/PlanCache.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the command "SWAP_VIA_ROUTER" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract SwapViaRouter_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_swapViaRouter_OnlyKeeper(
        address caller,
        uint256 amountIn,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

        // And: The caller is not a keeper.
        vm.assume(caller != users.keeper);
        bytes memory route =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, true, 0, route);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: Calling swapViaRouter().
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ALMKeeperExtension.OnlyKeeper.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaRouter_Paused(
        uint256 amountIn,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

        // And: The vault is paused.
        vm.prank(factory);
        almCore.pause();
        bytes memory route =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, true, 0, route);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls swapViaRouter().
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.Paused.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaRouter_InvalidPayload_OpenBalance(
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

        // And: A seeded vault with a range, and a router filling at spot.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        BalanceRouterMock router = new BalanceRouterMock();
        uint160 spot = sqrtPriceX96(pool);

        // And: An open buffer flag on a remainder above the bps denominator.
        bps = bound(bps, ConfigLib.BPS_DENOMINATOR + 1, Sentinels.OPEN_BALANCE - 1);
        Plan.Steps memory plan = Plan.init()
            .swapBalance(
                address(router),
                address(token0),
                address(token1),
                address(routerTrampoline),
                zeroForOne,
                Sentinels.OPEN_BALANCE | bps,
                spot,
                0
            );

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps via the router.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, spot);
    }

    function testFuzz_Revert_swapViaRouter_InvalidPayload_TargetRatio(
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

        // And: A seeded vault with a range, and a router filling at spot.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        BalanceRouterMock router = new BalanceRouterMock();
        uint160 spot = sqrtPriceX96(pool);

        // And: A target ratio flag on a remainder above the bps denominator.
        bps = bound(bps, ConfigLib.BPS_DENOMINATOR + 1, Sentinels.TO_TARGET_RATIO - 1);
        Plan.Steps memory plan = Plan.init()
            .swapBalance(
                address(router),
                address(token0),
                address(token1),
                address(routerTrampoline),
                zeroForOne,
                Sentinels.TO_TARGET_RATIO | bps,
                spot,
                0
            );

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps via the router.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, spot);
    }

    function testFuzz_Revert_swapViaRouter_InvalidPayload_BothSentinels(
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

        // And: A seeded vault with a range, and a router filling at spot.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        BalanceRouterMock router = new BalanceRouterMock();
        uint160 spot = sqrtPriceX96(pool);

        // And: Both sentinel flags on any remainder.
        bps = bound(bps, 0, Sentinels.TO_TARGET_RATIO - 1);
        Plan.Steps memory plan = Plan.init()
            .swapBalance(
                address(router),
                address(token0),
                address(token1),
                address(routerTrampoline),
                zeroForOne,
                Sentinels.OPEN_BALANCE | Sentinels.TO_TARGET_RATIO | bps,
                spot,
                0
            );

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps via the router.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(CalldataLogic.InvalidPayload.selector);
        almCore.execute(plan.commands, plan.inputs, spot);
    }

    function testFuzz_Revert_swapViaRouter_RouterRevertsWithItsDataAsReason(
        uint256 amountIn,
        bytes memory reason,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
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

        // And: A sale of token0 on a router that reverts with fuzzed data.
        amountIn = bound(amountIn, 0, almCore.bufferAmount0());
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token0), address(token1), amountIn, amountIn, address(routerTrampoline))
        );
        vm.mockCallRevert(address(router), data, reason);
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(router), amountIn, true, 0, data);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The keeper swaps via the router.
        // Then: It reverts with the router's revert data as the reason string.
        vm.prank(users.keeper);
        vm.expectRevert(abi.encodeWithSignature("Error(string)", string(reason)));
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaRouter_TooManySwaps(
        uint256 amountIn,
        bool firstInPool,
        bool withClose,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
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

        // And: Pending deposits and redeems.
        givenValidQueueState(queueState, 0, 0);
        setQueueState(queueState);

        // And: The buffer holds the first swap's input, inside the current tick spacing.
        amountIn = spacingSwapIn(amountIn, true);
        fundBuffer(amountIn, 0);

        // And: A plan, with or without a clear step, that swaps twice through a router.
        Plan.Steps memory plan = withClose ? Plan.init().clearAllRequests(false, true) : Plan.init();
        if (firstInPool) {
            plan = plan.swapViaPool(true, amountIn, priceLimit(true), 0);
        } else {
            uint256 amountOut = token0ToToken1(poolState.sqrtPrice, amountIn);
            plan = plan.swapAtRate(
                address(token0), address(token1), address(routerTrampoline), true, amountIn, amountOut
            );
        }
        plan = plan.settleRequests()
            .swapAtRate(address(token0), address(token1), address(routerTrampoline), true, amountIn, amountIn);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: A max swap cost the first swap fits.
        uint256 swapCostBps = firstInPool ? leastSwapCostBps(true, amountIn, poolSwapOut(true, amountIn)) : 0;
        givenValidPlanLimits(configState, 0, swapCostBps);
        setPlanLimits(configState);

        // When: The keeper runs the plan.
        // Then: It reverts on the second swap.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.TooManySwaps.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaRouter_MaxSwapCostExceeded_ZeroForOne(
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price, a max swap cost, a trusted price in the band.
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

        // And: A token0 sale worth a wei or more, filled a wei below its floor at spot.
        amountIn = bound(
            amountIn,
            FixedPointMathLib.fullMulDivUp(1, 1 << 192, spot * spot),
            FixedPointMathLib.min(Constants.MAX_FUZZED_AMOUNT, token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT))
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(amountIn, 0);
        Plan.Steps memory plan = Plan.init()
            .swapAtRate(address(token0), address(token1), address(routerTrampoline), true, amountIn, floor - 1);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.MaxSwapCostExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));
    }

    function testFuzz_Revert_swapViaRouter_MaxSwapCostExceeded_OneForZero(
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price, a max swap cost, a trusted price in the band.
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

        // And: A token0 purchase worth a wei or more, filled a wei below its floor.
        amountIn = bound(
            amountIn,
            FixedPointMathLib.fullMulDivUp(1, spot * spot, 1 << 192),
            FixedPointMathLib.min(Constants.MAX_FUZZED_AMOUNT, token0ToToken1(spot, Constants.MAX_FUZZED_AMOUNT))
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, 1 << 192, spot * spot),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(0, amountIn);
        Plan.Steps memory plan = Plan.init()
            .swapAtRate(address(token0), address(token1), address(routerTrampoline), false, amountIn, floor - 1);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.MaxSwapCostExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));
    }

    function testFuzz_Revert_swapViaRouter_MaxSwapCostExceeded_NetOfTheRefund(
        uint256 amountIn,
        uint256 amountInUsed,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a max swap cost.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);

        // And: A token0 sale the router takes part of, filled a wei below its floor.
        uint256 most =
            FixedPointMathLib.min(Constants.MAX_FUZZED_AMOUNT, token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT));
        amountInUsed = bound(amountInUsed, FixedPointMathLib.fullMulDivUp(1, 1 << 192, spot * spot), most - 1);
        amountIn = bound(amountIn, amountInUsed + 1, most);
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountInUsed, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(amountIn, 0);
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap,
            (address(token0), address(token1), amountInUsed, floor - 1, address(routerTrampoline))
        );
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(router), amountIn, true, 0, data);

        // When: The keeper swaps.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.MaxSwapCostExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, uint160(spot));
    }

    function testFuzz_Revert_swapViaRouter_InsufficientOutput(
        uint256 amountIn,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        (ICLPool routePool0, ICLPool routePool1) =
            createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

        // And: The buffer holds the input.
        amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
        fundBuffer(amountIn, 0);

        // And: The output of the two route pools' swap steps for that input.
        uint256 amountOut = swapStepOut(
            routePool1,
            swapStepOut(
                routePool0,
                amountIn,
                TickMath.getSqrtPriceAtTick(address(token0) < address(token2) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            ),
            TickMath.getSqrtPriceAtTick(address(token2) < address(token1) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
        );
        bytes memory route =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, true, amountOut + 1, route);
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // When: The manager calls swapViaRouter() demanding one wei more.
        // Then: It reverts.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InsufficientOutput.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Revert_swapViaRouter_InsufficientOutput_TighterAmountOutMinStillBinds(
        uint256 amountIn,
        uint256 margin,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a max swap cost.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);

        // And: A minimum output above the floor, a token0 sale filled a wei below it.
        amountIn = bound(
            amountIn,
            1,
            FixedPointMathLib.min(Constants.MAX_FUZZED_AMOUNT, token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT - 1))
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        uint256 minAmountOut = floor + bound(margin, 1, Constants.MAX_FUZZED_AMOUNT - floor);
        fundBuffer(amountIn, 0);
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap,
            (address(token0), address(token1), amountIn, minAmountOut - 1, address(routerTrampoline))
        );
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(router), amountIn, true, minAmountOut, data);

        // When: The keeper swaps.
        // Then: It reverts on the minimum output.
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InsufficientOutput.selector);
        almCore.execute(plan.commands, plan.inputs, uint160(spot));
    }

    function testFuzz_Success_swapViaRouter_OpenBalanceFilledAboveTheTrustedPricePaysTheValueBefore(
        uint256 trustedSqrtPriceX96,
        uint256 fee,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A router filling at spot less a fee, trusted at half its price at most.
        BalanceRouterMock router = new BalanceRouterMock();
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
            )
        );
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            FixedPointMathLib.fullMulDivUp(poolState.sqrtPrice, 1e18, 1e18 + Constants.WIDE_DEVIATION),
            FixedPointMathLib.sqrt(
                FullMath.mulDiv(poolState.sqrtPrice * poolState.sqrtPrice, MAX_PIPS - fee, 2 * MAX_PIPS)
            )
        );

        // And: A range, and token0 left whose gain on the fill outgrows a token0 unit.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 unit = token0ToToken1(trustedSqrtPriceX96, 1) + 3;
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 floor = FixedPointMathLib.max(
                FixedPointMathLib.max(
                    FixedPointMathLib.max(32 * unit, 4 * (almCore.DEAD_SHARES_() + 4)),
                    16 * (coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, amount0))
                        / Constants.MAX_FUZZED_AMOUNT + 17
                ),
                FixedPointMathLib.sqrt(
                    32 * unit * (coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, amount0) + 2)
                ) + 1
            );
            floor = token1ToToken0(trustedSqrtPriceX96, floor) + 2;
            {
                uint256 ceiling = FixedPointMathLib.max(
                    floor,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
                coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, ceiling);
            }

            // And: Four times the dead shares or more, a share an eighth of that token0.
            uint256 value = coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, coreState.buffer0) + 2;
            floor = FixedPointMathLib.max(
                4 * (almCore.DEAD_SHARES_() + 4),
                8 * value / token0ToToken1(trustedSqrtPriceX96, coreState.buffer0 - amount0 - 1) + 1
            );
            value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's value at the trusted price, the range at its principal.
        uint256 owed0;
        {
            uint256 buffer0 = almCore.bufferAmount0();
            uint256 value;
            {
                (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                    uint160(trustedSqrtPriceX96),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = principal1 + almCore.bufferAmount1() + token0ToToken1(trustedSqrtPriceX96, principal0 + buffer0);
            }

            // And: The least gain of a sale of half the token0 buffer or more.
            uint256 gain = token0ToToken1(poolState.sqrtPrice, buffer0 - buffer0 / 2);
            gain = gain - gain * fee / MAX_PIPS - token0ToToken1(trustedSqrtPriceX96, buffer0 - buffer0 / 2) - 4;

            // And: Deposits of half the vault each at most, token0's fill in an amount.
            givenValidQueueState(queueState, 0, 0);
            uint256 most = FixedPointMathLib.min(
                token1ToToken0(trustedSqrtPriceX96, value / 2),
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
            );
            queueState.deposit0 = bound(queueState.deposit0, 0, most);
            queueState.deposit1 = bound(queueState.deposit1, 0, value / 2);

            // And: A token0 redeem gaining over a token0 unit, half the buffer at most.
            most = token0ToToken1(trustedSqrtPriceX96, buffer0);
            most = FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(most, coreState.supply, 2 * value)
            );
            queueState.redeem0 =
                bound(queueState.redeem0, FullMath.mulDivRoundingUp(unit, coreState.supply, gain), most);
            setQueueState(queueState);
            owed0 = token1ToToken0(trustedSqrtPriceX96, FullMath.mulDiv(queueState.redeem0, value, coreState.supply));
        }
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(true, false);
        {
            uint256 routerFee = fee;
            uint256 sqrtPrice = poolState.sqrtPrice;
            plan = plan.swapBalance(
                    address(router),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and routes the whole open buffer of token0.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));

        // Then: The redeem is paid at the value before, the sale took all token0.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, owed0);
        assertEq(almCore.bufferAmount0(), 0);
    }

    function testFuzz_Success_swapViaRouter_TargetRatioFilledAboveTheTrustedPricePaysTheValueBefore(
        uint256 trustedSqrtPriceX96,
        uint256 fee,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A router filling at spot less a fee, trusted at half its price at most.
        BalanceRouterMock router = new BalanceRouterMock();
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
            )
        );
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            FixedPointMathLib.fullMulDivUp(poolState.sqrtPrice, 1e18, 1e18 + Constants.WIDE_DEVIATION),
            FixedPointMathLib.sqrt(
                FullMath.mulDiv(poolState.sqrtPrice * poolState.sqrtPrice, MAX_PIPS - fee, 2 * MAX_PIPS)
            )
        );

        // And: A range, and token0 left whose gain on the fill outgrows a token0 unit.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 unit = token0ToToken1(trustedSqrtPriceX96, 1) + 3;
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 floor = FixedPointMathLib.max(
                FixedPointMathLib.max(
                    FixedPointMathLib.max(32 * unit, 4 * (almCore.DEAD_SHARES_() + 4)),
                    16 * (coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, amount0))
                        / Constants.MAX_FUZZED_AMOUNT + 17
                ),
                FixedPointMathLib.sqrt(
                    32 * unit * (coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, amount0) + 2)
                ) + 1
            );
            floor = token1ToToken0(trustedSqrtPriceX96, floor) + 2;
            {
                uint256 ceiling = FixedPointMathLib.max(
                    floor,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
                coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, ceiling);
            }

            // And: Four times the dead shares or more, a share an eighth of that token0.
            uint256 value = coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, coreState.buffer0) + 2;
            floor = FixedPointMathLib.max(
                4 * (almCore.DEAD_SHARES_() + 4),
                8 * value / token0ToToken1(trustedSqrtPriceX96, coreState.buffer0 - amount0 - 1) + 1
            );
            value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's value at the trusted price, the range at its principal.
        uint256 owed0;
        {
            uint256 buffer0 = almCore.bufferAmount0();
            uint256 value;
            {
                (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                    uint160(trustedSqrtPriceX96),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = principal1 + almCore.bufferAmount1() + token0ToToken1(trustedSqrtPriceX96, principal0 + buffer0);
            }

            // And: The least gain of a sale of half the token0 buffer or more.
            uint256 gain = token0ToToken1(poolState.sqrtPrice, buffer0 - buffer0 / 2);
            gain = gain - gain * fee / MAX_PIPS - token0ToToken1(trustedSqrtPriceX96, buffer0 - buffer0 / 2) - 4;

            // And: Deposits of half the vault each at most, token0's fill in an amount.
            givenValidQueueState(queueState, 0, 0);
            uint256 most = FixedPointMathLib.min(
                token1ToToken0(trustedSqrtPriceX96, value / 2),
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
            );
            queueState.deposit0 = bound(queueState.deposit0, 0, most);
            queueState.deposit1 = bound(queueState.deposit1, 0, value / 2);

            // And: A token0 redeem gaining over a token0 unit, half the buffer at most.
            most = token0ToToken1(trustedSqrtPriceX96, buffer0);
            most = FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(most, coreState.supply, 2 * value)
            );
            queueState.redeem0 =
                bound(queueState.redeem0, FullMath.mulDivRoundingUp(unit, coreState.supply, gain), most);
            setQueueState(queueState);
            owed0 = token1ToToken0(trustedSqrtPriceX96, FullMath.mulDiv(queueState.redeem0, value, coreState.supply));
        }
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(true, false);
        {
            uint256 routerFee = fee;
            uint256 sqrtPrice = poolState.sqrtPrice;
            plan = plan.swapBalance(
                    address(router),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    Sentinels.TO_TARGET_RATIO,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and routes token0 to a zero target ratio.
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));

        // Then: The redeem is paid at the value before, the sale took all token0.
        assertEq(almCore.redeemEpoch(asyncVault0, 0).amountOut, owed0);
        assertEq(almCore.bufferAmount0(), 0);
    }

    function testFuzz_Revert_swapViaRouter_MaxShortfallExceeded_AfterASettlement(
        uint256 amountIn,
        uint256 fee,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        uint256 least = 2 * token0ToToken1(poolState.sqrtPrice, 1) + 12;

        // And: A range, and token0 left for twice a sale of twice that least.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 value;
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 floor = FixedPointMathLib.max(
                2 * token1ToToken0(poolState.sqrtPrice, 2 * least) + 3,
                token1ToToken0(
                    poolState.sqrtPrice,
                    8 * (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, amount0)) / Constants.MAX_FUZZED_AMOUNT
                        + 9
                ) + 2
            );
            {
                uint256 ceiling = FixedPointMathLib.max(
                    floor,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
                coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, ceiling);
            }

            // And: A supply over the dead shares, a share a quarter of that token0.
            value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            floor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                4 * value / token0ToToken1(poolState.sqrtPrice, coreState.buffer0 - amount0 - 1) + 1
            );
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's value at spot, the range at its principal.
        uint256 buffer0 = almCore.bufferAmount0();
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, principal0 + buffer0);
        }

        // And: Pending requests, a token0 redeem worth half the token0 buffer at most.
        givenValidQueueState(queueState, 0, 0);
        {
            uint256 bufferValue = token0ToToken1(poolState.sqrtPrice, buffer0);
            uint256 most = FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(bufferValue, coreState.supply, 2 * value)
            );
            queueState.redeem0 = bound(queueState.redeem0, 1, most);
        }
        setQueueState(queueState);

        // And: A sale of half the token0 buffer at most.
        amountIn = bound(amountIn, token1ToToken0(poolState.sqrtPrice, 2 * least) + 1, buffer0 / 2);
        uint256 amountOut = token0ToToken1(poolState.sqrtPrice, amountIn);

        // And: A max shortfall a loss of the least exceeds, a max swap cost it fits.
        givenValidPlanLimits(configState, 0, leastSwapCostBps(true, amountIn, amountOut - least));
        configState.maxShortfallBps = uint16(bound(configState.maxShortfallBps, 0, mostShortfallBps(least)));
        setPlanLimits(configState);

        // And: A fill losing the least or more at spot within the max swap cost.
        fee = bound(fee, least, maxSwapLoss(amountOut, configState.maxSwapCostBps));
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, false);
        {
            uint256 sold = amountIn;
            uint256 bought = amountOut - fee;
            plan = plan.swapAtRate(address(token0), address(token1), address(routerTrampoline), true, sold, bought)
                .settleRequests();
        }
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);

        // When: The keeper settles the redeem and routes the sale in the same plan.
        // Then: It reverts on the plan's loss bound.
        vm.prank(users.keeper);
        vm.expectRevert(PlanCacheLib.MaxShortfallExceeded.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function testFuzz_Success_swapViaRouter_ZeroForOne(
        uint256 amountIn,
        uint256 surplus1,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at the route's price.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        (ICLPool routePool0, ICLPool routePool1) =
            createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

        // And: The buffer holds the input and some token1 already.
        amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
        surplus1 = bound(surplus1, 0, Constants.MAX_FUZZED_AMOUNT);
        fundBuffer(amountIn, surplus1);
        bytes memory route =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, true, 0, route);
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: The output of the two route pools' swap steps for that input.
        uint256 amountOut = swapStepOut(
            routePool1,
            swapStepOut(
                routePool0,
                amountIn,
                TickMath.getSqrtPriceAtTick(address(token0) < address(token2) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            ),
            TickMath.getSqrtPriceAtTick(address(token2) < address(token1) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
        );

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, true, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager routes the whole input through the middle token.
        runPlan(plan);

        // Then: The input left the buffer and the route's output arrived in it.
        assertEq(almCore.bufferAmount0(), 0);
        assertEq(almCore.bufferAmount1(), buffer1Before + amountOut);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
        assertEq(token2.balanceOf(address(almCore)), 0);
    }

    function testFuzz_Success_swapViaRouter_OneForZero(
        uint256 amountIn,
        uint256 surplus0,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at the route's price.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        (ICLPool routePool0, ICLPool routePool1) =
            createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

        // And: The buffer holds the input and token0 worth at least a wei of token1.
        amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
        surplus0 = bound(surplus0, token1ToToken0(sqrtPriceX96(pool), 1) + 1, Constants.MAX_FUZZED_AMOUNT);
        fundBuffer(surplus0, amountIn);
        bytes memory route =
            routeCalldata(address(token1), address(token2), address(token0), amountIn, address(routerTrampoline));
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, false, 0, route);
        uint256 buffer0Before = almCore.bufferAmount0();

        // And: The output of the two route pools' swap steps for that input.
        uint256 amountOut = swapStepOut(
            routePool0,
            swapStepOut(
                routePool1,
                amountIn,
                TickMath.getSqrtPriceAtTick(address(token1) < address(token2) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            ),
            TickMath.getSqrtPriceAtTick(address(token2) < address(token0) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
        );

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, false, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager routes the whole input through the middle token.
        runPlan(plan);

        // Then: The input left the buffer and the route's output arrived in it.
        assertEq(almCore.bufferAmount1(), 0);
        assertEq(almCore.bufferAmount0(), buffer0Before + amountOut);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
    }

    function testFuzz_Success_swapViaRouter_MeetsAmountOutMin(
        uint256 amountIn,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at the route's price.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        (ICLPool routePool0, ICLPool routePool1) =
            createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

        // And: The buffer holds the input.
        amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
        fundBuffer(amountIn, 0);

        // And: The output of the two route pools' swap steps for that input.
        uint256 amountOut = swapStepOut(
            routePool1,
            swapStepOut(
                routePool0,
                amountIn,
                TickMath.getSqrtPriceAtTick(address(token0) < address(token2) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            ),
            TickMath.getSqrtPriceAtTick(address(token2) < address(token1) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
        );

        bytes memory route =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        Plan.Steps memory plan = Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, true, amountOut, route);
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, true, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager routes the input demanding exactly that.
        runPlan(plan);

        // Then: The output is credited.
        assertEq(almCore.bufferAmount1() - buffer1Before, amountOut);
    }

    function testFuzz_Success_swapViaRouter_TrampolineHoldsTokenOutIsCredited(
        uint256 amountIn,
        uint256 fee,
        uint256 donation,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, and a router filling at spot less a fee.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
            )
        );

        // And: A token0 sale filling an eighth of an amount, a trampoline holding token1.
        amountIn = bound(
            amountIn,
            0,
            FixedPointMathLib.min(buffer0, token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8))
        );
        donation = bound(donation, 1, Constants.MAX_FUZZED_AMOUNT / 8);
        token1.mint(address(routerTrampoline), donation);

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(1, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper routes the sale.
        {
            uint256 sold = amountIn;
            uint256 sqrtPrice = poolState.sqrtPrice;
            uint256 routerFee = fee;
            runPlan(
                Plan.init()
                    .swapBalance(
                        address(new BalanceRouterMock()),
                        address(token0),
                        address(token1),
                        address(routerTrampoline),
                        true,
                        sold,
                        sqrtPrice,
                        routerFee
                    )
            );
        }

        // Then: The input left, and the fill and the trampoline's token1 arrived.
        uint256 amountOut = token0ToToken1(poolState.sqrtPrice, amountIn);
        assertEq(almCore.bufferAmount0(), buffer0 - amountIn);
        assertEq(almCore.bufferAmount1(), buffer1 + amountOut - amountOut * fee / MAX_PIPS + donation);
        assertEq(token1.balanceOf(address(routerTrampoline)), 0);
    }

    function testFuzz_Success_swapViaRouter_LeavesNoAllowance(
        uint256 amountIn,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at the route's price.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        (ICLPool routePool0, ICLPool routePool1) =
            createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

        // And: The buffer holds the input.
        amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
        fundBuffer(amountIn, 0);

        // And: Plan limits above the route's cost and the plan's loss.
        uint256 amountOut = swapStepOut(
            routePool1,
            swapStepOut(
                routePool0,
                amountIn,
                TickMath.getSqrtPriceAtTick(address(token0) < address(token2) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            ),
            TickMath.getSqrtPriceAtTick(address(token2) < address(token1) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
        );
        givenValidPlanLimits(configState, 1, true, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager routes the whole input through the middle token.
        bytes memory route =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        runPlan(Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, true, 0, route));

        // Then: The router keeps no allowance on the vault.
        assertEq(token0.allowance(address(almCore), address(SWAP_ROUTER)), 0);
    }

    function testFuzz_Success_swapViaRouter_TrampolineHoldsTokenIn(
        uint256 amountIn,
        uint256 donation,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        uint256 amountOut;
        {
            (ICLPool routePool0, ICLPool routePool1) =
                createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

            // And: The buffer holds the input.
            amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
            fundBuffer(amountIn, 0);

            // And: The trampoline already holds more token0 than the swap's input.
            donation = bound(donation, amountIn + 1, Constants.MAX_FUZZED_AMOUNT);
            ERC20Mock(address(token0)).mint(address(routerTrampoline), donation);

            // And: The output of the two route pools' swap steps for that input.
            amountOut = swapStepOut(
                routePool1,
                swapStepOut(
                    routePool0,
                    amountIn,
                    TickMath.getSqrtPriceAtTick(address(token0) < address(token2) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
                ),
                TickMath.getSqrtPriceAtTick(address(token2) < address(token1) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            );
        }

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager routes the whole input through the middle token.
        bytes memory route =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        runPlan(Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, true, 0, route));

        // Then: The input left, the donation and the route's output arrived.
        assertEq(almCore.bufferAmount0(), donation);
        assertEq(almCore.bufferAmount1(), amountOut);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
        assertEq(token0.balanceOf(address(routerTrampoline)), 0);
    }

    function testFuzz_Success_swapViaRouter_OpenBalance(
        uint256 amountIn,
        uint256 surplus1,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at the route's price.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        (ICLPool routePool0, ICLPool routePool1) =
            createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

        // And: The buffer holds the input and some token1 already.
        amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
        surplus1 = bound(surplus1, 0, Constants.MAX_FUZZED_AMOUNT);
        fundBuffer(amountIn, surplus1);
        bytes memory route =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        Plan.Steps memory plan = Plan.init()
            .swapViaRouter(address(SWAP_ROUTER), Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR, true, 0, route);
        uint256 buffer1Before = almCore.bufferAmount1();

        // And: The output of the two route pools' swap steps for that input.
        uint256 amountOut = swapStepOut(
            routePool1,
            swapStepOut(
                routePool0,
                amountIn,
                TickMath.getSqrtPriceAtTick(address(token0) < address(token2) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            ),
            TickMath.getSqrtPriceAtTick(address(token2) < address(token1) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
        );

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, true, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager routes the token0 buffer through the middle token.
        runPlan(plan);

        // Then: The whole token0 buffer left, the route's output arrived.
        assertEq(almCore.bufferAmount0(), 0);
        assertEq(almCore.bufferAmount1(), buffer1Before + amountOut);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1());
        assertEq(token2.balanceOf(address(almCore)), 0);
    }

    function testFuzz_Success_swapViaRouter_OpenBalanceShare(
        bool zeroForOne,
        uint256 bps,
        uint256 fee,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and each token left filling an eighth of an amount at most.
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
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    amount1 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );

            // And: A supply from the dead shares only up to the vault's value.
            uint256 floor = almCore.DEAD_SHARES_();
            uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: A router filling at spot less a fee.
        BalanceRouterMock router = new BalanceRouterMock();
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
            )
        );

        // And: A share of the open buffer, and its fill at spot less the fee.
        bps = bound(bps, 1, ConfigLib.BPS_DENOMINATOR);
        Plan.Steps memory plan = Plan.init()
            .swapBalance(
                address(router),
                address(token0),
                address(token1),
                address(routerTrampoline),
                zeroForOne,
                Sentinels.OPEN_BALANCE | bps,
                poolState.sqrtPrice,
                fee
            );
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint256 sold = (zeroForOne ? buffer0 : buffer1) * bps / ConfigLib.BPS_DENOMINATOR;
        uint256 amountOut =
            zeroForOne ? token0ToToken1(poolState.sqrtPrice, sold) : token1ToToken0(poolState.sqrtPrice, sold);
        amountOut -= amountOut * fee / MAX_PIPS;
        (buffer0, buffer1) = zeroForOne ? (buffer0 - sold, buffer1 + amountOut) : (buffer0 + amountOut, buffer1 - sold);

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, zeroForOne, sold, amountOut);
        setPlanLimits(configState);

        // When: The keeper routes that share of the input token's open buffer.
        runPlan(plan);

        // Then: The router took that share of the input token's buffer.
        assertEq((zeroForOne ? token0 : token1).balanceOf(address(router)), sold);

        // And: The share left the buffer and its fill at spot less the fee arrived.
        assertEq(almCore.bufferAmount0(), buffer0);
        assertEq(almCore.bufferAmount1(), buffer1);
    }

    function testFuzz_Success_swapViaRouter_OpenBalanceAtZeroBpsSwapsNothing(
        bool zeroForOne,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, and a router filling at spot.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        BalanceRouterMock router = new BalanceRouterMock();

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper routes no share of the open buffer.
        Plan.Steps memory plan = Plan.init()
            .swapBalance(
                address(router),
                address(token0),
                address(token1),
                address(routerTrampoline),
                zeroForOne,
                Sentinels.OPEN_BALANCE,
                poolState.sqrtPrice,
                0
            );
        runPlan(plan);

        // Then: Nothing is swapped.
        assertEq((zeroForOne ? token0 : token1).balanceOf(address(router)), 0);
        assertEq(almCore.bufferAmount0(), buffer0);
        assertEq(almCore.bufferAmount1(), buffer1);
    }

    function testFuzz_Success_swapViaRouter_OpenBalanceLeavesThePayouts(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and token0 left worth nine wei up to an eighth of an amount.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 value;
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 floor = token1ToToken0(
                poolState.sqrtPrice,
                8 * (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, amount0)) / Constants.MAX_FUZZED_AMOUNT + 9
            ) + 2;
            {
                uint256 ceiling = FixedPointMathLib.max(
                    floor,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
                coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, ceiling);
            }

            // And: A supply over the dead shares, a share a quarter of that token0.
            value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            floor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                4 * value / token0ToToken1(poolState.sqrtPrice, coreState.buffer0 - amount0 - 1) + 1
            );
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's value at spot, the range at its principal.
        uint256 buffer0 = almCore.bufferAmount0();
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = principal1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, principal0 + buffer0);
        }

        // And: Pending deposits, the token1 one worth half the vault at most.
        givenValidQueueState(queueState, 0, 0);
        queueState.deposit1 = bound(queueState.deposit1, 0, value / 2);

        // And: A token0 redeem the token0 buffer pays.
        {
            uint256 most = FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2,
                FullMath.mulDiv(token0ToToken1(poolState.sqrtPrice, buffer0), coreState.supply, value)
            );
            queueState.redeem0 = bound(queueState.redeem0, 1, most);
        }
        setQueueState(queueState);

        // And: A router filling at spot less a fee.
        BalanceRouterMock router = new BalanceRouterMock();
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
            )
        );

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(3, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears the token1 deposit and redeem, routing all open token0.
        {
            Plan.Steps memory plan = Plan.init().clearAllRequests(false, true).clearAllRequests(true, false);
            uint256 sqrtPrice = poolState.sqrtPrice;
            uint256 routerFee = fee;
            plan = plan.swapBalance(
                    address(router),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
            runPlan(plan);
        }

        // Then: The router took the token0 buffer less the token0 the redeem is owed.
        uint256 owed0 =
            token1ToToken0(poolState.sqrtPrice, FullMath.mulDiv(queueState.redeem0, value, coreState.supply));
        assertEq(token0.balanceOf(address(router)), buffer0 - owed0);

        // And: The redeem settles at the value after the fill, its payout in escrow.
        {
            uint256 sold = buffer0 - owed0;
            uint256 amountOut = token0ToToken1(poolState.sqrtPrice, sold);
            uint256 received = amountOut - amountOut * fee / MAX_PIPS;
            uint256 soldUp = sold.fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
            value = (value + received).zeroFloorSub(soldUp);
        }
        assertEq(
            almCore.redeemEpoch(asyncVault0, 0).amountOut,
            token1ToToken0(poolState.sqrtPrice, FullMath.mulDiv(queueState.redeem0, value, coreState.supply))
        );
        assertEq(almCore.getEscrowed0(), queueState.deposit0 + almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaRouter_OpenBalanceSlackLeavesThePayoutsAndTheLevy(
        uint256 fee,
        uint256 slack,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and token0 left worth four token0 units or more.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 floor = FixedPointMathLib.max(
                4 * token1ToToken0(poolState.sqrtPrice, 1) + 6,
                token1ToToken0(
                    poolState.sqrtPrice,
                    8 * (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, amount0)) / Constants.MAX_FUZZED_AMOUNT
                        + 9
                ) + 2
            );
            {
                uint256 ceiling = FixedPointMathLib.max(
                    floor,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
                coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, ceiling);
            }

            // And: A supply over the dead shares, a share a quarter of that token0.
            uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            floor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                4 * value / token0ToToken1(poolState.sqrtPrice, coreState.buffer0 - amount0 - 1) + 1
            );
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's holdings at spot, the range at its principal.
        uint256 open0;
        {
            uint256 buffer0 = almCore.bufferAmount0();
            uint256 value;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = amount1 + almCore.bufferAmount1() + token0ToToken1(poolState.sqrtPrice, amount0 + buffer0);
            }

            // And: Deposits of half the vault each at most, token0's fill in an amount.
            givenValidQueueState(queueState, 0, 0);
            queueState.deposit0 = bound(
                queueState.deposit0,
                0,
                token1ToToken0(poolState.sqrtPrice, FixedPointMathLib.min(value / 2, Constants.MAX_FUZZED_AMOUNT / 8))
            );
            queueState.deposit1 = bound(queueState.deposit1, 0, value / 2);

            // And: A token0 redeem of half the token0 buffer at most.
            uint256 bufferValue = token0ToToken1(poolState.sqrtPrice, buffer0);
            uint256 most = FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(bufferValue, coreState.supply, 2 * value)
            );
            queueState.redeem0 = bound(queueState.redeem0, 1, most);
            setQueueState(queueState);

            // And: The open token0, the buffer with the deposit less the payout.
            open0 = buffer0 + queueState.deposit0
                - token1ToToken0(poolState.sqrtPrice, FullMath.mulDiv(queueState.redeem0, value, coreState.supply));
        }

        // And: A router filling at spot less a fee.
        BalanceRouterMock router = new BalanceRouterMock();
        givenValidPlanLimits(configState, 0, 0);
        uint256 routerFee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
            )
        );

        // And: A slack leaving a wei of token1's payout in token0 or more.
        slack = bound(
            slack,
            FullMath.mulDivRoundingUp(token1ToToken0(poolState.sqrtPrice, 1) + 1, ConfigLib.BPS_DENOMINATOR, open0),
            ConfigLib.BPS_DENOMINATOR - 1
        );

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(5, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(routerFee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears the queues and routes the open token0 less the slack.
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(true, false);
        {
            uint256 amountIn = Sentinels.OPEN_BALANCE | (ConfigLib.BPS_DENOMINATOR - slack);
            uint256 sqrtPrice = poolState.sqrtPrice;
            plan = plan.swapBalance(
                    address(router),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    amountIn,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
        }
        runPlan(plan);

        // Then: The router took the open token0 less the slack.
        assertEq(
            token0.balanceOf(address(router)), open0 * (ConfigLib.BPS_DENOMINATOR - slack) / ConfigLib.BPS_DENOMINATOR
        );

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaRouter_OpenBalanceSlackCoversAFillAboveTheTrustedPrice(
        uint256 trustedSqrtPriceX96,
        uint256 fee,
        uint256 slack,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A fee, and a trusted price in the band below spot.
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
            )
        );
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            FixedPointMathLib.fullMulDivUp(poolState.sqrtPrice, 1e18, 1e18 + Constants.WIDE_DEVIATION),
            poolState.sqrtPrice
        );

        // And: A range, and token0 left worth eight times four wei or more.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 value;
        {
            (uint256 amount0,) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 floor = token1ToToken0(
                trustedSqrtPriceX96,
                8 * (coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, amount0)) / Constants.MAX_FUZZED_AMOUNT + 9
            ) + 2;
            floor = FixedPointMathLib.max(8 * token1ToToken0(trustedSqrtPriceX96, 4) + 30, floor);
            {
                uint256 ceiling = FixedPointMathLib.max(
                    floor,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
                coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, ceiling);
            }

            // And: A supply over the dead shares, a share a quarter of that token0.
            value = coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, coreState.buffer0) + 2;
            floor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                4 * value / token0ToToken1(trustedSqrtPriceX96, coreState.buffer0 - amount0 - 1) + 1
            );
            value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's holdings at the trusted price, the range at its principal.
        uint256 open0;
        {
            uint256 held0;
            uint256 held1;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(trustedSqrtPriceX96),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                (held0, held1) = (amount0 + almCore.bufferAmount0(), amount1 + almCore.bufferAmount1());
            }
            value = held1 + token0ToToken1(trustedSqrtPriceX96, held0);

            // And: Deposits of half the vault each at most, token0's fill in an amount.
            givenValidQueueState(queueState, 0, 0);
            uint256 most = FixedPointMathLib.min(
                token1ToToken0(trustedSqrtPriceX96, value / 2),
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
            );
            queueState.deposit0 = bound(queueState.deposit0, 0, most);
            queueState.deposit1 = bound(queueState.deposit1, 0, value / 2);

            // And: A token0 redeem of an eighth of the supply, half the buffer at most.
            most = FullMath.mulDiv(
                token0ToToken1(trustedSqrtPriceX96, almCore.bufferAmount0()), coreState.supply, 2 * value
            );
            most = FixedPointMathLib.min(
                FixedPointMathLib.min(almCore.balanceOf(users.steward) / 2, coreState.supply / 8), most
            );
            queueState.redeem0 = bound(queueState.redeem0, 1, most);
            setQueueState(queueState);

            // And: The open token0, the buffer with the deposit less the payout.
            value = held1 + token0ToToken1(trustedSqrtPriceX96, held0);
            open0 = almCore.bufferAmount0() + queueState.deposit0
                - token1ToToken0(trustedSqrtPriceX96, FullMath.mulDiv(queueState.redeem0, value, coreState.supply));
        }

        // And: A slack covering the redeem's share of the fill's gain.
        value = token0ToToken1(poolState.sqrtPrice, open0) - token0ToToken1(trustedSqrtPriceX96, open0) + 3;
        value = token1ToToken0(
            trustedSqrtPriceX96, FullMath.mulDivRoundingUp(value, queueState.redeem0, coreState.supply) + 1
        );
        slack = bound(
            slack, FullMath.mulDivRoundingUp(value + 1, ConfigLib.BPS_DENOMINATOR, open0), ConfigLib.BPS_DENOMINATOR - 1
        );

        // And: A router filling at spot less that fee.
        uint256 routerFee = fee;

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(5, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears and routes the open buffer of token0 less the slack.
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(true, false);
        {
            uint256 amountIn = Sentinels.OPEN_BALANCE | (ConfigLib.BPS_DENOMINATOR - slack);
            uint256 sqrtPrice = poolState.sqrtPrice;
            plan = plan.swapBalance(
                    address(new BalanceRouterMock()),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    amountIn,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
        }
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));

        // Then: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaRouter_TargetRatioNeedingNoSaleSwapsNothing(
        uint256 bps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and a seed leaving token1 in the buffer.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        (, uint256 amount1) = amountsRoundedUp(
            uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );
        coreState.buffer1 = amount1
            + bound(
                coreState.buffer1 - amount1,
                2,
                FixedPointMathLib.max(2, amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4)
            );
        setCoreState(coreState);
        setRangeState(range);
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        BalanceRouterMock router = new BalanceRouterMock();

        // And: A target share of token0 above its share of the buffer's value at spot.
        uint256 value0 = token0ToToken1(poolState.sqrtPrice, buffer0);
        bps = bound(
            bps,
            FullMath.mulDivRoundingUp(value0 + 1, ConfigLib.BPS_DENOMINATOR, value0 + buffer1),
            ConfigLib.BPS_DENOMINATOR
        );

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The keeper routes token0 to the target ratio.
        {
            uint256 ratio = Sentinels.TO_TARGET_RATIO | bps;
            uint256 sqrtPrice = poolState.sqrtPrice;
            runPlan(
                Plan.init()
                    .swapBalance(
                        address(router),
                        address(token0),
                        address(token1),
                        address(routerTrampoline),
                        true,
                        ratio,
                        sqrtPrice,
                        0
                    )
            );
        }

        // Then: Nothing is swapped.
        assertEq(token0.balanceOf(address(router)), 0);
        assertEq(almCore.bufferAmount0(), buffer0);
        assertEq(almCore.bufferAmount1(), buffer1);
    }

    function testFuzz_Success_swapViaRouter_TargetRatioWithoutAFeeSettlesExactly(
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

        // And: A range, and token0 left filling an eighth of an amount at most.
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
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );

            // And: Token1 left of nine wei up to an eighth of an amount.
            uint256 floor = 8 * (amount1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0) + 2)
                / Constants.MAX_FUZZED_AMOUNT + 10;
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    floor,
                    FixedPointMathLib.max(
                        floor,
                        FixedPointMathLib.min(
                            amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                            token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                        )
                    )
                );

            // And: A supply over the dead shares, a share a quarter of that token1.
            uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            floor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2, 4 * (value + 2) / (coreState.buffer1 - amount1 - 1) + 1
            );
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's holdings at spot, the range at its principal.
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        uint256 open;
        {
            uint256 value;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = amount1 + buffer1 + token0ToToken1(poolState.sqrtPrice, amount0 + buffer0);
            }

            // And: Deposits of half the vault each at most, token0's fill in an amount.
            givenValidQueueState(queueState, 0, 0);
            queueState.deposit0 = bound(
                queueState.deposit0,
                0,
                token1ToToken0(poolState.sqrtPrice, FixedPointMathLib.min(value / 2, Constants.MAX_FUZZED_AMOUNT / 8))
            );
            queueState.deposit1 = bound(queueState.deposit1, 0, value / 2);

            // And: A token1 redeem of half the token1 buffer at most.
            uint256 most = FixedPointMathLib.min(
                almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(buffer1, coreState.supply, 2 * value)
            );
            queueState.redeem1 = bound(queueState.redeem1, 1, most);
            setQueueState(queueState);

            // And: The buffers with the deposits, the open buffer less the payout.
            (buffer0, buffer1) = (buffer0 + queueState.deposit0, buffer1 + queueState.deposit1);
            open = (token0ToToken1(poolState.sqrtPrice, buffer0) + buffer1)
            .zeroFloorSub(FullMath.mulDiv(queueState.redeem1, value, coreState.supply));
        }

        // And: A router filling at spot without a fee.
        BalanceRouterMock router = new BalanceRouterMock();

        // And: A target share of token0 under half its share of the buffer.
        bps = bound(
            bps,
            0,
            token0ToToken1(poolState.sqrtPrice, buffer0) * ConfigLib.BPS_DENOMINATOR
                / (2 * (token0ToToken1(poolState.sqrtPrice, buffer0) + buffer1))
        );

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(5, 0), 0);
        setPlanLimits(configState);

        // When: The keeper clears the queues and routes token0 to the target ratio.
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(false, false);
        {
            uint256 ratio = Sentinels.TO_TARGET_RATIO | bps;
            uint256 sqrtPrice = poolState.sqrtPrice;
            plan = plan.swapBalance(
                    address(router),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    ratio,
                    sqrtPrice,
                    0
                )
                .settleRequests();
        }
        runPlan(plan);

        // Then: The router took the token0 above the target share of the open buffer.
        uint256 target0 = token1ToToken0(poolState.sqrtPrice, open * bps / ConfigLib.BPS_DENOMINATOR);
        assertEq(token0.balanceOf(address(router)), buffer0 - target0);

        // And: The token0 buffer is the target share, and the redeem settles.
        assertEq(almCore.bufferAmount0(), target0);
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);
    }

    function testFuzz_Success_swapViaRouter_TargetRatioPastTheExactSellsToken0AndSettles(
        uint256 bps,
        uint256 fee,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and token0 left filling an eighth of an amount at most.
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
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );

            // And: Token1 left of nine wei up to an eighth of an amount.
            uint256 floor = 8 * (amount1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0) + 2)
                / Constants.MAX_FUZZED_AMOUNT + 10;
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    floor,
                    FixedPointMathLib.max(
                        floor,
                        FixedPointMathLib.min(
                            amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                            token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                        )
                    )
                );

            // And: A supply over the dead shares, a share a quarter of that token1.
            uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            floor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2, 4 * (value + 2) / (coreState.buffer1 - amount1 - 1) + 1
            );
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's holdings at spot, the range at its principal.
        uint256 sold;
        {
            uint256 buffer0 = almCore.bufferAmount0();
            uint256 buffer1 = almCore.bufferAmount1();
            uint256 open;
            {
                uint256 value;
                {
                    (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                        uint160(poolState.sqrtPrice),
                        range.tickLower,
                        range.tickUpper,
                        range.liquidity + range.liquidityStaked
                    );
                    value = amount1 + buffer1 + token0ToToken1(poolState.sqrtPrice, amount0 + buffer0);
                }

                // And: Deposits of half the vault each, token0's fill in an amount.
                givenValidQueueState(queueState, 0, 0);
                queueState.deposit0 = bound(
                    queueState.deposit0,
                    0,
                    token1ToToken0(
                        poolState.sqrtPrice, FixedPointMathLib.min(value / 2, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
                queueState.deposit1 = bound(queueState.deposit1, 0, value / 2);

                // And: A token1 redeem of half the token1 buffer.
                {
                    uint256 most = FixedPointMathLib.min(
                        almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(buffer1, coreState.supply, 2 * value)
                    );
                    queueState.redeem1 = bound(queueState.redeem1, 1, most);
                }
                setQueueState(queueState);

                // And: The buffers with the deposits, the open buffer less the payout.
                (buffer0, buffer1) = (buffer0 + queueState.deposit0, buffer1 + queueState.deposit1);
                open = (token0ToToken1(poolState.sqrtPrice, buffer0) + buffer1)
                .zeroFloorSub(FullMath.mulDiv(queueState.redeem1, value, coreState.supply));
            }

            // And: A fee, and a token0 share twice it past the exact, under half.
            givenValidPlanLimits(configState, 0, 0);
            fee = bound(
                fee,
                0,
                FixedPointMathLib.min(
                    uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
                )
            );
            {
                uint256 value0 = token0ToToken1(poolState.sqrtPrice, buffer0);
                bps = bound(
                    bps,
                    0,
                    FixedPointMathLib.min(
                        ConfigLib.BPS_DENOMINATOR - 2
                            * FixedPointMathLib.divUp(fee, MAX_PIPS / ConfigLib.BPS_DENOMINATOR),
                        value0 * ConfigLib.BPS_DENOMINATOR / (2 * (value0 + buffer1))
                    )
                );
            }
            sold = buffer0 - token1ToToken0(poolState.sqrtPrice, open * bps / ConfigLib.BPS_DENOMINATOR);
        }

        // And: A router filling at spot less that fee.
        BalanceRouterMock router = new BalanceRouterMock();

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(5, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears the queues and routes token0 to the target ratio.
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(false, false);
        {
            uint256 ratio = Sentinels.TO_TARGET_RATIO | bps;
            uint256 sqrtPrice = poolState.sqrtPrice;
            uint256 routerFee = fee;
            plan = plan.swapBalance(
                    address(router),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    true,
                    ratio,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
        }
        runPlan(plan);

        // Then: The router took the token0 above the target share of the open buffer.
        assertEq(token0.balanceOf(address(router)), sold);

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);
    }

    function testFuzz_Success_swapViaRouter_TargetRatioPastTheExactBuysToken0AndSettles(
        uint256 bps,
        uint256 fee,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range, and token1 left filling an eighth of an amount at most.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            coreState.buffer1 = amount1
                + bound(
                    coreState.buffer1 - amount1,
                    amount1 > 0 ? 0 : 1,
                    FixedPointMathLib.min(
                        amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );

            // And: Token0 left worth nine wei up to an eighth of an amount.
            uint256 floor = token1ToToken0(
                poolState.sqrtPrice,
                8 * (coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, amount0)) / Constants.MAX_FUZZED_AMOUNT + 9
            ) + 2;
            {
                uint256 ceiling = FixedPointMathLib.max(
                    floor,
                    FixedPointMathLib.min(
                        amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                        token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    )
                );
                coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, ceiling);
            }

            // And: A supply over the dead shares, a share a quarter of that token0.
            uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            floor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                4 * value / token0ToToken1(poolState.sqrtPrice, coreState.buffer0 - amount0 - 1) + 1
            );
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's holdings at spot, the range at its principal.
        uint256 bought;
        {
            (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
            uint256 open;
            {
                uint256 value;
                {
                    (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                        uint160(poolState.sqrtPrice),
                        range.tickLower,
                        range.tickUpper,
                        range.liquidity + range.liquidityStaked
                    );
                    value = amount1 + buffer1 + token0ToToken1(poolState.sqrtPrice, amount0 + buffer0);
                }

                // And: Deposits of half the vault each at most, token1's in an amount.
                givenValidQueueState(queueState, 0, 0);
                queueState.deposit0 = bound(queueState.deposit0, 0, token1ToToken0(poolState.sqrtPrice, value / 2));
                {
                    uint256 most = FixedPointMathLib.min(
                        value / 2, token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                    );
                    queueState.deposit1 = bound(queueState.deposit1, 0, most);
                }

                // And: A token0 redeem of half the token0 buffer at most.
                {
                    uint256 bufferValue = token0ToToken1(poolState.sqrtPrice, buffer0);
                    uint256 most = FixedPointMathLib.min(
                        almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(bufferValue, coreState.supply, 2 * value)
                    );
                    queueState.redeem0 = bound(queueState.redeem0, 1, most);
                }
                setQueueState(queueState);

                // And: The buffers with the deposits, the open buffer less the payout.
                (buffer0, buffer1) = (buffer0 + queueState.deposit0, buffer1 + queueState.deposit1);
                uint256 paid = FullMath.mulDiv(queueState.redeem0, value, coreState.supply);
                paid = token0ToToken1(poolState.sqrtPrice, token1ToToken0(poolState.sqrtPrice, paid));
                open = (token0ToToken1(poolState.sqrtPrice, buffer0) + buffer1).zeroFloorSub(paid);
            }

            // And: A fee, and a token0 share twice it past the exact, over half.
            givenValidPlanLimits(configState, 0, 0);
            fee = bound(
                fee,
                0,
                FixedPointMathLib.min(
                    uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
                )
            );
            bps = bound(
                bps,
                FixedPointMathLib.max(
                    2 * FixedPointMathLib.divUp(fee, MAX_PIPS / ConfigLib.BPS_DENOMINATOR),
                    ConfigLib.BPS_DENOMINATOR - buffer1 * ConfigLib.BPS_DENOMINATOR
                        / (2 * (token0ToToken1(poolState.sqrtPrice, buffer0) + buffer1))
                ),
                ConfigLib.BPS_DENOMINATOR
            );
            bought = buffer1.zeroFloorSub(open - open * bps / ConfigLib.BPS_DENOMINATOR);
        }

        // And: A router filling at spot less that fee.
        BalanceRouterMock router = new BalanceRouterMock();

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(5, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper clears the queues and routes token1 to the target ratio.
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(true, false);
        {
            uint256 ratio = Sentinels.TO_TARGET_RATIO | bps;
            uint256 sqrtPrice = poolState.sqrtPrice;
            uint256 routerFee = fee;
            plan = plan.swapBalance(
                    address(router),
                    address(token0),
                    address(token1),
                    address(routerTrampoline),
                    false,
                    ratio,
                    sqrtPrice,
                    routerFee
                )
                .settleRequests();
        }
        runPlan(plan);

        // Then: The router took the token1 above the target share of the open buffer.
        assertEq(token1.balanceOf(address(router)), bought);

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaRouter_TargetRatioAtATrustedPriceSellsToTheTarget(
        uint256 bps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 trustedSqrtPriceX96,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A trusted price in the band.
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            FixedPointMathLib.fullMulDivUp(poolState.sqrtPrice, 1e18, 1e18 + Constants.WIDE_DEVIATION),
            FixedPointMathLib.fullMulDiv(poolState.sqrtPrice, 1e18 + Constants.WIDE_DEVIATION, 1e18)
        );

        // And: A range, and token0 left filling an eighth of an amount at most.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 most = FixedPointMathLib.min(
                amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                token1ToToken0(trustedSqrtPriceX96, Constants.MAX_FUZZED_AMOUNT / 8)
            );
            coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, amount0 > 0 ? 0 : 1, most);

            // And: Token1 left of eighteen wei up to an eighth of an amount.
            uint256 floor = 32 * (amount1 + token0ToToken1(trustedSqrtPriceX96, coreState.buffer0) + 2)
                / Constants.MAX_FUZZED_AMOUNT + 18;
            most = FixedPointMathLib.min(
                amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
            );
            coreState.buffer1 = amount1 + bound(coreState.buffer1 - amount1, floor, FixedPointMathLib.max(floor, most));

            // And: A supply over the dead shares, a share a quarter of that token1.
            value = coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, coreState.buffer0) + 2;
            floor = FixedPointMathLib.max(almCore.DEAD_SHARES_() + 2, 4 * value / (coreState.buffer1 - amount1 - 1) + 1);
            value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's holdings at the trusted price, the range at its principal.
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 target0;
        {
            uint256 buffer1 = almCore.bufferAmount1();
            (uint256 held0, uint256 held1) = amountsRoundedDown(
                uint160(trustedSqrtPriceX96), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            (held0, held1) = (held0 + buffer0, held1 + buffer1);
            value = held1 + token0ToToken1(trustedSqrtPriceX96, held0);

            // And: Deposits of half the vault each at most, token0's fill in an amount.
            givenValidQueueState(queueState, 0, 0);
            queueState.deposit0 = bound(
                queueState.deposit0,
                0,
                token1ToToken0(trustedSqrtPriceX96, FixedPointMathLib.min(value / 2, Constants.MAX_FUZZED_AMOUNT / 8))
            );
            queueState.deposit1 = bound(queueState.deposit1, 0, value / 2);

            // And: A token1 redeem of half the token1 buffer at most.
            {
                uint256 most = FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(buffer1, coreState.supply, 2 * value)
                );
                queueState.redeem1 = bound(queueState.redeem1, 1, most);
            }
            setQueueState(queueState);

            // And: The buffers with the deposits, the open buffer less the payout.
            (buffer0, buffer1) = (buffer0 + queueState.deposit0, buffer1 + queueState.deposit1);
            value = held1 + token0ToToken1(trustedSqrtPriceX96, held0);
            uint256 open = (token0ToToken1(trustedSqrtPriceX96, buffer0) + buffer1)
            .zeroFloorSub(FullMath.mulDiv(queueState.redeem1, value, coreState.supply));

            // And: A target share of token0 under half its share of the buffer.
            value = token0ToToken1(trustedSqrtPriceX96, buffer0);
            bps = bound(bps, 0, value * ConfigLib.BPS_DENOMINATOR / (2 * (value + buffer1)));
            target0 = open * bps / ConfigLib.BPS_DENOMINATOR;
        }

        // And: A router filling at the trusted price without a fee.
        BalanceRouterMock router = new BalanceRouterMock();

        // And: Plan limits above the swap's cost and the plan's loss.
        {
            uint256 sale = buffer0 - token1ToToken0(trustedSqrtPriceX96, target0);
            givenValidPlanLimits(configState, 5, true, sale, token0ToToken1(trustedSqrtPriceX96, sale));
        }
        setPlanLimits(configState);

        // When: The keeper clears the queues and routes token0 to the target ratio.
        uint256 ratio = Sentinels.TO_TARGET_RATIO | bps;
        Plan.Steps memory plan =
            Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(false, false);
        plan = plan.swapBalance(
                address(router),
                address(token0),
                address(token1),
                address(routerTrampoline),
                true,
                ratio,
                trustedSqrtPriceX96,
                0
            )
            .settleRequests();
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));

        // Then: The router took the token0 above the target's value.
        assertEq(token0.balanceOf(address(router)), buffer0 - token1ToToken0(trustedSqrtPriceX96, target0));

        // And: The token0 left is the target in token0.
        assertEq(almCore.bufferAmount0(), token1ToToken0(trustedSqrtPriceX96, target0));

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed1(), almCore.redeemEpoch(asyncVault1, 0).amountOut);
    }

    function testFuzz_Success_swapViaRouter_TargetRatioAtATrustedPriceBuysToTheTarget(
        uint256 bps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 trustedSqrtPriceX96,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A trusted price in the band.
        trustedSqrtPriceX96 = bound(
            trustedSqrtPriceX96,
            FixedPointMathLib.fullMulDivUp(poolState.sqrtPrice, 1e18, 1e18 + Constants.WIDE_DEVIATION),
            FixedPointMathLib.fullMulDiv(poolState.sqrtPrice, 1e18 + Constants.WIDE_DEVIATION, 1e18)
        );

        // And: A range, and token1 worth 32 token0 wei up to an eighth amount's fill.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 most = FixedPointMathLib.min(
                amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                token0ToToken1(trustedSqrtPriceX96, Constants.MAX_FUZZED_AMOUNT / 8)
            );
            {
                uint256 least1 = 32 * (uint256(1).fullMulDivUp(trustedSqrtPriceX96 * trustedSqrtPriceX96, 1 << 192) + 1);
                coreState.buffer1 =
                    amount1 + bound(coreState.buffer1 - amount1, least1, FixedPointMathLib.max(least1, most));
            }

            // And: Token0 left worth seventeen wei up to an eighth of an amount.
            uint256 floor = token1ToToken0(
                trustedSqrtPriceX96,
                32 * (coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, amount0)) / Constants.MAX_FUZZED_AMOUNT
                    + 17
            ) + 2;
            most = FixedPointMathLib.min(
                amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4,
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
            );
            coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, FixedPointMathLib.max(floor, most));

            // And: A supply over the dead shares, a share a quarter of that token0.
            uint256 value = coreState.buffer1 + token0ToToken1(trustedSqrtPriceX96, coreState.buffer0) + 2;
            floor = FixedPointMathLib.max(
                almCore.DEAD_SHARES_() + 2,
                4 * value / token0ToToken1(trustedSqrtPriceX96, coreState.buffer0 - amount0 - 1) + 1
            );
            value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's holdings at the trusted price, the range at its principal.
        uint256 buffer1 = almCore.bufferAmount1();
        uint256 target1;
        {
            uint256 buffer0 = almCore.bufferAmount0();
            (uint256 held0, uint256 value) = amountsRoundedDown(
                uint160(trustedSqrtPriceX96), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            held0 += buffer0;
            value += buffer1 + token0ToToken1(trustedSqrtPriceX96, held0);

            // And: Deposits of half the vault each at most, token1's in an amount.
            givenValidQueueState(queueState, 0, 0);
            queueState.deposit0 = bound(queueState.deposit0, 0, token1ToToken0(trustedSqrtPriceX96, value / 2));
            {
                uint256 most = FixedPointMathLib.min(
                    value / 2, token0ToToken1(trustedSqrtPriceX96, Constants.MAX_FUZZED_AMOUNT / 8)
                );
                queueState.deposit1 = bound(queueState.deposit1, 0, most);
            }

            // And: A token0 redeem of half the token0 buffer at most.
            {
                uint256 most = token0ToToken1(trustedSqrtPriceX96, buffer0);
                most = FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(most, coreState.supply, 2 * value)
                );
                queueState.redeem0 = bound(queueState.redeem0, 1, most);
            }
            setQueueState(queueState);

            // And: The buffers with the deposits, the open buffer less the payout.
            (buffer0, buffer1) = (buffer0 + queueState.deposit0, buffer1 + queueState.deposit1);
            uint256 paid = FullMath.mulDiv(queueState.redeem0, value, coreState.supply);
            paid = token0ToToken1(trustedSqrtPriceX96, token1ToToken0(trustedSqrtPriceX96, paid));
            uint256 open = (token0ToToken1(trustedSqrtPriceX96, buffer0) + buffer1).zeroFloorSub(paid);

            // And: A target share of token0 over half its share of the value.
            bps = bound(
                bps,
                ConfigLib.BPS_DENOMINATOR - buffer1 * ConfigLib.BPS_DENOMINATOR
                    / (2 * (token0ToToken1(trustedSqrtPriceX96, buffer0) + buffer1)),
                ConfigLib.BPS_DENOMINATOR
            );
            target1 = open - open * bps / ConfigLib.BPS_DENOMINATOR;
        }

        // And: A router filling at the trusted price without a fee.
        BalanceRouterMock router = new BalanceRouterMock();

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(
            configState, 5, false, buffer1 - target1, token1ToToken0(trustedSqrtPriceX96, buffer1 - target1)
        );
        setPlanLimits(configState);

        // When: The keeper clears the queues and routes token1 to the target ratio.
        uint256 ratio = Sentinels.TO_TARGET_RATIO | bps;
        Plan.Steps memory plan = Plan.init()
            .clearAllRequests(true, true)
            .clearAllRequests(false, true)
            .clearAllRequests(true, false)
            .swapBalance(
                address(router),
                address(token0),
                address(token1),
                address(routerTrampoline),
                false,
                ratio,
                trustedSqrtPriceX96,
                0
            )
            .settleRequests();
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, uint160(trustedSqrtPriceX96));

        // Then: The router took the token1 above the target, leaving the target.
        assertEq(token1.balanceOf(address(router)), buffer1 - target1);
        assertEq(almCore.bufferAmount1(), target1);

        // And: The redeem settles with its payout in escrow.
        assertEq(almCore.getEscrowed0(), almCore.redeemEpoch(asyncVault0, 0).amountOut);
    }

    function testFuzz_Success_swapViaRouter_CancelBeforeThePlanShrinksTheInput(
        uint256 bps,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range whose token1, if any, is the least token1 left or more.
        givenValidRangeState(range, poolState, false);
        {
            uint256 floor = token1ToToken0(
                poolState.sqrtPrice, 4 * (ConfigLib.BPS_DENOMINATOR + token0ToToken1(poolState.sqrtPrice, 1) + 7)
            ) + 2;
            uint256 amount0;
            uint256 amount1;
            {
                uint256 least = token0ToToken1(poolState.sqrtPrice, floor) + 2;
                {
                    uint256 lower = TickMath.getSqrtPriceAtTick(range.tickLower);
                    uint256 upper =
                        FixedPointMathLib.min(poolState.sqrtPrice, TickMath.getSqrtPriceAtTick(range.tickUpper));
                    uint256 liquidity = upper > lower ? FullMath.mulDiv(least - 1, 1 << 96, upper - lower) + 1 : 0;
                    uint256 most =
                        liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4;
                    // And: Room for that liquidity, a hole for narrow ranges below spot.
                    vm.assume(liquidity <= 2 * most);
                    range.liquidity = uint128(
                        bound(
                            range.liquidity,
                            FixedPointMathLib.max(Constants.MIN_FUZZED_LIQUIDITY, liquidity.zeroFloorSub(most)),
                            most
                        )
                    );
                    range.liquidityStaked =
                        uint128(bound(range.liquidityStaked, liquidity.zeroFloorSub(range.liquidity), most));
                }
                givenValidCoreState(coreState, poolState, range, 0, 0, 0);
                (amount0, amount1) = amountsRoundedUp(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );

                // And: Token1 worth the least token0 left, up to an eighth amount's fill.
                coreState.buffer1 = amount1
                    + bound(
                        coreState.buffer1 - amount1,
                        least,
                        FixedPointMathLib.min(
                            amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4,
                            token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                        )
                    );
            }

            // And: Token0 worth four bps denominators and a unit, under that token1.
            {
                uint256 most = (coreState.buffer1 - amount1 - 1)
                .fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) - 1;
                most = FixedPointMathLib.min(
                    most, FixedPointMathLib.max(floor, amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4)
                );
                most = FixedPointMathLib.min(
                    most,
                    FixedPointMathLib.max(floor, token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8))
                );
                coreState.buffer0 = amount0 + bound(coreState.buffer0 - amount0, floor, most);
            }

            // And: Twice the dead shares or more, a share a quarter of that token0.
            uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            floor = FixedPointMathLib.max(
                2 * (almCore.DEAD_SHARES_() + 2),
                4 * value / token0ToToken1(poolState.sqrtPrice, coreState.buffer0 - amount0 - 1) + 1
            );
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: The vault's holdings at spot, the range at its principal.
        (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        {
            uint256 value;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                value = amount1 + buffer1 + token0ToToken1(poolState.sqrtPrice, amount0 + buffer0);
            }

            // And: Deposits of half the vault each, token0's at most the token1 buffer.
            givenValidQueueState(queueState, 0, 0);
            queueState.deposit0 = bound(
                queueState.deposit0, 0, token1ToToken0(poolState.sqrtPrice, FixedPointMathLib.min(value / 2, buffer1))
            );
            {
                uint256 most = FixedPointMathLib.min(
                    value / 2, token0ToToken1(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
                );
                queueState.deposit1 = bound(queueState.deposit1, 0, most);
            }

            // And: A token0 redeem worth the bps denominator and a unit, half the buffer.
            {
                uint256 unit = token0ToToken1(poolState.sqrtPrice, 1) + 1;
                uint256 bufferValue = token0ToToken1(poolState.sqrtPrice, buffer0);
                uint256 most = FixedPointMathLib.min(
                    almCore.balanceOf(users.steward) / 2, FullMath.mulDiv(bufferValue, coreState.supply, 2 * value)
                );
                queueState.redeem0 = bound(
                    queueState.redeem0,
                    FullMath.mulDivRoundingUp(ConfigLib.BPS_DENOMINATOR + unit + 4, coreState.supply, value),
                    most
                );
            }
            setQueueState(queueState);

            // And: The buffers with the deposits.
            (buffer0, buffer1) = (buffer0 + queueState.deposit0, buffer1 + queueState.deposit1);

            // And: A token0 purchase to a share over half its own, short of the whole.
            uint256 buffer0Value = token0ToToken1(poolState.sqrtPrice, buffer0);
            bps = bound(
                bps,
                ConfigLib.BPS_DENOMINATOR - buffer1 * ConfigLib.BPS_DENOMINATOR / (2 * (buffer0Value + buffer1)),
                ConfigLib.BPS_DENOMINATOR - 1
            );
        }

        // And: A router filling at spot less a fee.
        BalanceRouterMock router = new BalanceRouterMock();
        givenValidPlanLimits(configState, 0, 0);
        fee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                uint256(configState.maxSwapCostBps) * (MAX_PIPS / ConfigLib.BPS_DENOMINATOR), Constants.MAX_POOL_FEE
            )
        );

        // And: A max shortfall above the fill's fee and the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(5, vaultValue(sqrtPriceX96(pool), true).fullMulDivUp(fee, MAX_PIPS)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The redeem is canceled before the plan runs.
        vm.prank(asyncVault0);
        almCore.cancelRedeemRequest(0, controller, controller);
        {
            Plan.Steps memory plan =
                Plan.init().clearAllRequests(true, true).clearAllRequests(false, true).clearAllRequests(true, false);
            {
                uint256 ratio = Sentinels.TO_TARGET_RATIO | bps;
                uint256 sqrtPrice = poolState.sqrtPrice;
                uint256 routerFee = fee;
                plan = plan.swapBalance(
                        address(router),
                        address(token0),
                        address(token1),
                        address(routerTrampoline),
                        false,
                        ratio,
                        sqrtPrice,
                        routerFee
                    )
                    .settleRequests();
            }
            runPlan(plan);
        }

        // Then: The purchase takes the token1 above the target of the whole buffer.
        uint256 open = token0ToToken1(poolState.sqrtPrice, buffer0) + buffer1;
        assertEq(token1.balanceOf(address(router)), buffer1.zeroFloorSub(open - open * bps / ConfigLib.BPS_DENOMINATOR));

        // And: Less than without the cancel, the payout off the open buffer.
        {
            (uint256 principal0, uint256 principal1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            principal1 = FullMath.mulDiv(
                queueState.redeem0,
                principal1 + buffer1 - queueState.deposit1
                    + token0ToToken1(poolState.sqrtPrice, principal0 + buffer0 - queueState.deposit0),
                coreState.supply
            );
            open = open.zeroFloorSub(
                token0ToToken1(poolState.sqrtPrice, token1ToToken0(poolState.sqrtPrice, principal1))
            );
        }
        assertLt(token1.balanceOf(address(router)), buffer1.zeroFloorSub(open - open * bps / ConfigLib.BPS_DENOMINATOR));
    }

    function testFuzz_Success_swapViaRouter_AtTheFloor_ZeroForOne(
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price, a max swap cost, a trusted price in the band.
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

        // And: A token0 sale the router fills at its floor at spot.
        amountIn = bound(
            amountIn,
            FixedPointMathLib.fullMulDivUp(1, 1 << 192, spot * spot),
            FixedPointMathLib.min(Constants.MAX_FUZZED_AMOUNT, token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT))
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(amountIn, 0);
        uint256 buffer1Before = almCore.bufferAmount1();
        Plan.Steps memory plan =
            Plan.init().swapAtRate(address(token0), address(token1), address(routerTrampoline), true, amountIn, floor);

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

    function testFuzz_Success_swapViaRouter_AtTheFloor_OneForZero(
        uint256 amountIn,
        uint256 trustedSqrtPriceX96,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool at a fuzzed price, a max swap cost, a trusted price in the band.
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

        // And: A buffer of twice the input, a token0 purchase filled at its floor.
        amountIn = bound(
            amountIn,
            FixedPointMathLib.fullMulDivUp(1, spot * spot, 1 << 192),
            FixedPointMathLib.min(Constants.MAX_FUZZED_AMOUNT / 2, token0ToToken1(spot, Constants.MAX_FUZZED_AMOUNT))
        );
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountIn, 1 << 192, spot * spot),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(0, 2 * amountIn);
        uint256 buffer0Before = almCore.bufferAmount0();
        Plan.Steps memory plan =
            Plan.init().swapAtRate(address(token0), address(token1), address(routerTrampoline), false, amountIn, floor);

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

    function testFuzz_Success_swapViaRouter_NetOfTheRefundAtItsFloor(
        uint256 amountIn,
        uint256 amountInUsed,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a max swap cost.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);
        uint256 spot = sqrtPriceX96(pool);

        // And: A token0 sale the router takes part of, filled at that part's floor.
        {
            uint256 most =
                FixedPointMathLib.min(Constants.MAX_FUZZED_AMOUNT, token1ToToken0(spot, Constants.MAX_FUZZED_AMOUNT));
            amountInUsed = bound(amountInUsed, FixedPointMathLib.fullMulDivUp(1, 1 << 192, spot * spot), most - 1);
            amountIn = bound(amountIn, amountInUsed + 1, most);
        }
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            FullMath.mulDiv(amountInUsed, spot * spot, 1 << 192),
            ConfigLib.BPS_DENOMINATOR - configState.maxSwapCostBps,
            ConfigLib.BPS_DENOMINATOR
        );
        fundBuffer(amountIn, 0);
        uint256 buffer0Before = almCore.bufferAmount0();
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token0), address(token1), amountInUsed, floor, address(routerTrampoline))
        );

        // And: A max shortfall above the plan's loss.
        givenValidPlanLimits(
            configState,
            leastShortfallBps(1, (token0ToToken1(spot, amountInUsed) + 1).zeroFloorSub(floor)),
            configState.maxSwapCostBps
        );
        setPlanLimits(configState);

        // When: The keeper swaps.
        runPlan(Plan.init().swapViaRouter(address(router), amountIn, true, 0, data));

        // Then: Only the part the router took left the buffer.
        assertEq(almCore.bufferAmount0(), buffer0Before - amountInUsed);
    }

    function testFuzz_Success_swapViaRouter_RefundAboveTheInputHasNoFloor(
        uint256 amountIn,
        uint256 extra,
        PoolState memory poolState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price, and a max swap cost.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidPlanLimits(configState, 0, 0);
        setPlanLimits(configState);

        // And: A buffer worth a wei, a trampoline holding token0, a router doing nothing.
        uint256 spot = sqrtPriceX96(pool);
        amountIn =
            bound(amountIn, FixedPointMathLib.fullMulDivUp(1, 1 << 192, spot * spot), Constants.MAX_FUZZED_AMOUNT - 1);
        extra = bound(extra, 1, Constants.MAX_FUZZED_AMOUNT - amountIn);
        token0.mint(address(routerTrampoline), extra);
        fundBuffer(amountIn, 0);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        LockProbeRouterMock router = new LockProbeRouterMock();
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token0), address(token1), 0, 0, address(routerTrampoline))
        );

        // And: A max shortfall above the plan's loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), configState.maxSwapCostBps);
        setPlanLimits(configState);

        // When: The keeper swaps.
        runPlan(Plan.init().swapViaRouter(address(router), amountIn, true, 0, data));

        // Then: The swap used no input and has no floor, the trampoline's token0 arrived.
        assertEq(almCore.bufferAmount0(), buffer0Before + extra);
        assertEq(almCore.bufferAmount1(), buffer1Before);
    }

    function testFuzz_Success_swapViaRouter_RecordsTheNetOfTheRefund(
        uint256 amountIn,
        uint256 sold,
        uint256 fee,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 3);
        setCoreState(coreState);
        setRangeState(range);

        // And: Pending requests, a token0 deposit among them.
        givenValidQueueState(queueState, 1, 0);
        setQueueState(queueState);

        // And: The vault's holdings at spot after the clear, the range at its principal.
        uint256 held0;
        uint256 held1;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            (held0, held1) =
            (amount0 + almCore.bufferAmount0() + queueState.deposit0, amount1 + almCore.bufferAmount1());
        }

        // And: Plan limits storage holds.
        givenValidPlanLimits(configState, 0, 0);

        // And: A sale of part of a larger input, losing under the value and the cost.
        sold = bound(
            sold,
            1,
            FixedPointMathLib.min(
                almCore.bufferAmount0() + queueState.deposit0,
                token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT / 8)
            )
        );
        amountIn = bound(amountIn, sold, almCore.bufferAmount0() + queueState.deposit0);
        uint256 amountOut = token0ToToken1(poolState.sqrtPrice, sold);
        fee = bound(
            fee,
            0,
            FixedPointMathLib.min(
                maxSwapLoss(amountOut, configState.maxSwapCostBps),
                (held1 + token0ToToken1(poolState.sqrtPrice, held0 - queueState.deposit0)).zeroFloorSub(2)
            )
        );
        amountOut -= fee;
        Plan.Steps memory plan;
        {
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap, (address(token0), address(token1), sold, amountOut, address(routerTrampoline))
            );
            plan = Plan.init()
                .clearAllRequests(true, true)
                .swapViaRouter(address(new LockProbeRouterMock()), amountIn, true, 0, data)
                .settleRequests();
        }

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, leastShortfallBps(2, fee), leastSwapCostBps(true, sold, amountOut));
        setPlanLimits(configState);

        // And: The deposit's levy, the swap's cost on its part of the sold token0.
        (held0, held1) = (held0 - sold, held1 + amountOut);
        uint256 amountSold = sold;
        uint256 swapped = token0ToToken1(poolState.sqrtPrice, amountSold);
        uint256 valueUp =
            held1 + CLMath.convert(poolState.sqrtPrice, true, held0 + amountSold - queueState.deposit0, true) - swapped;
        uint256 value = held1 + token0ToToken1(poolState.sqrtPrice, held0);
        uint256 cost = CLMath.convert(poolState.sqrtPrice, true, amountSold, true) - amountOut;
        uint256 depositValue = token0ToToken1(poolState.sqrtPrice, queueState.deposit0);
        uint256 levy;
        uint256 depositSwap = FullMath.mulDiv(depositValue, held1, value);
        if (swapped != 0 && depositSwap != 0) {
            levy = FixedPointMathLib.min(
                FixedPointMathLib.fullMulDivUp(cost, FixedPointMathLib.min(depositSwap, swapped), swapped), depositValue
            );
        }
        uint256 supply = almCore.totalSupply();

        // When: The keeper settles the deposit and swaps.
        runPlan(plan);

        // Then: The deposit pays the cost of the input taken, net of the refund.
        assertEq(
            almCore.depositEpoch(asyncVault0, 0).amountOut, FullMath.mulDiv(depositValue - levy, supply, valueUp + levy)
        );
    }

    function testFuzz_Success_swapViaRouter_MultiPoolPathIsOneSwap(
        uint256 amountIn,
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at the route's price.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range, an aLP a sixteenth of an amount at most.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            uint256 floor =
                FixedPointMathLib.max(almCore.DEAD_SHARES_(), value / (Constants.MAX_FUZZED_AMOUNT / 16) + 1);
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(floor, FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT))
            );
            setCoreState(coreState);
        }
        setRangeState(range);

        // And: A route through a middle token.
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        uint256 amountOut;
        {
            (ICLPool routePool0, ICLPool routePool1) =
                createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);

            // And: The buffer holds the input, and the route's swap steps' output for it.
            amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
            fundBuffer(amountIn, 0);
            amountOut = swapStepOut(
                routePool1,
                swapStepOut(
                    routePool0,
                    amountIn,
                    TickMath.getSqrtPriceAtTick(address(token0) < address(token2) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
                ),
                TickMath.getSqrtPriceAtTick(address(token2) < address(token1) ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            );
        }

        // And: Pending requests, a token1 deposit worth an aLP after the swap.
        uint256 valueAfter;
        {
            (uint256 held0, uint256 held1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            valueAfter = held1 + almCore.bufferAmount1() + amountOut
                + token0ToToken1(poolState.sqrtPrice, held0 + almCore.bufferAmount0() - amountIn);
            givenValidQueueState(queueState, 0, valueAfter / almCore.totalSupply() + 1);
            setQueueState(queueState);
        }
        uint256 buffer1Before = almCore.bufferAmount1();
        uint256 supply = almCore.totalSupply();

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 2, true, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The keeper settles the deposit and routes token0 through both pools.
        bytes memory data =
            routeCalldata(address(token0), address(token2), address(token1), amountIn, address(routerTrampoline));
        runPlan(
            Plan.init()
                .clearAllRequests(false, true)
                .swapViaRouter(address(SWAP_ROUTER), amountIn, true, 0, data)
                .settleRequests()
        );

        // Then: The route was the plan's one swap, the deposit minted at that value.
        assertEq(almCore.depositEpoch(asyncVault1, 0).amountOut, queueState.deposit1.fullMulDiv(supply, valueAfter));
        assertEq(almCore.bufferAmount1(), buffer1Before + queueState.deposit1 + amountOut);
    }
}
