/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { Plan } from "../../utils/Plan.sol";
import { ReentrancyGuardTransient } from "@solady/utils/ReentrancyGuardTransient.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the reentrancy guard of contract "ALMCore".
 */
// forge-lint: disable-next-item(boolean-cst, unsafe-typecast, unused-return)
contract Reentrancy_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_Reentrancy_StateChangingFunctions(
        PoolState memory poolState,
        uint256 seed,
        address account
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An externally callable state-changing function, and the core's lock held.
        Plan.Steps memory plan = Plan.init();
        bytes[] memory callDatas = new bytes[](15);
        callDatas[0] = abi.encodeCall(ALMCore.seed, (1, 1, 2 * almCore.DEAD_SHARES_(), account));
        callDatas[1] = abi.encodeCall(ALMCore.mint, (1, account));
        callDatas[2] = abi.encodeCall(ALMCore.skim, ());
        callDatas[3] = abi.encodeCall(ALMCore.claimEmissions, (account));
        callDatas[4] = abi.encodeCall(ALMCore.payProtocolFees, ());
        callDatas[5] = abi.encodeCall(ALMCore.execute, (plan.commands, plan.inputs, sqrtPriceX96(pool)));
        callDatas[6] = abi.encodeCall(ALMCore.burn, (1, account, account));
        callDatas[7] = abi.encodeCall(ALMCore.setProtocolFees, (0, 0, account));
        callDatas[8] = abi.encodeCall(ALMCore.recordDepositRequest, (account, 1));
        callDatas[9] = abi.encodeCall(ALMCore.recordRedeemRequest, (account, account, account, 1));
        callDatas[10] = abi.encodeCall(ALMCore.cancelDepositRequest, (1, account, account));
        callDatas[11] = abi.encodeCall(ALMCore.cancelRedeemRequest, (1, account, account));
        callDatas[12] = abi.encodeCall(ALMCore.claimDepositRequest, (account, 1, 1, account));
        callDatas[13] = abi.encodeCall(ALMCore.claimRedeemRequest, (account, 1, 1, account));
        callDatas[14] = abi.encodeCall(ALMCore.trustedBurn, (1, account, account, account));
        bytes memory callData = callDatas[bound(seed, 0, callDatas.length - 1)];
        almCore.lock_();

        // When: Calling it.
        // Then: It reverts before any other check.
        vm.expectRevert(ReentrancyGuardTransient.Reentrancy.selector);
        (bool success,) = address(almCore).call(callData);
        assertTrue(success);
    }

    function testFuzz_Revert_Reentrancy_SwapCallbackStaysOpenToThePool(
        PoolState memory poolState,
        int256 amount0Delta,
        int256 amount1Delta
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The core's lock held.
        almCore.lock_();

        // When: Calling the swap callback, which the pool did not send.
        // Then: It reverts on the caller, not on the guard.
        vm.expectRevert(ALMCore.OnlyPool.selector);
        almCore.uniswapV3SwapCallback(amount0Delta, amount1Delta, "");
    }

    function testFuzz_Success_Reentrancy_GuardWritesNoStorage(PoolState memory poolState, uint96 protocolFees) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A protocol fee owed on both pool tokens.
        protocolFees = uint96(bound(protocolFees, 1, type(uint96).max));
        fundBuffer(protocolFees, protocolFees);
        almCore.setBuffers(0, 0);
        almCore.setFeesOwed(protocolFees, protocolFees, 0);

        // When: Calling a guarded function.
        almCore.payProtocolFees();

        // Then: The guard left no sentinel behind.
        assertEq(vm.load(address(almCore), Constants.STORAGE_GUARD_SLOT), bytes32(0));
        assertEq(vm.load(address(almCore), Constants.FALLBACK_GUARD_SLOT), bytes32(0));
    }

    function testFuzz_Success_Reentrancy_ERC721ReceiverStaysOpen(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                1,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: Plan limits above the plan's rounding loss.
        givenValidPlanLimits(configState, leastShortfallBps(1, 0), 0);
        setPlanLimits(configState);

        // When: The manager unstakes, so the gauge hands the range back mid-call.
        runPlan(
            Plan.init()
                .unstake(
                    range.index,
                    almCore.getRange(range.index).stakedTokenId,
                    almCore.getRange(range.index).stakedLiquidity,
                    0,
                    0,
                    false
                )
        );

        // Then: The vault accepted the range back and holds no staked side.
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);
        assertEq(almCore.getRange(range.index).stakedLiquidity, 0);
    }

    function testFuzz_Success_Reentrancy_SwapCompletesThroughItsCallback(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 amountIn,
        bool zeroForOne,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        givenSpacingRoom(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        amountIn = spacingSwapIn(amountIn, zeroForOne);
        fundBuffer(amountIn, amountIn);

        uint256 bufferBefore = zeroForOne ? almCore.bufferAmount1() : almCore.bufferAmount0();
        uint256 poolBefore = (zeroForOne ? token1 : token0).balanceOf(address(pool));

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, zeroForOne, amountIn, poolSwapOut(zeroForOne, amountIn));
        setPlanLimits(configState);

        // When: The manager swaps against the pool, which re-enters through the callback.
        runPlan(Plan.init().swapViaPool(zeroForOne, amountIn, priceLimit(zeroForOne), 0));

        // Then: The guard admitted the callback, the pool's output landed in the buffer.
        uint256 amountOut = poolBefore - (zeroForOne ? token1 : token0).balanceOf(address(pool));
        assertEq(zeroForOne ? almCore.bufferAmount1() : almCore.bufferAmount0(), bufferBefore + amountOut);
    }

    function testFuzz_Success_Reentrancy_SwapMultiHopCompletes(
        PoolState memory poolState,
        uint256 amountIn,
        bool zeroForOne,
        ConfigState memory configState
    ) public {
        // Given: A pool with depth at the route's price.
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A two-pool route via a middle token, the input buffered, a wei kept.
        ERC20Mock token2 = new ERC20Mock("Token 2", "TKN2", 18);
        (ICLPool routePool0, ICLPool routePool1) =
            createRoute(address(token0), address(token2), address(token1), users.liquidityProvider);
        amountIn = bound(amountIn, MAX_PIPS / uint256(routePool0.fee()) + 1, ROUTE_LIQUIDITY);
        fundBuffer(zeroForOne ? amountIn : token1ToToken0(sqrtPriceX96(pool), 1) + 1, zeroForOne ? 0 : amountIn);
        address tokenIn = zeroForOne ? address(token0) : address(token1);

        // And: The output of the two route pools' swap steps for that input.
        uint256 amountOut;
        {
            bool firstZeroForOne = tokenIn < address(token2);
            bool secondZeroForOne = address(token2) < (zeroForOne ? address(token1) : address(token0));
            amountOut = swapStepOut(
                zeroForOne ? routePool1 : routePool0,
                swapStepOut(
                    zeroForOne ? routePool0 : routePool1,
                    amountIn,
                    TickMath.getSqrtPriceAtTick(firstZeroForOne ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
                ),
                TickMath.getSqrtPriceAtTick(secondZeroForOne ? ROUTE_TICK_LOWER : ROUTE_TICK_UPPER)
            );
        }
        uint256 bufferBefore = zeroForOne ? almCore.bufferAmount1() : almCore.bufferAmount0();

        // And: Plan limits above the swap's cost and the plan's loss.
        givenValidPlanLimits(configState, 1, zeroForOne, amountIn, amountOut);
        setPlanLimits(configState);

        // When: The manager swaps through the router over both pools.
        address tokenOut = zeroForOne ? address(token1) : address(token0);
        bytes memory route = routeCalldata(tokenIn, address(token2), tokenOut, amountIn, address(routerTrampoline));
        runPlan(Plan.init().swapViaRouter(address(SWAP_ROUTER), amountIn, zeroForOne, 0, route));

        // Then: The output of the second pool landed in the buffer.
        assertEq(zeroForOne ? almCore.bufferAmount1() : almCore.bufferAmount0(), bufferBefore + amountOut);
    }
}
