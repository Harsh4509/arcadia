/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { Constants } from "../../../utils/Constants.sol";
import { ERC20Mock } from "../../../utils/mocks/ERC20Mock.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PoolLogic } from "../../../../src/shared/libraries/logic/PoolLogic.sol";
import { Snapshot } from "../../../../src/vaults/types/Snapshot.sol";
import { SnapshotLibExtension } from "../../../utils/extensions/SnapshotLibExtension.sol";
import { StepComputations, SwapState } from "../../../../src/vaults/types/SwapState.sol";
import { SwapStateLibExtension } from "../../../utils/extensions/SwapStateLibExtension.sol";

/**
 * @notice Fuzz tests for the function "getStepFees" of library "SwapStateLib".
 */
contract GetStepFees_SwapStateLib_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    SnapshotLibExtension internal snapshotLib;
    SwapStateLibExtension internal swapStateLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        snapshotLib = new SnapshotLibExtension();
        swapStateLib = new SwapStateLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_getStepFees_TheUnstakedShareOfTheFeeRoundedUp(
        uint256 feeAmount,
        uint256 feeShare,
        uint128 liquidity,
        uint128 unstakedLiquidity
    ) public view {
        // Given: A step's fee, the fee share and the core's unstaked liquidity.
        SwapState memory swapState;
        StepComputations memory step;
        step.feeAmount = bound(feeAmount, 1, type(uint128).max);
        swapState.feeShare = bound(feeShare, 1, Constants.FEE_SHARE_UNIT);
        swapState.liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        swapState.position.unstakedLiquidity = bound(unstakedLiquidity, 1, swapState.liquidity);

        // When: Reading the core's fee share rounded up.
        uint256 feesIn = swapStateLib.getStepFees(swapState, step, true);

        // Then: The fee at the fee share, pro rata to unstaked liquidity, rounded up.
        assertEq(
            feesIn,
            FullMath.mulDivRoundingUp(
                step.feeAmount * swapState.feeShare,
                swapState.position.unstakedLiquidity,
                Constants.FEE_SHARE_UNIT * uint256(swapState.liquidity)
            )
        );
    }

    function testFuzz_Success_getStepFees_TheUnstakedShareOfTheFeeRoundedDown(
        uint256 feeAmount,
        uint256 feeShare,
        uint128 liquidity,
        uint128 unstakedLiquidity
    ) public view {
        // Given: A step's fee, the fee share and the core's unstaked liquidity.
        SwapState memory swapState;
        StepComputations memory step;
        step.feeAmount = bound(feeAmount, 1, type(uint128).max);
        swapState.feeShare = bound(feeShare, 1, Constants.FEE_SHARE_UNIT);
        swapState.liquidity = uint128(bound(liquidity, 1, type(uint128).max));
        swapState.position.unstakedLiquidity = bound(unstakedLiquidity, 1, swapState.liquidity);

        // When: Reading the core's fee share rounded down.
        uint256 feesIn = swapStateLib.getStepFees(swapState, step, false);

        // Then: The fee at the fee share, pro rata to unstaked liquidity, rounded down.
        assertEq(
            feesIn,
            FullMath.mulDiv(
                step.feeAmount * swapState.feeShare,
                swapState.position.unstakedLiquidity,
                Constants.FEE_SHARE_UNIT * uint256(swapState.liquidity)
            )
        );
    }

    function testFuzz_Success_getStepFees_BoundsTheCoresNetFees(
        uint16 protocolSwapFeeBps,
        uint160 sqrtPriceTargetX96,
        bool zeroForOne,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot, with no staked leg.
        {
            int24 band = bandTick(poolState.tickSpacing) / poolState.tickSpacing;
            int24 compressed = poolState.tickCurrent / poolState.tickSpacing;
            if (poolState.tickCurrent < 0 && poolState.tickCurrent % poolState.tickSpacing != 0) --compressed;
            range.tickLower = int24(bound(range.tickLower, -band + 1, compressed)) * poolState.tickSpacing;
            range.tickUpper = int24(bound(range.tickUpper, compressed + 1, band - 1)) * poolState.tickSpacing;
        }
        range.liquidityStaked = 0;
        givenValidRangeState(range, poolState, false);

        // And: A seeded vault holding it, and a protocol swap fee.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_()));
        {
            uint16 protocolEmissionFeeBps = almCore.protocolEmissionFeeBps_();
            vm.prank(factory);
            almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, users.feeRecipient);
        }

        // And: A step from spot to a target, the fee share net of levy and protocol.
        SwapState memory swapState;
        StepComputations memory step;
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
        swapState = swapStateLib.getSwapState(snapshot, address(pool), zeroForOne);
        swapState.feeShare = snapshotLib.getFeeShare(snapshot, address(pool));
        step = swapStateLib.setNextTick(swapState, address(pool), zeroForOne, PoolLogic.sqrtPriceLimit(zeroForOne));
        // And: A next price apart from spot, a hole for spot sitting on the next tick.
        vm.assume(step.sqrtPriceTargetX96 != snapshot.sqrtPriceX96);
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(bound(sqrtPriceTargetX96, step.sqrtPriceTargetX96, snapshot.sqrtPriceX96 - 1))
            : uint160(bound(sqrtPriceTargetX96, snapshot.sqrtPriceX96 + 1, step.sqrtPriceTargetX96));
        step = swapStateLib.computeSwapStep(swapState, step, zeroForOne, true);

        // When: The pool swaps that step.
        (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
        uint256 feesBefore = zeroForOne ? fees0 : fees1;
        {
            (address tokenIn, address tokenOut) =
                zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
            ERC20Mock(tokenIn).mint(users.liquidityProvider, step.amountIn + step.feeAmount);
            swapAsActor(
                pool,
                users.liquidityProvider,
                tokenIn,
                tokenOut,
                step.amountIn + step.feeAmount,
                step.sqrtPriceTargetX96
            );
        }
        (fees0, fees1,) = almCore.getUnstakedPositions();
        uint256 earned = (zeroForOne ? fees0 : fees1) - feesBefore;

        // Then: Its net fees rose at least by the floored fees, less a wei of levy.
        // And: At most rounded up, plus a wei of protocol share floored on totals.
        assertLe(swapStateLib.getStepFees(swapState, step, false), earned + (pool.unstakedFee() > 0 ? 1 : 0));
        assertLe(earned, swapStateLib.getStepFees(swapState, step, true) + (protocolSwapFeeBps > 0 ? 1 : 0));
    }

    function testFuzz_Success_getStepFees_BoundsTheCoresNetFeesWithAStakedLeg(
        uint16 protocolSwapFeeBps,
        uint160 sqrtPriceTargetX96,
        bool zeroForOne,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState
    ) public {
        // Given: A pool with depth at a fuzzed price and a non-zero unstaked fee.
        givenValidPoolState(poolState);
        poolState.unstakedFee = uint24(bound(poolState.unstakedFee, 1, Constants.MAX_UNSTAKED_FEE));
        setPoolState(poolState, false);

        // And: A range around spot with a staked leg.
        givenValidRangeState(range, poolState, true);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }

        // And: A seeded vault with a protocol swap fee, holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_()));
        {
            uint16 protocolEmissionFeeBps = almCore.protocolEmissionFeeBps_();
            vm.prank(factory);
            almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, users.feeRecipient);
        }
        setRangeState(range);

        // And: A step from spot to a target, the fee share net of levy and protocol.
        SwapState memory swapState;
        StepComputations memory step;
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
        swapState = swapStateLib.getSwapState(snapshot, address(pool), zeroForOne);
        swapState.feeShare = snapshotLib.getFeeShare(snapshot, address(pool));
        step = swapStateLib.setNextTick(swapState, address(pool), zeroForOne, PoolLogic.sqrtPriceLimit(zeroForOne));
        // And: A next price apart from spot, a hole for spot sitting on the next tick.
        vm.assume(step.sqrtPriceTargetX96 != snapshot.sqrtPriceX96);
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(bound(sqrtPriceTargetX96, step.sqrtPriceTargetX96, snapshot.sqrtPriceX96 - 1))
            : uint160(bound(sqrtPriceTargetX96, snapshot.sqrtPriceX96 + 1, step.sqrtPriceTargetX96));
        step = swapStateLib.computeSwapStep(swapState, step, zeroForOne, true);

        // When: The pool swaps that step.
        (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
        uint256 feesBefore = zeroForOne ? fees0 : fees1;
        {
            (address tokenIn, address tokenOut) =
                zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
            ERC20Mock(tokenIn).mint(users.liquidityProvider, step.amountIn + step.feeAmount);
            swapAsActor(
                pool,
                users.liquidityProvider,
                tokenIn,
                tokenOut,
                step.amountIn + step.feeAmount,
                step.sqrtPriceTargetX96
            );
        }
        (fees0, fees1,) = almCore.getUnstakedPositions();
        uint256 earned = (zeroForOne ? fees0 : fees1) - feesBefore;

        // Then: Net fees rose at least the floored fees less 2 wei of split and levy.
        assertLe(swapStateLib.getStepFees(swapState, step, false), earned + 2);

        // And: At most the step's fees rounded up.
        assertLe(earned, swapStateLib.getStepFees(swapState, step, true));
    }

    function testFuzz_Success_getStepFees_BoundsTheCoresNetFeesAfterAPriorStep(
        uint16 protocolSwapFeeBps,
        uint160 sqrtPriceTargetX96,
        uint160 sqrtPricePriorX96,
        bool zeroForOne,
        RangeState memory range,
        PoolState memory poolState,
        CoreState memory coreState
    ) public {
        // Given: A pool with depth at a fuzzed price and a non-zero unstaked fee.
        givenValidPoolState(poolState);
        poolState.unstakedFee = uint24(bound(poolState.unstakedFee, 1, Constants.MAX_UNSTAKED_FEE));
        setPoolState(poolState, false);

        // And: A range around spot with a staked leg.
        givenValidRangeState(range, poolState, true);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }

        // And: A seeded vault with a protocol swap fee, holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        protocolSwapFeeBps = uint16(bound(protocolSwapFeeBps, 0, almCore.MAX_FEE_BPS_()));
        {
            uint16 protocolEmissionFeeBps = almCore.protocolEmissionFeeBps_();
            vm.prank(factory);
            almCore.setProtocolFees(protocolEmissionFeeBps, protocolSwapFeeBps, users.feeRecipient);
        }
        setRangeState(range);

        // And: A prior step from spot to short of the next tick, its fees uncollected.
        SwapState memory swapState;
        StepComputations memory step;
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
        swapState = swapStateLib.getSwapState(snapshot, address(pool), zeroForOne);
        step = swapStateLib.setNextTick(swapState, address(pool), zeroForOne, PoolLogic.sqrtPriceLimit(zeroForOne));
        // And: Room for a prior step, a hole for spot within a wei of the next tick.
        vm.assume(
            zeroForOne
                ? step.sqrtPriceTargetX96 + 1 < snapshot.sqrtPriceX96
                : snapshot.sqrtPriceX96 + 1 < step.sqrtPriceTargetX96
        );
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(bound(sqrtPricePriorX96, step.sqrtPriceTargetX96 + 1, snapshot.sqrtPriceX96 - 1))
            : uint160(bound(sqrtPricePriorX96, snapshot.sqrtPriceX96 + 1, step.sqrtPriceTargetX96 - 1));
        step = swapStateLib.computeSwapStep(swapState, step, zeroForOne, true);
        (address tokenIn, address tokenOut) =
            zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        ERC20Mock(tokenIn).mint(users.liquidityProvider, step.amountIn + step.feeAmount);
        swapAsActor(
            pool, users.liquidityProvider, tokenIn, tokenOut, step.amountIn + step.feeAmount, step.sqrtPriceTargetX96
        );

        // And: A step on to the next tick at most, fee share net of levy and protocol.
        snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(this));
        swapState = swapStateLib.getSwapState(snapshot, address(pool), zeroForOne);
        swapState.feeShare = snapshotLib.getFeeShare(snapshot, address(pool));
        step = swapStateLib.setNextTick(swapState, address(pool), zeroForOne, PoolLogic.sqrtPriceLimit(zeroForOne));
        step.sqrtPriceTargetX96 = zeroForOne
            ? uint160(bound(sqrtPriceTargetX96, step.sqrtPriceTargetX96, snapshot.sqrtPriceX96 - 1))
            : uint160(bound(sqrtPriceTargetX96, snapshot.sqrtPriceX96 + 1, step.sqrtPriceTargetX96));
        step = swapStateLib.computeSwapStep(swapState, step, zeroForOne, true);

        // When: The pool swaps that step.
        uint256 earned;
        {
            (uint256 fees0Before, uint256 fees1Before,) = almCore.getUnstakedPositions();
            ERC20Mock(tokenIn).mint(users.liquidityProvider, step.amountIn + step.feeAmount);
            swapAsActor(
                pool,
                users.liquidityProvider,
                tokenIn,
                tokenOut,
                step.amountIn + step.feeAmount,
                step.sqrtPriceTargetX96
            );
            (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
            earned = zeroForOne ? fees0 - fees0Before : fees1 - fees1Before;
        }

        // Then: Net fees rose at least the floored fees less 3 wei: split, levy, carry.
        assertLe(swapStateLib.getStepFees(swapState, step, false), earned + 3);

        // And: At most rounded up, plus a wei of protocol share floored on totals.
        assertLe(earned, swapStateLib.getStepFees(swapState, step, true) + (protocolSwapFeeBps > 0 ? 1 : 0));
    }
}
