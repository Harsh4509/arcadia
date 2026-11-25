/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "maxRedeem" of contract "ALMVaultSync".
 */
contract MaxRedeem_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_maxRedeem_CoreNotDeployed(PoolState memory poolState, bool isToken0, address owner_)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? 0 : 1];

        // When: Reading maxRedeem() on one of its synchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        IALMSyncExtension(vault).maxRedeem(owner_);
    }

    function testFuzz_Success_maxRedeem_ZeroWhenPaused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, an approving holder, and a pause.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);
        vm.prank(factory);
        vault.setPaused(true);

        // When: Reading the holder's maxRedeem.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxRedeem(users.steward), 0);
    }

    function testFuzz_Success_maxRedeem_ZeroWhileTheCoreIsLocked(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A vault seeded with it.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);

        // When: A router reads maxRedeem while a keeper plan holds the core's lock.
        (bool success, bytes memory result) =
            readDuringPlan(address(vault), abi.encodeCall(IALMSyncExtension.maxRedeem, (users.steward)));

        // Then: It is zero, and does not revert.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), 0);

        // And: Outside the plan the same read is above zero, so the lock alone zeroed it.
        assertGt(IALMSyncExtension(address(vault)).maxRedeem(users.steward), 0);
    }

    function testFuzz_Success_maxRedeem_ZeroWhenNotInitialized(
        PoolState memory poolState,
        address owner_,
        bool isToken0
    ) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Reading maxRedeem.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxRedeem(owner_), 0);
    }

    function testFuzz_Success_maxRedeem_ItsRedeemSucceedsWhateverTheAllowance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 allowance,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, approved for any amount.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, allowance);
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // When: Reading the holder's maxRedeem.
        uint256 shares = IALMSyncExtension(address(vault)).maxRedeem(users.steward);

        // Then: It is at most the holder's shares, and the plain redeem of it succeeds.
        assertLe(shares, balanceBefore);
        if (shares > 0) {
            vm.prank(users.steward);
            vault.redeem(shares, users.steward, users.steward);
            assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
        }
    }

    function testFuzz_Success_maxRedeem_ZeroOutsideTheBand(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 deviation,
        bool above,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);

        // And: A ratio band around the TWAP of up to the wide one cores use.
        deviation = bound(deviation, 0, Constants.WIDE_DEVIATION);
        setSpotFromTwap(deviation);

        // And: Spot parked one tick past the band's edge, above or below.
        {
            uint256 mean = almCore.meanSqrtPriceX96_();
            uint256 edge = above
                ? FixedPointMathLib.fullMulDiv(mean, 1e18 + deviation, 1e18)
                : FixedPointMathLib.fullMulDivUp(mean, 1e18, 1e18 + deviation);
            int24 tick = TickMath.getTickAtSqrtPrice(uint160(edge));
            parkSpotAt(poolState, range, above ? tick + 1 : tick - 1);
        }

        // When: Reading the holder's maxRedeem.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxRedeem(users.steward), 0);
    }

    function testFuzz_Success_maxRedeem_ZeroWhenTheFeeCannotBeRead(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A vault seeded with it, and an owner who approved it and can redeem.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);
        assertGt(IALMSyncExtension(address(vault)).maxRedeem(users.steward), 0);

        // And: A pool whose fee read reverts.
        vm.mockCallRevert(address(pool), abi.encodeWithSelector(IMetadexCLPool.fee.selector), "");

        // When: Reading maxRedeem.
        // Then: It is zero, and does not revert.
        assertEq(IALMSyncExtension(address(vault)).maxRedeem(users.steward), 0);
    }

    function testFuzz_Success_maxRedeem_ZeroWithoutActiveLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);

        // And: A non-asset buffer whose part in the holder's aLP is at least a wei.
        uint256 least = coreState.supply.divUp(coreState.supply - almCore.DEAD_SHARES_()) + 3;
        givenValidCoreState(coreState, poolState, range, coreState.supply, isToken0 ? 0 : least, isToken0 ? least : 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);

        // And: Spot a spacing past every position, where they hold only the other token.
        {
            int24 tick = isToken0
                ? bandTick(poolState.tickSpacing) + poolState.tickSpacing
                : -bandTick(poolState.tickSpacing) - poolState.tickSpacing;
            parkSpotAt(poolState, range, tick);
        }
        assertEq(pool.liquidity(), 0);

        // And: A TWAP window at that spot.
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // When: Reading the holder's maxRedeem.
        // Then: It is zero, the pool buying none of the non-asset the burn releases.
        assertEq(IALMSyncExtension(address(vault)).maxRedeem(users.steward), 0);
    }

    function testFuzz_Success_maxRedeem_IsTheBalanceWhenItsSaleStaysWithinTheSwapCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        uint256 balance = almCore.balanceOf(users.steward);

        // And: The sqrt price move of the balance's sale into the other providers alone.
        uint256 move;
        {
            uint256 sqrtPriceStart = sqrtPriceX96(pool);
            uint256 sold = isToken0 ? almCore.bufferAmount1() : almCore.bufferAmount0();
            for (uint256 i; i < almCore.getRangesLength(); ++i) {
                Range memory staged = almCore.getRange(i);
                (uint256 range0, uint256 range1) = amountsRoundedUp(
                    uint160(sqrtPriceStart),
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                sold += isToken0 ? range1 : range0;
            }
            sold = sold.fullMulDivUp(balance, almCore.totalSupply());
            uint256 sqrtPriceEnd = SqrtPriceMath.getNextSqrtPriceFromInput(
                uint160(sqrtPriceStart), poolState.liquidityPool, sold, !isToken0
            );
            move = isToken0
                ? sqrtPriceEnd.fullMulDivUp(1e18, sqrtPriceStart) - 1e18
                : sqrtPriceStart.fullMulDivUp(1e18, sqrtPriceEnd) - 1e18;
        }

        // And: A max swap cost under the whole value whose band holds the sale.
        {
            uint256 sqrtPrice = sqrtPriceX96(pool);
            (uint256 amount0, uint256 amount1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
            for (uint256 i; i < almCore.getRangesLength(); ++i) {
                Range memory staged = almCore.getRange(i);
                (uint256 range0, uint256 range1) = amountsRoundedDown(
                    uint160(sqrtPrice),
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                (amount0, amount1) = (amount0 + range0, amount1 + range1);
            }
            uint256 heldValue = amount1 + token0ToToken1(sqrtPrice, amount0);
            uint256 rounding = (pool.liquidity() >> 96) + 1 + 4 * (token0ToToken1(sqrtPrice, 1) + 1);
            uint256 least = ((move + 2).divUp(5e11) + pool.fee()).divUp(100)
                + (rounding * ConfigLib.BPS_DENOMINATOR)
                .divUp(FixedPointMathLib.max(balance.fullMulDiv(heldValue, almCore.totalSupply()), 1));
            // And: Where the band needs the whole value, a hole no bound expresses.
            vm.assume(least < ConfigLib.BPS_DENOMINATOR);
            maxSwapCostBps = bound(maxSwapCostBps, least, ConfigLib.BPS_DENOMINATOR - 1);
        }
        setMaxSwapCost(maxSwapCostBps);

        // When: Reading the holder's maxRedeem.
        uint256 shares = IALMSyncExtension(address(vault)).maxRedeem(users.steward);

        // Then: It is the holder's balance, and the holder's plain redeem of it succeeds.
        assertEq(shares, balance);
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);
        assertEq(almCore.balanceOf(users.steward), balance - shares);
    }

    function testFuzz_Success_maxRedeem_ItsRedeemSucceedsWithinTheSwapCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        givenValidCoreStateAboveTheExitRounding(coreState, poolState, range, isToken0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A max swap cost above the pool's fee and below the whole value.
        maxSwapCostBps = bound(maxSwapCostBps, uint256(poolState.fee).divUp(100) + 1, ConfigLib.BPS_DENOMINATOR - 1);
        setMaxSwapCost(maxSwapCostBps);

        // And: The holder's maxRedeem.
        uint256 shares = IALMSyncExtension(address(vault)).maxRedeem(users.steward);
        // And: Where maxRedeem is zero, a hole no bound expresses.
        vm.assume(shares > 0);
        uint256 balanceBefore = almCore.balanceOf(users.steward);
        uint256 sqrtPriceStart = sqrtPriceX96(pool);

        // When: The holder redeems it through the plain signature.
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward);

        // Then: The shares are burned.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);

        // And: Its swap ended at or inside the swap cost's band.
        uint256 scale = 1e18 + (maxSwapCostBps * 100 - pool.fee()) * 5e11;
        if (!isToken0) assertGe(sqrtPriceX96(pool), sqrtPriceStart.fullMulDivUp(1e18, scale));
        else assertLe(sqrtPriceX96(pool), sqrtPriceStart.fullMulDiv(scale, 1e18));
    }
}
