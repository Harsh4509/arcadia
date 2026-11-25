/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "maxWithdraw" of contract "ALMVaultSync".
 */
contract MaxWithdraw_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
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

    function testFuzz_Revert_maxWithdraw_CoreNotDeployed(PoolState memory poolState, bool isToken0, address owner_)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? 0 : 1];

        // When: Reading maxWithdraw() on one of its synchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        IALMSyncExtension(vault).maxWithdraw(owner_);
    }

    function testFuzz_Success_maxWithdraw_ZeroWhenPaused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, an approving holder, and a pause.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        approveVault(users.steward, vault, type(uint256).max);
        vm.prank(factory);
        vault.setPaused(true);

        // When: Reading the holder's maxWithdraw.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxWithdraw(users.steward), 0);
    }

    function testFuzz_Success_maxWithdraw_ZeroWhileTheCoreIsLocked(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
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
        approveVault(users.steward, vault, type(uint256).max);

        // When: A router reads maxWithdraw while a keeper plan holds the core's lock.
        (bool success, bytes memory result) =
            readDuringPlan(address(vault), abi.encodeCall(IALMSyncExtension.maxWithdraw, (users.steward)));

        // Then: It is zero, and does not revert.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), 0);
    }

    function testFuzz_Success_maxWithdraw_ZeroWhenNotInitialized(
        PoolState memory poolState,
        address owner_,
        bool isToken0
    ) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Reading maxWithdraw.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxWithdraw(owner_), 0);
    }

    function testFuzz_Success_maxWithdraw_ZeroOutsideTheBand(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 deviation,
        bool above,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        approveVault(users.steward, vault, type(uint256).max);

        // And: A ratio band around the TWAP of up to the wide one cores use.
        deviation = bound(deviation, 0, Constants.WIDE_DEVIATION);
        vm.prank(factory);
        almCore.setDeviation(Constants.TWAP_WINDOW, deviation, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION);

        // And: Spot parked one tick past the band's edge, above or below.
        {
            uint256 mean = almCore.meanSqrtPriceX96_();
            uint256 edge = above
                ? FixedPointMathLib.fullMulDiv(mean, 1e18 + deviation, 1e18)
                : FixedPointMathLib.fullMulDivUp(mean, 1e18, 1e18 + deviation);
            int24 tick = TickMath.getTickAtSqrtPrice(uint160(edge));
            parkSpotAt(poolState, range, above ? tick + 1 : tick - 1);
        }

        // When: Reading the holder's maxWithdraw.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxWithdraw(users.steward), 0);
    }

    function testFuzz_Success_maxWithdraw_WithdrawingItSucceeds(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 kept,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);

        // And: Other providers' depth of at most half a price unit's wei liquidity.
        poolState.liquidityPool = uint128(
            bound(
                poolState.liquidityPool,
                Constants.MIN_FUZZED_LIQUIDITY,
                FixedPointMathLib.max(1 << 96, poolState.sqrtPrice * poolState.sqrtPrice >> 96) / 2
            )
        );
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);

        // And: Range legs within the rest of that liquidity.
        {
            uint256 room = FixedPointMathLib.max(1 << 96, poolState.sqrtPrice * poolState.sqrtPrice >> 96)
                - poolState.liquidityPool;
            range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, room / 2));
            range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, room - range.liquidity));
        }

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);

        // And: An asset buffer whose part in a held aLP covers its burn's rounding.
        uint256 leastAsset = ((isToken0
                    ? uint256(1 << 96).divUp(poolState.sqrtPrice)
                    : poolState.sqrtPrice.divUp(1 << 96))
            + 3)
        .fullMulDivUp(coreState.supply, coreState.supply - almCore.DEAD_SHARES_()) + 6;
        givenValidCoreState(
            coreState, poolState, range, coreState.supply, isToken0 ? leastAsset : 0, isToken0 ? 0 : leastAsset
        );
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A holder keeping from its burn's asset rounding to all the aLP.
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
            uint256 length = almCore.getRangesLength();
            uint256 rounding =
                length * ((isToken0 ? uint256(1 << 96).divUp(sqrtPrice) : sqrtPrice.divUp(1 << 96)) + 2) + 1;
            uint256 least = rounding.fullMulDivUp(
                almCore.totalSupply(), FixedPointMathLib.max((isToken0 ? amount0 : amount1).zeroFloorSub(length + 1), 1)
            );
            kept = bound(kept, least, almCore.balanceOf(users.steward));
        }
        uint256 rest = almCore.balanceOf(users.steward) - kept;
        vm.prank(users.steward);
        almCore.transfer(users.unprivilegedAddress, rest);
        uint256 balanceBefore = almCore.balanceOf(users.steward);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(users.steward);
        uint256 assets = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);

        // When: The holder withdraws its maxWithdraw.
        vm.prank(users.steward);
        uint256 burned = vault.withdraw(assets, users.steward, users.steward);

        // Then: It burned no more than it kept, and paid at least what was asked.
        assertLe(burned, kept);
        assertEq(almCore.balanceOf(users.steward), balanceBefore - burned);
        assertGe(ERC20Mock(vault.asset()).balanceOf(users.steward) - assetsBefore, assets);
    }

    function testFuzz_Success_maxWithdraw_ZeroWhenTheFeeCannotBeRead(
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

        // When: Reading maxWithdraw.
        // Then: It is zero, and does not revert.
        assertEq(IALMSyncExtension(address(vault)).maxWithdraw(users.steward), 0);
    }

    function testFuzz_Success_maxWithdraw_ZeroWithoutActiveLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0
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

        // When: Reading the holder's maxWithdraw.
        // Then: It is zero, the pool buying none of the non-asset the burn releases.
        assertEq(IALMSyncExtension(address(vault)).maxWithdraw(users.steward), 0);
    }

    function testFuzz_Success_maxWithdraw_ItsWithdrawSucceedsAfterAPricePush(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        bool zeroForOne,
        uint256 amountIn,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot pushed either way by at most a 1% sale.
        uint256 ceiling = (zeroForOne
                ? uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPriceX96(pool))
                : uint256(pool.liquidity()).fullMulDiv(sqrtPriceX96(pool), 1 << 96))
        .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR);
        amountIn = bound(amountIn, 1, ceiling);
        ERC20Mock(zeroForOne ? pool.token0() : pool.token1()).mint(users.unprivilegedAddress, amountIn);
        pushPrice(pool, users.unprivilegedAddress, zeroForOne, amountIn);

        // And: The holder's maxWithdraw.
        uint256 assets = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
        // And: Where maxWithdraw is zero, a hole no bound expresses.
        vm.assume(assets > 0);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(users.steward);

        // When: The holder withdraws it.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);

        // Then: It paid at least what was asked.
        assertGe(ERC20Mock(vault.asset()).balanceOf(users.steward) - assetsBefore, assets);
    }

    function testFuzz_Success_maxWithdraw_ItsWithdrawSucceedsWithinTheSwapCost(
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
        vm.prank(factory);
        almCore.setPlanLimits(Constants.WIDE_MAX_SHORTFALL_BPS, uint16(maxSwapCostBps), 0);

        // And: The holder's maxWithdraw.
        uint256 assets = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
        // And: Where maxWithdraw is zero, a hole no bound expresses.
        vm.assume(assets > 0);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(users.steward);
        uint256 sqrtPriceStart = sqrtPriceX96(pool);

        // When: The holder withdraws it through the plain signature.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);

        // Then: It paid at least what was asked.
        assertGe(ERC20Mock(vault.asset()).balanceOf(users.steward) - assetsBefore, assets);

        // And: Its swap ended at or inside the swap cost's band.
        uint256 scale = 1e18 + (maxSwapCostBps * 100 - pool.fee()) * 5e11;
        if (!isToken0) assertGe(sqrtPriceX96(pool), sqrtPriceStart.fullMulDivUp(1e18, scale));
        else assertLe(sqrtPriceX96(pool), sqrtPriceStart.fullMulDiv(scale, 1e18));
    }

    function testFuzz_Success_maxWithdraw_ItsWithdrawFillsAndPaysTheAssets(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);

        // And: Other providers' depth of at most half a price unit's wei liquidity.
        poolState.liquidityPool = uint128(
            bound(
                poolState.liquidityPool,
                Constants.MIN_FUZZED_LIQUIDITY,
                FixedPointMathLib.max(1 << 96, poolState.sqrtPrice * poolState.sqrtPrice >> 96) / 2
            )
        );
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);

        // And: Range legs within the rest of that liquidity.
        {
            uint256 room = FixedPointMathLib.max(1 << 96, poolState.sqrtPrice * poolState.sqrtPrice >> 96)
                - poolState.liquidityPool;
            range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, room / 2));
            range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, room - range.liquidity));
        }
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        givenValidCoreStateAboveTheExitRounding(coreState, poolState, range, isToken0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A max swap cost above the pool's fee and below the whole value.
        maxSwapCostBps = bound(maxSwapCostBps, poolState.fee / 100 + 1, ConfigLib.BPS_DENOMINATOR - 1);
        vm.prank(factory);
        almCore.setPlanLimits(Constants.WIDE_MAX_SHORTFALL_BPS, uint16(maxSwapCostBps), 0);

        // And: The holder's maxWithdraw and maxRedeem.
        uint256 assets = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
        // And: Where maxWithdraw is zero, a hole no bound expresses.
        vm.assume(assets > 0);
        uint256 most = IALMSyncExtension(address(vault)).maxRedeem(users.steward);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(users.steward);

        // When: The holder withdraws it through the plain signature.
        vm.prank(users.steward);
        uint256 burned = vault.withdraw(assets, users.steward, users.steward);

        // Then: It paid at least the assets, and burned at most the holder's maxRedeem.
        assertGe(ERC20Mock(vault.asset()).balanceOf(users.steward) - assetsBefore, assets);
        assertLe(burned, most);
    }

    function testFuzz_Success_maxWithdraw_UnderReportsByAtMostTheMargin(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);

        // And: Other providers' depth of at most half a price unit's wei liquidity.
        poolState.liquidityPool = uint128(
            bound(
                poolState.liquidityPool,
                Constants.MIN_FUZZED_LIQUIDITY,
                FixedPointMathLib.max(1 << 96, poolState.sqrtPrice * poolState.sqrtPrice >> 96) / 2
            )
        );
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);

        // And: Range legs within the rest of that liquidity.
        {
            uint256 room = FixedPointMathLib.max(1 << 96, poolState.sqrtPrice * poolState.sqrtPrice >> 96)
                - poolState.liquidityPool;
            range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, room / 2));
            range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, room - range.liquidity));
        }
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        givenValidCoreStateAboveTheExitRounding(coreState, poolState, range, isToken0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A max swap cost above the pool's fee and below the whole value.
        maxSwapCostBps = bound(maxSwapCostBps, poolState.fee / 100 + 1, ConfigLib.BPS_DENOMINATOR - 1);
        vm.prank(factory);
        almCore.setPlanLimits(Constants.WIDE_MAX_SHORTFALL_BPS, uint16(maxSwapCostBps), 0);

        // And: The preview's margin over the sale's steps to the band's edge.
        uint256 margin;
        {
            bool zeroForOne = !isToken0;
            uint160 spot = sqrtPriceX96(pool);
            uint256 fee = pool.fee();
            uint256 ranges = almCore.getRangesLength();
            uint160 limit = SnapshotLib.getSwapCostLimit(spot, fee, maxSwapCostBps, zeroForOne);
            uint256 steps;
            {
                int256 ticks = int256(TickMath.getTickAtSqrtPrice(spot)) - TickMath.getTickAtSqrtPrice(limit);
                uint256 span = uint256(ticks < 0 ? -ticks : ticks) + 1;
                uint256 tickSpacing = uint256(int256(pool.tickSpacing()));
                steps = span / tickSpacing + span / (256 * tickSpacing) + 3;
            }
            uint256 marginIn = ranges * ((zeroForOne ? uint256(1 << 96).divUp(spot) : uint256(spot).divUp(1 << 96)) + 2)
                + 1 + 2 * ranges
                + (zeroForOne
                        ? SqrtPriceMath.getAmount0Delta(limit, spot, uint128(ranges), true)
                        : SqrtPriceMath.getAmount1Delta(spot, limit, uint128(ranges), true))
                .fullMulDivUp(1e6, 1e6 - fee) + ((2e6 - fee) * steps).divUp(1e6 - fee);
            margin = ranges * ((zeroForOne ? uint256(spot).divUp(1 << 96) : uint256(1 << 96).divUp(spot)) + 2) + 1
                + steps + 2 * ranges + CLMath.convert(spot, zeroForOne, marginIn, false) + 1;
        }

        // When: Reading the holder's maxRedeem, its redeem and the holder's maxWithdraw.
        uint256 most = IALMSyncExtension(address(vault)).maxRedeem(users.steward);
        uint256 redeemed = vault.previewRedeem(most);
        uint256 assets = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);

        // Then: maxWithdraw is short of that redeem by at most the margin.
        assertLe(redeemed - assets, margin);

        // And: A withdraw of it burns at most the holder's maxRedeem.
        assertLe(vault.previewWithdraw(assets), most);
    }

    function testFuzz_Success_maxWithdraw_ZeroOnARangeEdgeWhenTheSwapCostIsWithinTheFee(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range around spot, and a holder that approved it.
        givenValidRangeState(range, poolState, true);

        // And: A non-asset buffer a wei past the range's two legs, each rounded up.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, isToken0 ? 0 : 2, isToken0 ? 2 : 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        approveVault(users.steward, vault, type(uint256).max);

        // And: A max swap cost of at most the pool's fee.
        setMaxSwapCost(bound(maxSwapCostBps, 0, poolState.fee / 100));

        // And: Spot parked on the range's lower edge from above, its tick one below.
        parkSpotAt(poolState, range, range.tickLower);
        assertEq(sqrtPriceX96(pool), TickMath.getSqrtPriceAtTick(range.tickLower));
        assertEq(currentTick(pool), range.tickLower - 1);

        // When: Reading the holder's maxWithdraw.
        // Then: It is zero, as maxRedeem is.
        assertEq(IALMSyncExtension(address(vault)).maxRedeem(users.steward), 0);
        assertEq(IALMSyncExtension(address(vault)).maxWithdraw(users.steward), 0);
    }
}
