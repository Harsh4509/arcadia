/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { LockProbeRouterMock } from "../../utils/mocks/LockProbeRouterMock.sol";
import { Plan } from "../../utils/Plan.sol";

/**
 * @notice End-to-end fuzz tests of contract "ALMVaultAsync": request, settle and claim, in and back out.
 */
contract RoundTrip_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_roundTrip_NeverReturnsMoreThanWasPaid(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        bool isToken0
    ) public {
        // Given: A seeded core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);

        // And: An account requested a deposit, the keeper settled it, it claimed shares.
        uint256 assets = setDepositSettled(poolState, range, queueState, isToken0, users.unprivilegedAddress);
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress);

        // And: Those shares claim at least a wei, so their redeem is not dust.
        uint256 value;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            value = amount1 + almCore.bufferAmount1()
                + token0ToToken1(poolState.sqrtPrice, amount0 + almCore.bufferAmount0());
        }
        uint256 supply = almCore.totalSupply();
        uint256 owed = shares.fullMulDiv(value, supply);
        if (isToken0) owed = token1ToToken0(poolState.sqrtPrice, owed);
        // And: Where those shares are worth under a wei, a hole no bound expresses.
        vm.assume(owed > 0);

        // When: It redeems all of them, the keeper settles it, and it claims the asset.
        vm.startPrank(users.unprivilegedAddress);
        almCore.approve(address(vault), shares);
        vault.requestRedeem(shares, users.unprivilegedAddress, users.unprivilegedAddress);
        vm.stopPrank();
        settleRedeem(isToken0);
        vm.prank(users.unprivilegedAddress);
        uint256 returned = vault.redeem(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: The account holds no shares, and got back its shares' value.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
        assertEq((isToken0 ? token0 : token1).balanceOf(users.unprivilegedAddress), returned);
        assertEq(returned, owed);
        assertLe(returned, assets);

        // And: It lost at most a share, a wei of token1 per conversion, a wei of asset.
        uint256 oneShare = value / supply;
        if (isToken0) oneShare = token1ToToken0(poolState.sqrtPrice, oneShare);
        uint256 token1Wei = isToken0 ? token1ToToken0(poolState.sqrtPrice, 1) + 1 : 0;
        assertGe(returned + oneShare + 1 + 2 * token1Wei + 1, assets);
    }

    function testFuzz_Success_roundTrip_ClaimsTheSettledOutputs(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        QueueState memory queueState,
        uint256 shares,
        uint256 mode,
        uint256 amountIn,
        uint256 fee,
        ConfigState memory configState
    ) public {
        // Given: A seeded core, with token1 left in its buffer when the plan buys token0.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        mode = bound(mode, 0, 2);
        givenValidCoreState(coreState, poolState, range, 0, 0, mode == 2 ? 2 : 0);
        setSeededState(coreState, range);

        // And: A token0 deposit requested through its vault.
        givenValidQueueState(queueState, 1, 0);
        requestDepositFor(true, users.unprivilegedAddress, queueState.deposit0);

        // And: A plan settling it and a token1 redeem, with no swap, a sale or a buy.
        Plan.Steps memory plan = Plan.init().clearAllRequests(true, true).clearAllRequests(false, false);
        if (mode == 1) {
            amountIn = bound(
                amountIn,
                1,
                FixedPointMathLib.min(
                    almCore.bufferAmount0() + queueState.deposit0,
                    token1ToToken0(poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1())
                )
            );
            uint256 amountOut = token0ToToken1(poolState.sqrtPrice, amountIn);
            fee = bound(fee, 0, amountOut - amountOut.divUp(ConfigLib.BPS_DENOMINATOR));
            LockProbeRouterMock router = new LockProbeRouterMock();
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap,
                (address(token0), address(token1), amountIn, amountOut - fee, address(routerTrampoline))
            );
            plan = plan.swapViaRouter(address(router), amountIn, true, 0, data);
            givenValidPlanLimits(configState, 3, true, amountIn, amountOut - fee);
        } else if (mode == 2) {
            amountIn = bound(
                amountIn,
                1,
                FixedPointMathLib.min(
                    almCore.bufferAmount1(),
                    token0ToToken1(
                        poolState.sqrtPrice, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount0() - queueState.deposit0
                    )
                )
            );
            uint256 amountOut = token1ToToken0(poolState.sqrtPrice, amountIn);
            fee = bound(fee, 0, amountOut - amountOut.divUp(ConfigLib.BPS_DENOMINATOR));
            LockProbeRouterMock router = new LockProbeRouterMock();
            bytes memory data = abi.encodeCall(
                LockProbeRouterMock.swap,
                (address(token1), address(token0), amountIn, amountOut - fee, address(routerTrampoline))
            );
            plan = plan.swapViaRouter(address(router), amountIn, false, 0, data);
            givenValidPlanLimits(configState, 3, false, amountIn, amountOut - fee);
        } else {
            givenValidPlanLimits(configState, leastShortfallBps(2, 0), 0);
        }
        setPlanLimits(configState);

        // And: A token1 redeem the token1 buffer pays, the holders left worth a wei.
        {
            uint256 value;
            {
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(poolState.sqrtPrice),
                    range.tickLower,
                    range.tickUpper,
                    range.liquidity + range.liquidityStaked
                );
                amount0 += almCore.bufferAmount0();
                amount1 += almCore.bufferAmount1();
                value = amount1 + token0ToToken1(poolState.sqrtPrice, amount0) + 2
                    * token0ToToken1(poolState.sqrtPrice, queueState.deposit0) + 2;
                amount0 += queueState.deposit0;
                if (mode == 1) {
                    amount1 += token0ToToken1(poolState.sqrtPrice, amountIn) - fee;
                    amount0 -= amountIn;
                } else if (mode == 2) {
                    amount0 += token1ToToken0(poolState.sqrtPrice, amountIn) - fee;
                    amount1 -= amountIn;
                }
                amount1 += token0ToToken1(poolState.sqrtPrice, amount0);
                // And: Where the holders are worth under the deposit, a hole.
                vm.assume(amount1 > token0ToToken1(poolState.sqrtPrice, queueState.deposit0));
            }
            uint256 ceiling = almCore.bufferAmount1() - (mode == 2 ? amountIn : 0);
            ceiling = ceiling.fullMulDiv(almCore.totalSupply(), value);
            // And: Where the buffer pays under a share, a hole no bound expresses.
            vm.assume(ceiling != 0);
            shares = bound(shares, 1, ceiling);
        }
        requestRedeemFor(false, accountB, shares);

        // When: The keeper runs the plan and both claim through the vaults.
        runPlan(plan.settleRequests());
        uint256 settledShares = almCore.depositEpoch(address(asyncVault), 0).amountOut;
        uint256 settledAssets = almCore.redeemEpoch(address(secondAsyncVault), 0).amountOut;
        vm.prank(users.unprivilegedAddress);
        uint256 claimed = asyncVault.deposit(queueState.deposit0, users.unprivilegedAddress);
        vm.prank(accountB);
        uint256 paid = secondAsyncVault.redeem(shares, accountB, accountB);

        // Then: The claims are the epochs' outputs.
        assertEq(claimed, settledShares);
        assertEq(paid, settledAssets);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), settledShares);
        assertEq(token1.balanceOf(accountB), settledAssets);
    }
}
