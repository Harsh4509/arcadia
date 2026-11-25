/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "../fuzz/ALMVaultSync/_ALMVaultSync.fuzz.t.sol";
import { ConfigLib } from "../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Range } from "../../src/core/types/Range.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Gas of the costliest exit through every range, read with --isolate.
 */
contract ExitGas_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The gas an exit may use.
    uint256 internal constant MAX_EXIT_GAS = 14_000_000;
    // The share of a position's emissions the penalty forfeits, in pips.
    uint256 internal constant PARTIAL_PENALTY_RATE = 500_000;
    // The referral share of emissions, the gauge factory's default cap.
    uint256 internal constant REFERRAL_SHARE = 50_000;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    // The referral recipient of the gauge.
    address internal referral = makeAddr("referral");

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();

        PoolState memory poolState;
        CoreState memory coreState;
        RangeState memory range;
        poolState.sqrtPrice = SQRT_PRICE_ONE_X96;
        poolState.liquidityPool = type(uint128).max;
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        range.tickLower = -3000;
        range.tickUpper = 3000;
        range.liquidity = type(uint128).max;
        range.liquidityStaked = type(uint128).max;
        givenValidRangeState(range, poolState, false);

        coreState.supply = 1e40;
        coreState.buffer0 = 1e40;
        coreState.buffer1 = 1e40;
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        RangeState memory nested;
        for (int24 step; almCore.getRangesLength() < ConfigLib.MAX_RANGE_CAP; ++step) {
            nested.tickLower = range.tickLower - step * poolState.tickSpacing;
            nested.tickUpper = range.tickUpper + step * poolState.tickSpacing;
            nested.liquidity = Constants.MIN_FUZZED_LIQUIDITY;
            nested.liquidityStaked = range.liquidityStaked;
            setRangeState(nested);
        }
        addEmissionsToGaugeCL(pool, gauge, MAX_BASE_RATE / 2);
        closePenaltyWindow(gauge);

        fundActorForTick(pool, users.unprivilegedAddress, poolState.tickSpacing / 2);
        pushPriceToTick(pool, users.unprivilegedAddress, poolState.tickSpacing / 2);
        fundActorForTick(pool, users.unprivilegedAddress, 0);
        pushPriceToTick(pool, users.unprivilegedAddress, 0);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        setReferralConfig(gauge, referral, REFERRAL_SHARE);
        setPenaltyConfig(clGaugeFactory.minStakeBlocks(address(gauge)), PARTIAL_PENALTY_RATE);
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_exitGas_AtMaxRangeCap_Token0(uint256 shares) public {
        // Given: A core at the maximum range cap, every range staked, emissions live.
        uint256 rangeCount = ConfigLib.MAX_RANGE_CAP;
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());
        uint256[] memory stakedBefore = new uint256[](rangeCount);
        for (uint256 i; i < rangeCount; ++i) {
            stakedBefore[i] = almCore.getRange(i).stakedLiquidity;
            assertFalse(almCore.isPenaltyWindowOpen(i));
        }

        // And: Fees on both tokens, a referral, a partial penalty on every staked side.
        assertGt(pool.feeGrowthGlobal0X128(), 0);
        assertGt(pool.feeGrowthGlobal1X128(), 0);
        (, uint256 share) = clGaugeFactory.referralConfig(address(gauge));
        assertEq(share, REFERRAL_SHARE);
        assertEq(clGaugeFactory.effectivePenaltyConfig(address(gauge)).penaltyRate, PARTIAL_PENALTY_RATE);

        // And: A price a wei under an initialized tick the token0 vault's sale crosses.
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(
            sqrtPriceX96(pool), pool.tickSpacing(), 2 * pool.tickSpacing(), Constants.MIN_FUZZED_LIQUIDITY
        );
        mintPosition(pool, users.liquidityProvider, pool.tickSpacing(), 2 * pool.tickSpacing(), amount0, amount1);
        uint160 target = TickMath.getSqrtPriceAtTick(pool.tickSpacing()) - 1;
        uint256 amountIn = SqrtPriceMath.getAmount1Delta(sqrtPriceX96(pool), target, pool.liquidity(), true)
            .fullMulDivUp(MAX_PIPS, MAX_PIPS - pool.fee());
        token1.mint(users.unprivilegedAddress, amountIn);
        swapAsActor(pool, users.unprivilegedAddress, address(token1), address(token0), amountIn, target);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        assertEq(currentTick(pool), pool.tickSpacing() - 1);

        // And: Shares within slippage whose exit drains every range's unstaked side.
        ALMVaultSync vault = vaultFor(true);
        uint256 most = redeemableWithinSlippage(vault);
        uint256 floor = 1;
        uint256 supply = almCore.totalSupply();
        for (uint256 i; i < rangeCount; ++i) {
            Range memory staged = almCore.getRange(i);
            uint256 total = uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity;
            floor = FixedPointMathLib.max(
                floor, (uint256(positionLiquidity(staged.unstakedTokenId)) + 1).fullMulDivUp(supply, total)
            );
        }
        shares = bound(shares, floor, most);
        uint256 assets = vault.previewRedeem(shares);
        vm.assume(vault.previewWithdraw(assets) >= floor);
        approveVault(users.steward, vault, type(uint256).max);

        // When: A holder exits through the token0 vault, withdrawing.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward, type(uint256).max);
        uint256 used = vm.lastFrameGas().gasTotalUsed;
        {
            bytes memory data = abi.encodeWithSignature(
                "withdraw(uint256,address,address,uint256)", assets, users.steward, users.steward, type(uint256).max
            );
            uint256 tokens;
            for (uint256 i; i < data.length; ++i) {
                tokens += data[i] == 0 ? 1 : 4;
            }
            used = FixedPointMathLib.max(
                Constants.TX_BASE_GAS + Constants.STANDARD_TOKEN_GAS * tokens + used,
                Constants.TX_BASE_GAS + Constants.FLOOR_TOKEN_GAS * tokens
            );
        }

        // Then: The transaction fits the exit budget.
        emit log_named_uint("gas exit token0", used);
        assertLe(used, MAX_EXIT_GAS);

        // And: The sale crossed the tick, every range released both sides and restaked.
        assertGe(currentTick(pool), pool.tickSpacing());
        for (uint256 i; i < rangeCount; ++i) {
            Range memory range = almCore.getRange(i);
            assertEq(positionLiquidity(range.unstakedTokenId), 0);
            assertLt(range.stakedLiquidity, stakedBefore[i]);
            assertGt(range.stakedLiquidity, 0);
        }
    }

    function testFuzz_Success_exitGas_AtMaxRangeCap_Token1(uint256 shares) public {
        // Given: A core at the maximum range cap, every range staked, emissions live.
        uint256 rangeCount = ConfigLib.MAX_RANGE_CAP;
        assertEq(almCore.getRangesLength(), almCore.rangeCap_());
        uint256[] memory stakedBefore = new uint256[](rangeCount);
        for (uint256 i; i < rangeCount; ++i) {
            stakedBefore[i] = almCore.getRange(i).stakedLiquidity;
            assertFalse(almCore.isPenaltyWindowOpen(i));
        }

        // And: Fees on both tokens, a referral, a partial penalty on every staked side.
        assertGt(pool.feeGrowthGlobal0X128(), 0);
        assertGt(pool.feeGrowthGlobal1X128(), 0);
        (, uint256 share) = clGaugeFactory.referralConfig(address(gauge));
        assertEq(share, REFERRAL_SHARE);
        assertEq(clGaugeFactory.effectivePenaltyConfig(address(gauge)).penaltyRate, PARTIAL_PENALTY_RATE);

        // And: A price a wei above an initialized tick the token1 vault's sale crosses.
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(
            sqrtPriceX96(pool), -2 * pool.tickSpacing(), -pool.tickSpacing(), Constants.MIN_FUZZED_LIQUIDITY
        );
        mintPosition(pool, users.liquidityProvider, -2 * pool.tickSpacing(), -pool.tickSpacing(), amount0, amount1);
        uint160 target = TickMath.getSqrtPriceAtTick(-pool.tickSpacing()) + 1;
        uint256 amountIn = SqrtPriceMath.getAmount0Delta(target, sqrtPriceX96(pool), pool.liquidity(), true)
            .fullMulDivUp(MAX_PIPS, MAX_PIPS - pool.fee());
        token0.mint(users.unprivilegedAddress, amountIn);
        swapAsActor(pool, users.unprivilegedAddress, address(token0), address(token1), amountIn, target);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        assertEq(currentTick(pool), -pool.tickSpacing());

        // And: Shares within slippage whose exit drains every range's unstaked side.
        ALMVaultSync vault = vaultFor(false);
        uint256 most = redeemableWithinSlippage(vault);
        uint256 floor = 1;
        uint256 supply = almCore.totalSupply();
        for (uint256 i; i < rangeCount; ++i) {
            Range memory staged = almCore.getRange(i);
            uint256 total = uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity;
            floor = FixedPointMathLib.max(
                floor, (uint256(positionLiquidity(staged.unstakedTokenId)) + 1).fullMulDivUp(supply, total)
            );
        }
        shares = bound(shares, floor, most);
        uint256 assets = vault.previewRedeem(shares);
        vm.assume(vault.previewWithdraw(assets) >= floor);
        approveVault(users.steward, vault, type(uint256).max);

        // When: A holder exits through the token1 vault, withdrawing.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward, type(uint256).max);
        uint256 used = vm.lastFrameGas().gasTotalUsed;
        {
            bytes memory data = abi.encodeWithSignature(
                "withdraw(uint256,address,address,uint256)", assets, users.steward, users.steward, type(uint256).max
            );
            uint256 tokens;
            for (uint256 i; i < data.length; ++i) {
                tokens += data[i] == 0 ? 1 : 4;
            }
            used = FixedPointMathLib.max(
                Constants.TX_BASE_GAS + Constants.STANDARD_TOKEN_GAS * tokens + used,
                Constants.TX_BASE_GAS + Constants.FLOOR_TOKEN_GAS * tokens
            );
        }

        // Then: The transaction fits the exit budget.
        emit log_named_uint("gas exit token1", used);
        assertLe(used, MAX_EXIT_GAS);

        // And: The sale crossed the tick, every range released both sides and restaked.
        assertLt(currentTick(pool), -pool.tickSpacing());
        for (uint256 i; i < rangeCount; ++i) {
            Range memory range = almCore.getRange(i);
            assertEq(positionLiquidity(range.unstakedTokenId), 0);
            assertLt(range.stakedLiquidity, stakedBefore[i]);
            assertGt(range.stakedLiquidity, 0);
        }
    }
}
