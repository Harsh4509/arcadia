/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMSyncExtension } from "../../../src/vaults/ALMSyncExtension.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSyncExtension } from "../../utils/extensions/ALMVaultSyncExtension.sol";
import { BaseVault_Fuzz_Test } from "../BaseVault/_BaseVault.fuzz.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { CoreParameters } from "../../../src/core/types/CoreParameters.sol";
import { DeployerMock } from "../../utils/mocks/DeployerMock.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { VaultParameters } from "../../../src/vaults/types/VaultParameters.sol";
import { VmSafe } from "@forge-std/Vm.sol";

/**
 * @notice Common logic needed by all "ALMVaultSync" fuzz tests.
 */
abstract contract ALMVaultSync_Fuzz_Test is BaseVault_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(BaseVault_Fuzz_Test) {
        BaseVault_Fuzz_Test.setUp();
    }

    function vaultExtension(bool isToken0) internal returns (ALMVaultSyncExtension vault) {
        DeployerMock deployer_ = new DeployerMock();
        CoreParameters memory coreParams;
        coreParams.vaults.syncVault0 = isToken0 ? vm.computeCreateAddress(address(deployer_), 2) : address(syncVault0);
        deployer_.setParameters(coreParams);
        deployer_.setVaultParameters(VaultParameters(isToken0, address(almCore), address(pool), address(0)));
        address syncExtension = deployer_.deploy(type(ALMSyncExtension).creationCode);
        deployer_.setVaultParameters(VaultParameters(isToken0, address(almCore), address(pool), syncExtension));
        vault = ALMVaultSyncExtension(deployer_.deploy(type(ALMVaultSyncExtension).creationCode));
    }

    /* //////////////////////////////////////////////////////////////
                               CORE STATE
    ////////////////////////////////////////////////////////////// */

    function seededVault(CoreState memory coreState, RangeState memory range, bool isToken0)
        internal
        returns (ALMVaultSync vault)
    {
        setSeededState(coreState, range);
        vault = vaultFor(isToken0);

        // And: A total cap of half the supply above it.
        uint256 totalCap = almCore.totalSupply() * 3 / 2;
        vm.prank(factory);
        almCore.setTotalCap(totalCap);
    }

    function seededThinLegVault(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool dustIsAsset,
        uint256 leg,
        uint256 maxSwapCostBps
    ) internal returns (ALMVaultSync vault) {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A token0 vault, its range beside spot, the dust token's buffer the leg.
        givenValidDustState(
            coreState, poolState, range, dustIsAsset, FixedPointMathLib.max(leg, 1), poolState.tickSpacing
        );
        vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A zero leg seeded as a wei that is then burnt.
        if (leg == 0) {
            ERC20Mock dust = dustIsAsset ? token0 : token1;
            almCore.setBuffers(dustIsAsset ? 0 : almCore.bufferAmount0(), dustIsAsset ? almCore.bufferAmount1() : 0);
            deal(address(dust), address(almCore), dust.balanceOf(address(almCore)) - 1);
        }
    }

    function seededDustRangeVault(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps
    ) internal returns (ALMVaultSync vault) {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core for a range around spot, its legs then shrunk to dust.
        givenValidRangeState(range, poolState, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        range.liquidity = uint128(bound(range.liquidity, 1, Constants.MIN_FUZZED_LIQUIDITY));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, Constants.MIN_FUZZED_LIQUIDITY));

        // And: An uncapped token0 vault, seeded with a token0 buffer then taken out.
        vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        setUncapped();
        uint256 buffer0 = almCore.bufferAmount0();
        almCore.setBuffers(0, almCore.bufferAmount1());
        deal(address(token0), address(almCore), token0.balanceOf(address(almCore)) - buffer0);
    }

    function seededFeeCarryVault(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 protocolSwapFeeBps,
        uint256 maxSwapCostBps
    ) internal returns (ALMVaultSync vault) {
        // Given: A pool with depth at a fuzzed price, the protocol taking swap fees.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setProtocolFees(0, uint16(bound(protocolSwapFeeBps, 0, ConfigLib.MAX_FEE_BPS)), users.feeRecipient);

        // And: A token0 vault holding a range around spot, without caps.
        givenValidRangeState(range, poolState, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        setUncapped();
    }

    function roundTrip(bool zeroForOne, uint256 tradeIn) internal {
        // And: A round trip up to the pool's slippage, leaving uncounted fees.
        uint256 depth = zeroForOne
            ? uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPriceX96(pool))
            : uint256(pool.liquidity()).fullMulDiv(sqrtPriceX96(pool), 1 << 96);
        tradeIn = bound(tradeIn, 0, depth.fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR));
        if (tradeIn == 0) return;
        address trader = users.unprivilegedAddress;
        (ERC20Mock tokenIn, ERC20Mock tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);
        uint256 balance = tokenOut.balanceOf(trader);
        tokenIn.mint(trader, tradeIn);
        swapAsActor(pool, trader, address(tokenIn), address(tokenOut), tradeIn, 0);
        uint256 bought = tokenOut.balanceOf(trader) - balance;
        if (bought > 0) swapAsActor(pool, trader, address(tokenOut), address(tokenIn), bought, 0);
    }

    function givenValidCoreStateAboveTheRounding(
        CoreState memory coreState,
        PoolState memory poolState,
        RangeState memory range,
        bool isToken0,
        uint256 margin,
        uint256 leg
    ) internal view {
        // And: Buffers whose legs in an entry to the cost's limit cover their rounding.
        uint256 sqrtPrice = poolState.sqrtPrice;
        uint256 shares;
        uint256 leastOut;
        {
            uint256 retained = (1e6 - uint256(poolState.fee)) * 4e12 / ((2e6 + margin) * (2e6 + margin));

            // And: The tokenOut the other providers sell to the limit, less the rounding.
            uint256 bought;
            {
                uint160 sqrtPriceLimit = uint160(
                    isToken0
                        ? sqrtPrice.fullMulDivUp(1e18, 1e18 + margin * 5e11)
                        : sqrtPrice.fullMulDiv(1e18 + margin * 5e11, 1e18)
                );
                sqrtPriceLimit = isToken0 ? sqrtPriceLimit + 1 : sqrtPriceLimit - 1;
                bought = isToken0
                    ? SqrtPriceMath.getAmount1Delta(sqrtPriceLimit, uint160(sqrtPrice), poolState.liquidityPool, false)
                    : SqrtPriceMath.getAmount0Delta(uint160(sqrtPrice), sqrtPriceLimit, poolState.liquidityPool, false);
                int256 ticks = int256(TickMath.getTickAtSqrtPrice(sqrtPriceLimit)) - poolState.tickCurrent;
                bought = bought.zeroFloorSub(
                    (isToken0 ? sqrtPrice.divUp(1 << 96) : uint256(1 << 96).divUp(sqrtPrice)) + 3 + 2
                        * (uint256(ticks < 0 ? -ticks : ticks) / uint256(int256(poolState.tickSpacing)) / 256 + 5) + 4
                        + (isToken0 ? 0 : 3 * uint256(1 << 96).divUp(sqrtPrice).divUp(sqrtPrice * sqrtPrice >> 96) + 4)
                );
            }

            // And: A tokenOut buffer whose half covers the leg, a step and rounding.
            {
                uint256 liquidity = uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked;
                uint256 needOut = (2e6
                        * ((isToken0 ? sqrtPrice.divUp(1 << 96) : uint256(1 << 96).divUp(sqrtPrice))
                            + 3
                            + (isToken0 ? liquidity >> 96 : liquidity.fullMulDivUp(1 << 96, sqrtPrice * sqrtPrice))))
                    .divUp(margin) + 1 + leg;
                // And: Where the depth to the limit buys under that, a hole.
                vm.assume(bought.fullMulDiv(retained, 4e6) > needOut + 1);
                leastOut = (needOut + 1).fullMulDivUp(4e6, retained) + 2;
            }
            givenValidCoreState(
                coreState, poolState, range, coreState.supply, isToken0 ? 0 : leastOut, isToken0 ? leastOut : 0
            );

            // And: The least shares the entry takes, a share below a quarter margin.
            {
                uint256 supply = coreState.supply;
                uint256 need = (isToken0 ? coreState.buffer1 : coreState.buffer0) + 4;
                if (!isToken0) need += 3 * need.divUp(sqrtPrice * sqrtPrice >> 96) + 1;
                shares = FixedPointMathLib.min(supply / 2, bought.fullMulDiv(supply, need)).fullMulDiv(retained, 2e6);
            }
        }
        // And: Where that buy is worth under a share, a hole no bound expresses.
        vm.assume(shares.fullMulDiv(margin, 4e6) > 0);

        // And: A tokenIn buffer whose leg in those shares covers both roundings.
        uint256 needIn;
        {
            uint256 value = (2e6
                * (((uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked) >> 96)
                    + 1
                    + 4
                    * (token0ToToken1(sqrtPrice, 1) + 1)))
            .divUp(margin) + 1;
            needIn = FixedPointMathLib.max(
                (2e6 * (isToken0 ? uint256(1 << 96).divUp(sqrtPrice) + 3 : sqrtPrice.divUp(1 << 96) + 3)).divUp(margin)
                + 1,
                isToken0 ? value.fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice) + 1 : value
            );
        }
        uint256 least = (needIn + 1).fullMulDivUp(coreState.supply, shares) + 2;
        // And: Where that leg outgrows an amount, a hole no bound expresses.
        vm.assume(least <= Constants.MAX_FUZZED_AMOUNT / 4);
        givenValidCoreState(
            coreState, poolState, range, coreState.supply, isToken0 ? least : leastOut, isToken0 ? leastOut : least
        );
    }

    function givenValidDustState(
        CoreState memory coreState,
        PoolState memory poolState,
        RangeState memory range,
        bool dustIsToken0,
        uint256 leg,
        int24 gap
    ) internal view {
        // And: A range at least the gap beside spot, holding none of the dust token.
        int24 tickSpacing = poolState.tickSpacing;
        int24 edge = bandTick(tickSpacing) / tickSpacing - 1;
        int24 tick = dustIsToken0 ? poolState.tickCurrent - gap : poolState.tickCurrent + gap;
        int24 units = tick / tickSpacing;
        if (units * tickSpacing > tick) --units;
        if (dustIsToken0) {
            range.tickUpper = int24(bound(range.tickUpper / tickSpacing, -edge + 1, units)) * tickSpacing;
            range.tickLower =
                int24(bound(range.tickLower / tickSpacing, -edge, range.tickUpper / tickSpacing - 1)) * tickSpacing;
        } else {
            range.tickLower = int24(bound(range.tickLower / tickSpacing, units + 1, edge - 1)) * tickSpacing;
            range.tickUpper =
                int24(bound(range.tickUpper / tickSpacing, range.tickLower / tickSpacing + 1, edge)) * tickSpacing;
        }

        // And: Legs of up to a quarter of the room, each worth a token1 wei rounded down.
        uint256 floor;
        {
            uint256 sqrtPrice = sqrtPriceX96(pool);
            uint256 lower = TickMath.getSqrtPriceAtTick(range.tickLower);
            uint256 upper = TickMath.getSqrtPriceAtTick(range.tickUpper);
            floor = dustIsToken0
                ? uint256(1 << 96).divUp(upper - lower)
                : uint256(1 << 192)
                    .divUp(sqrtPrice * sqrtPrice)
                    .fullMulDivUp(lower, upper - lower)
                    .fullMulDivUp(upper, 1 << 96);
        }
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity =
            uint128(bound(range.liquidity, FixedPointMathLib.max(Constants.MIN_FUZZED_LIQUIDITY, floor), free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, free / 4 + 1 - floor));
        if (range.liquidityStaked != 0) range.liquidityStaked += uint128(floor - 1);

        // And: The leg as the core's whole holding of the dust token.
        if (dustIsToken0) coreState.buffer0 = leg;
        else coreState.buffer1 = leg;
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
    }

    function givenValidCoreStateAboveTheExitRounding(
        CoreState memory coreState,
        PoolState memory poolState,
        RangeState memory range,
        bool isToken0
    ) internal view {
        // And: An asset buffer worth twice the dead shares and the sale's rounding.
        uint256 sqrtPrice = poolState.sqrtPrice;
        uint256 worth = FixedPointMathLib.max(
            4e4
                * (((uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked) >> 96)
                    + 1
                    + 4
                    * (token0ToToken1(sqrtPrice, 1) + 1)),
            2 * Constants.DEAD_SHARES
        );
        worth = isToken0 ? worth.fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice) : worth;
        givenValidCoreState(coreState, poolState, range, coreState.supply, isToken0 ? worth : 0, isToken0 ? 0 : worth);

        // And: A supply from twice the dead shares, a share's sale within the margin.
        uint256 depth = isToken0
            ? SqrtPriceMath.getAmount1Delta(
                uint160(sqrtPrice), uint160(sqrtPrice.fullMulDiv(1e6 + 25, 1e6)), poolState.liquidityPool, false
            )
            : SqrtPriceMath.getAmount0Delta(
                uint160(sqrtPrice.fullMulDivUp(1e6, 1e6 + 25)), uint160(sqrtPrice), poolState.liquidityPool, false
            );
        uint256 floor = FixedPointMathLib.max(
            2 * Constants.DEAD_SHARES, (isToken0 ? coreState.buffer1 : coreState.buffer0).divUp(depth)
        );
        uint256 ceiling = FixedPointMathLib.min(
            coreState.buffer1 + token0ToToken1(sqrtPrice, coreState.buffer0), Constants.MAX_FUZZED_AMOUNT
        );
        // And: Where that floor outgrows the value, a hole no bound expresses.
        vm.assume(floor <= ceiling);
        givenValidCoreState(coreState, poolState, range, floor, isToken0 ? worth : 0, isToken0 ? 0 : worth);
    }

    function givenValidRedeemWithinThePoolDepth(bool isToken0, uint256 shares, uint128 liquidityPool) internal view {
        // And: Where the pool buys under the redeem's non-asset to the band edge, a hole.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        (uint256 released0, uint256 released1,) = almCore.getUnstakedPositions();
        (released0, released1) = (released0 + almCore.bufferAmount0(), released1 + almCore.bufferAmount1());
        for (uint256 i; i < almCore.getRangesLength(); ++i) {
            Range memory staged = almCore.getRange(i);
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPrice,
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            (released0, released1) = (released0 + amount0, released1 + amount1);
        }
        uint160 edge =
            TickMath.getSqrtPriceAtTick(isToken0 ? bandTick(pool.tickSpacing()) : -bandTick(pool.tickSpacing()));
        vm.assume(
            (isToken0 ? released1 : released0).fullMulDivUp(shares, almCore.totalSupply())
                <= (isToken0
                        ? SqrtPriceMath.getAmount1Delta(sqrtPrice, edge, liquidityPool, false)
                        : SqrtPriceMath.getAmount0Delta(edge, sqrtPrice, liquidityPool, false))
        );
    }

    /* //////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function givenValidMaxSwapCost(uint256 maxSwapCostBps, uint256 fee) internal pure returns (uint256 bounded) {
        // And: A max swap cost above the pool's fee and below the whole value.
        bounded = bound(maxSwapCostBps, fee / 100 + 1, ConfigLib.BPS_DENOMINATOR - 1);
    }

    function bandTicks(PoolState memory poolState, uint256 maxSwapCostBps) internal pure returns (int24 ticks) {
        // The ticks the max swap cost's band spans from spot, and one for the rounding.
        uint256 scale = 1e18 + (maxSwapCostBps * 100 - poolState.fee) * 5e11;
        uint160 edge = uint160(poolState.sqrtPrice.fullMulDivUp(scale, 1e18));
        ticks = TickMath.getTickAtSqrtPrice(edge) - poolState.tickCurrent + 1;
    }

    function setUncapped() internal {
        vm.startPrank(factory);
        almCore.setTotalCap(type(uint128).max);
        almCore.setPerUserCap(type(uint128).max);
        vm.stopPrank();
    }

    function setMaxSwapCost(uint256 maxSwapCostBps) internal {
        (uint256 maxShortfallBps, uint256 minPlanInterval) = (almCore.maxShortfallBps_(), almCore.minPlanInterval_());
        vm.prank(factory);
        almCore.setPlanLimits(uint16(maxShortfallBps), uint16(maxSwapCostBps), uint32(minPlanInterval));
    }

    function setPerUserCapAbovePendingShares(address receiver, uint256 pending, uint256 room) internal {
        almCore.setPendingShares(receiver, bound(pending, 1, type(uint96).max));
        uint256 cap = almCore.balanceOf(receiver) + almCore.pendingShares_(receiver) + room;
        vm.prank(factory);
        almCore.setPerUserCap(cap);
    }

    function fundDeposit(ALMVaultSync vault, uint256 assets, uint256 least, uint256 most)
        internal
        returns (uint256 bounded)
    {
        // And: A funded deposit to maxDeposit, its legs covering a share and rounding.
        bool isToken0 = vault.asset() == address(token0);
        uint160 sqrtPrice = sqrtPriceX96(pool);
        uint128 liquidity = pool.liquidity();
        most = FixedPointMathLib.min(most, IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress));
        uint256 legIn;
        uint256 legOut;
        {
            (uint256 cost0, uint256 cost1,) = almCore.getUnstakedPositions();
            (cost0, cost1) = (cost0 + almCore.bufferAmount0(), cost1 + almCore.bufferAmount1());
            for (uint256 i; i < almCore.getRangesLength(); ++i) {
                Range memory staged = almCore.getRange(i);
                (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                    sqrtPrice,
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                (cost0, cost1) = (cost0 + amount0, cost1 + amount1);
                if (staged.tickLower <= currentTick(pool) && currentTick(pool) < staged.tickUpper) {
                    liquidity -= positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity;
                }
            }
            legIn = almCore.getRangesLength() * (uint256(1 << 96).divUp(sqrtPrice) + 2) + 4
                + cost0.divUp(almCore.totalSupply()) + uint256(liquidity).fullMulDivUp(1 << 96, uint256(sqrtPrice) ** 2)
                + (isToken0 ? most >> 64 : (most >> 64).fullMulDivUp(1 << 192, uint256(sqrtPrice) ** 2));
            legOut = almCore.getRangesLength() * (uint256(sqrtPrice).divUp(1 << 96) + 2) + 4
                + cost1.divUp(almCore.totalSupply()) + (liquidity >> 96)
                + (isToken0 ? (most >> 64).fullMulDivUp(uint256(sqrtPrice) ** 2, 1 << 192) : most >> 64);
            if (!isToken0) (legIn, legOut, cost0, cost1) = (legOut, legIn, cost1, cost0);
            if (cost0 == 0) {
                legIn = 0;
            } else if (cost1 == 0) {
                legOut = 0;
            } else {
                (legIn, legOut) =
                (
                    FixedPointMathLib.max(legIn, legOut.fullMulDivUp(cost0, cost1)),
                    FixedPointMathLib.max(legOut, legIn.fullMulDivUp(cost1, cost0))
                );
            }
        }
        if (legOut > 0) {
            uint160 edge =
                TickMath.getSqrtPriceAtTick(isToken0 ? -bandTick(pool.tickSpacing()) : bandTick(pool.tickSpacing()));
            // And: Where the pool sells under that leg to the band edge, a hole.
            vm.assume(
                legOut
                    < (isToken0
                            ? SqrtPriceMath.getAmount1Delta(edge, sqrtPrice, liquidity, false)
                            : SqrtPriceMath.getAmount0Delta(sqrtPrice, edge, liquidity, false))
            );
            uint160 sqrtPriceEnd = SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtPrice, liquidity, legOut, isToken0);
            legIn += (isToken0
                    ? SqrtPriceMath.getAmount0Delta(sqrtPriceEnd, sqrtPrice, liquidity, true)
                    : SqrtPriceMath.getAmount1Delta(sqrtPrice, sqrtPriceEnd, liquidity, true))
            .fullMulDivUp(1e6, 1e6 - pool.fee()) + 1;
        }
        least = FixedPointMathLib.max(least, legIn + 1);
        // And: Where maxDeposit is under those legs, a hole no bound expresses.
        vm.assume(least <= most);
        bounded = bound(assets, least, most);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), bounded, address(vault));
    }

    function holdingsValue(bool isToken0) internal view returns (uint256 value) {
        uint256 sqrtPrice = sqrtPriceX96(pool);
        (uint256 amount0, uint256 amount1,) = almCore.getUnstakedPositions();
        (amount0, amount1) = (amount0 + almCore.bufferAmount0(), amount1 + almCore.bufferAmount1());
        for (uint256 i; i < almCore.getRangesLength(); ++i) {
            Range memory staged = almCore.getRange(i);
            (uint256 range0, uint256 range1) = amountsRoundedUp(
                uint160(sqrtPrice),
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            (amount0, amount1) = (amount0 + range0, amount1 + range1);
        }
        value = isToken0
            ? amount0 + amount1.fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice)
            : amount1 + amount0.fullMulDivUp(sqrtPrice * sqrtPrice, 1 << 192);
    }

    function depositAtThePreview(ALMVaultSync vault, uint256 assets) internal returns (uint256 shares) {
        // The funded caller deposits into the token0 vault at the preview as its minimum.
        uint256 balance0 = token0.balanceOf(users.unprivilegedAddress);
        uint256 swapIn;
        uint256 tolerance;
        {
            uint256 quoted = vault.previewDeposit(assets);
            uint256 balance1 = token1.balanceOf(address(vault));
            uint256 held = heldOut(true);
            uint256 supply = almCore.totalSupply();
            vm.recordLogs();
            vm.prank(users.unprivilegedAddress);
            shares = vault.deposit(assets, users.unprivilegedAddress, quoted);
            assertEq(shares, quoted);

            // The vault kept at most the stranded token1 of the deposit's buy.
            uint256 bought;
            (swapIn, bought) = swapAmounts(address(vault));
            tolerance = strandedOut(true, held, supply, shares, bought);
            assertLe(token1.balanceOf(address(vault)) - balance1, tolerance);
        }

        // The payment lost at most the fee on the swap's input, a share, the rounding and that token1.
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 spent = balance0 - token0.balanceOf(users.unprivilegedAddress);
        uint256 value = holdingsValue(true);
        tolerance = tolerance.fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice) + value.divUp(almCore.totalSupply())
            + uint256(1 << 96).divUp(sqrtPrice) + 3;
        assertLe(
            spent, value.fullMulDiv(shares, almCore.totalSupply()) + swapIn.fullMulDivUp(pool.fee(), 1e6) + tolerance
        );
    }

    function heldOut(bool isToken0) internal view returns (uint256 held) {
        // The non-asset the core holds at spot: its ranges rounded up, its buffer and its fees.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
        held = isToken0 ? fees1 + almCore.bufferAmount1() : fees0 + almCore.bufferAmount0();
        for (uint256 i; i < almCore.getRangesLength(); ++i) {
            Range memory staged = almCore.getRange(i);
            (uint256 amount0, uint256 amount1) = CLMath.getAmountsForLiquidityRoundingUp(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(staged.tickLower),
                TickMath.getSqrtPriceAtTick(staged.tickUpper),
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            held += isToken0 ? amount1 : amount0;
        }
    }

    function swapAmounts(address vault) internal view returns (uint256 amountIn, uint256 amountOut) {
        // The vault's swap from the recorded transfers: what it paid the pool and what it got back.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 3 || logs[i].topics[0] != keccak256("Transfer(address,address,uint256)")) {
                continue;
            }
            address from = address(uint160(uint256(logs[i].topics[1])));
            address to = address(uint160(uint256(logs[i].topics[2])));
            if (from == vault && to == address(pool)) amountIn += abi.decode(logs[i].data, (uint256));
            else if (from == address(pool) && to == vault) amountOut += abi.decode(logs[i].data, (uint256));
        }
    }

    function strandedOut(bool isToken0, uint256 held, uint256 supply, uint256 shares, uint256 bought)
        internal
        view
        returns (uint256 most)
    {
        // Twice the rounding at the end price, a share of the holding, a wei per range and share.
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 ranges = almCore.getRangesLength();
        most = 2 * (ranges * ((isToken0 ? sqrtPrice.divUp(1 << 96) : uint256(1 << 96).divUp(sqrtPrice)) + 2) + 1)
            + held.divUp(supply) + ranges * (shares.divUp(supply) + 1);

        // And: The buy over the least token0 divisor at the end price of the ranges holding token0.
        uint256 ceilings;
        for (uint256 i; i < ranges; ++i) {
            Range memory staged = almCore.getRange(i);
            uint256 upper = TickMath.getSqrtPriceAtTick(staged.tickUpper);
            if (sqrtPrice >= upper) continue;
            uint256 divisor =
                FixedPointMathLib.max(sqrtPrice, TickMath.getSqrtPriceAtTick(staged.tickLower)).fullMulDivN(upper, 96);
            ceilings = FixedPointMathLib.max(ceilings, bought / divisor);
        }
        most += ceilings;
    }

    function roomValue(bool isToken0) internal view returns (uint256 most) {
        // The value growing the range to its ticks' limit or a holding to an amount.
        Range memory staged = almCore.getRange(0);
        uint256 liquidity = uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity;
        uint256 room;
        {
            (uint128 lower,,,,,,,,,) = pool.ticks(staged.tickLower);
            (uint128 upper,,,,,,,,,) = pool.ticks(staged.tickUpper);
            room = tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) - FixedPointMathLib.max(lower, upper);
        }
        uint256 total;
        {
            (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
            (uint256 amount0, uint256 amount1) =
                amountsRoundedUp(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, uint128(liquidity));
            total = FixedPointMathLib.max(
                fees0 + amount0 + almCore.bufferAmount0(), fees1 + amount1 + almCore.bufferAmount1()
            );
        }
        most = room * total < (Constants.MAX_FUZZED_AMOUNT - total) * liquidity
            ? holdingsValue(isToken0).fullMulDiv(room, liquidity)
            : holdingsValue(isToken0).fullMulDiv(Constants.MAX_FUZZED_AMOUNT - total, total);
    }

    function approveVault(address owner_, ALMVaultSync vault, uint256 shares) internal {
        vm.prank(owner_);
        almCore.approve(address(vault), shares);
    }

    function parkSpotAt(PoolState memory poolState, RangeState memory range, int24 tick) internal {
        parkSpotAt(
            TickMath.getSqrtPriceAtTick(tick),
            poolState.liquidityPool + range.liquidity + range.liquidityStaked,
            poolState.fee
        );
    }

    function parkSpotAt(uint160 target, uint128 liquidity, uint24 fee) internal {
        // And: Spot moved to the price by a sale sized at all liquidity and rounding.
        uint160 sqrtPrice = sqrtPriceX96(pool);
        bool zeroForOne = target < sqrtPrice;
        uint256 steps = 2 * (uint256(int256(TickMath.MAX_TICK)) / 128 + 4);
        uint256 amountIn =
            (zeroForOne
                        ? SqrtPriceMath.getAmount0Delta(target, sqrtPrice, liquidity, true)
                        : SqrtPriceMath.getAmount1Delta(sqrtPrice, target, liquidity, true)) + steps;
        amountIn = amountIn.fullMulDivUp(1e6, 1e6 - fee) + steps;
        (address tokenIn, address tokenOut) =
            zeroForOne ? (pool.token0(), pool.token1()) : (pool.token1(), pool.token0());
        ERC20Mock(tokenIn).mint(users.unprivilegedAddress, amountIn);
        swapAsActor(pool, users.unprivilegedAddress, tokenIn, tokenOut, amountIn, target);
    }

    function mintableWithinDepth(bool isToken0, uint128 liquidityPool) internal view returns (uint256 most) {
        uint160 sqrtPrice = sqrtPriceX96(pool);
        uint256 held = isToken0 ? almCore.bufferAmount1() : almCore.bufferAmount0();
        for (uint256 i; i < almCore.getRangesLength(); ++i) {
            Range memory staged = almCore.getRange(i);
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPrice,
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            held += isToken0 ? amount1 : amount0;
        }
        uint160 edge;
        {
            int24 tickUpper = bandTick(pool.tickSpacing());
            (uint256 bandLower, uint256 bandUpper) =
                CLMath.getBand(almCore.meanSqrtPriceX96_(), almCore.maxSpotFromTwap_());
            edge = isToken0
                ? uint160(FixedPointMathLib.max(TickMath.getSqrtPriceAtTick(-tickUpper), bandLower))
                : uint160(FixedPointMathLib.min(TickMath.getSqrtPriceAtTick(tickUpper), bandUpper));
        }
        uint256 depth = isToken0
            ? SqrtPriceMath.getAmount1Delta(edge, sqrtPrice, liquidityPool, false)
            : SqrtPriceMath.getAmount0Delta(sqrtPrice, edge, liquidityPool, false);
        most = (depth / 2).fullMulDiv(almCore.totalSupply(), held);
    }

    function redeemableWithinSlippage(ALMVaultSync vault) internal view returns (uint256 most) {
        most = almCore.balanceOf(users.steward);
        if (vault.asset() == pool.token0()) {
            uint160 sqrtPrice = sqrtPriceX96(pool);
            int24 tick = currentTick(pool);
            uint256 nonAsset = almCore.bufferAmount1();
            uint160 edge = TickMath.MAX_SQRT_PRICE;
            for (uint256 i; i < almCore.getRangesLength(); ++i) {
                Range memory staged = almCore.getRange(i);
                (, uint256 amount1) = amountsRoundedDown(
                    sqrtPrice,
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                nonAsset += amount1;
                if (positionLiquidity(staged.unstakedTokenId) != 0) {
                    (, uint256 fees1) = positionFees(pool, staged.unstakedTokenId);
                    nonAsset += fees1 - fees1.fullMulDiv(almCore.protocolSwapFeeBps_(), ConfigLib.BPS_DENOMINATOR);
                }
                uint160 lower = TickMath.getSqrtPriceAtTick(staged.tickLower);
                uint160 upper = TickMath.getSqrtPriceAtTick(staged.tickUpper);
                if (staged.tickLower > tick && lower < edge) edge = lower;
                if (staged.tickUpper > tick && upper < edge) edge = upper;
            }
            uint128 liquidity = pool.liquidity();
            uint256 sellable = FixedPointMathLib.min(
                uint256(liquidity)
                    .fullMulDiv(sqrtPrice, 1 << 96)
                    .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, 4 * ConfigLib.BPS_DENOMINATOR),
                SqrtPriceMath.getAmount1Delta(sqrtPrice, edge, liquidity, false)
            );
            most = FixedPointMathLib.min(most, sellable.fullMulDiv(almCore.totalSupply(), nonAsset));
        } else {
            uint160 sqrtPrice = sqrtPriceX96(pool);
            int24 tick = currentTick(pool);
            uint256 nonAsset = almCore.bufferAmount0();
            uint160 edge = TickMath.MIN_SQRT_PRICE;
            for (uint256 i; i < almCore.getRangesLength(); ++i) {
                Range memory staged = almCore.getRange(i);
                (uint256 amount0,) = amountsRoundedDown(
                    sqrtPrice,
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                nonAsset += amount0;
                if (positionLiquidity(staged.unstakedTokenId) != 0) {
                    (uint256 fees0,) = positionFees(pool, staged.unstakedTokenId);
                    nonAsset += fees0 - fees0.fullMulDiv(almCore.protocolSwapFeeBps_(), ConfigLib.BPS_DENOMINATOR);
                }
                uint160 lower = TickMath.getSqrtPriceAtTick(staged.tickLower);
                uint160 upper = TickMath.getSqrtPriceAtTick(staged.tickUpper);
                if (staged.tickLower <= tick && lower > edge) edge = lower;
                if (staged.tickUpper <= tick && upper > edge) edge = upper;
            }
            uint128 liquidity = pool.liquidity();
            uint256 sellable = FixedPointMathLib.min(
                uint256(liquidity)
                    .fullMulDiv(1 << 96, sqrtPrice)
                    .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, 4 * ConfigLib.BPS_DENOMINATOR),
                SqrtPriceMath.getAmount0Delta(edge, sqrtPrice, liquidity, false)
            );
            most = FixedPointMathLib.min(most, sellable.fullMulDiv(almCore.totalSupply(), nonAsset));
        }
    }
}
