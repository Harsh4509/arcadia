/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { DepositOptimizationMath } from "../../../src/vaults/libraries/math/DepositOptimizationMath.sol";
import { DepositOptimizationMathExtension } from "../../utils/extensions/DepositOptimizationMathExtension.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";
import { IMetadexSwapRouter } from "../../utils/fixtures/metadex/interfaces/IMetadexSwapRouter.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { Snapshot, SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { SnapshotLibExtension } from "../../utils/extensions/SnapshotLibExtension.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "deposit" of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract Deposit_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    DepositOptimizationMathExtension internal depositMath;
    SnapshotLibExtension internal snapshotLib;

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
        depositMath = new DepositOptimizationMathExtension();
        snapshotLib = new SnapshotLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_deposit_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: The factory paused it.
        vm.prank(factory);
        vault.setPaused(true);

        // When: Anyone deposits.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.deposit(assets, users.unprivilegedAddress, 0);
    }

    function testFuzz_Revert_deposit_Paused_Plain(PoolState memory poolState, uint256 amount, bool isToken0) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // And: The factory paused it.
        vm.prank(factory);
        vault.setPaused(true);

        // When: Calling the plain deposit().
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.deposit(amount, users.steward);
    }

    function testFuzz_Revert_deposit_ZeroShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot past every position on the side the deposit's swap moves away from.
        parkSpotAt(
            poolState,
            range,
            isToken0
                ? bandTick(poolState.tickSpacing) + poolState.tickSpacing
                : -bandTick(poolState.tickSpacing) - poolState.tickSpacing
        );

        // And: A funded caller.
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits with no bound of its own.
        // Then: It reverts, as the deposit can buy none of the non-asset token.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMCore.ZeroShares.selector);
        vault.deposit(assets, users.unprivilegedAddress, 0);
    }

    function testFuzz_Revert_deposit_ExcessiveInput(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        int24 tick,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot, its asset-side edge over a tick inside the band.
        givenValidRangeState(range, poolState, true);
        if (isToken0) {
            range.tickUpper = int24(
                bound(
                    range.tickUpper / poolState.tickSpacing,
                    (poolState.tickCurrent + poolState.tickSpacing) / poolState.tickSpacing,
                    (bandTick(poolState.tickSpacing) - 2) / poolState.tickSpacing
                )
            ) * poolState.tickSpacing;
        } else {
            range.tickLower = int24(
                bound(
                    range.tickLower / poolState.tickSpacing,
                    (2 - bandTick(poolState.tickSpacing)) / poolState.tickSpacing,
                    (poolState.tickCurrent - poolState.tickSpacing) / poolState.tickSpacing
                )
            ) * poolState.tickSpacing;
        }

        // And: A vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot parked past the range on the asset's side, the TWAP caught up.
        tick = isToken0
            ? int24(bound(tick, range.tickUpper + 1, bandTick(poolState.tickSpacing) - 1))
            : int24(bound(tick, -bandTick(poolState.tickSpacing) + 1, range.tickLower - 1));
        parkSpotAt(poolState, range, tick);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: No asset in the buffer, so the core holds only the other token.
        almCore.setBuffers(isToken0 ? 0 : almCore.bufferAmount0(), isToken0 ? almCore.bufferAmount1() : 0);

        // And: The pool reporting no fee to the vault, its quote leaving out the fee.
        vm.mockCall(address(pool), abi.encodeWithSelector(IMetadexCLPool.beforeSwapFee.selector), abi.encode(uint24(0)));

        // And: A deposit within the range, a 1% sale and the cap, its fee over rounding.
        {
            uint256 least;
            uint256 most;
            {
                uint256 sqrtPrice = sqrtPriceX96(pool);
                uint256 held = isToken0 ? almCore.bufferAmount1() : almCore.bufferAmount0();
                {
                    (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
                    held += isToken0 ? fees1 : fees0;
                }
                {
                    Range memory staged = almCore.getRange(0);
                    (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                        uint160(sqrtPrice),
                        staged.tickLower,
                        staged.tickUpper,
                        positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                    );
                    held += isToken0 ? amount1 : amount0;
                }
                most = FixedPointMathLib.min(
                    (almCore.totalCap_() - almCore.totalSupply()).fullMulDiv(held, almCore.totalSupply()),
                    Constants.MAX_FUZZED_AMOUNT
                );
                most = isToken0
                    ? most.fullMulDiv(1 << 192, sqrtPrice * sqrtPrice)
                    : most.fullMulDiv(sqrtPrice * sqrtPrice, 1 << 192);
                least = held.divUp(almCore.totalSupply()) + 4
                    + (isToken0
                            ? sqrtPrice.divUp(1 << 96) + (uint256(pool.liquidity()) >> 96)
                            : uint256(1 << 96).divUp(sqrtPrice)
                            + uint256(pool.liquidity()).fullMulDivUp(1 << 96, sqrtPrice * sqrtPrice));
                least = (isToken0
                        ? least.fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice)
                        : least.fullMulDivUp(sqrtPrice * sqrtPrice, 1 << 192))
                .fullMulDivUp(ConfigLib.BPS_DENOMINATOR + 2 * Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR);
            }
            {
                uint160 edge = TickMath.getSqrtPriceAtTick(isToken0 ? range.tickUpper : range.tickLower);
                most = FixedPointMathLib.min(
                    most,
                    isToken0
                        ? SqrtPriceMath.getAmount0Delta(edge, sqrtPriceX96(pool), pool.liquidity(), false)
                        : SqrtPriceMath.getAmount1Delta(sqrtPriceX96(pool), edge, pool.liquidity(), false)
                );
            }
            most = FixedPointMathLib.min(
                most,
                (isToken0
                        ? uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPriceX96(pool))
                        : uint256(pool.liquidity()).fullMulDiv(sqrtPriceX96(pool), 1 << 96))
                .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR)
            );
            {
                uint256 rounding =
                    (isToken0
                                ? uint256(pool.liquidity())
                                    .fullMulDivUp(1 << 96, sqrtPriceX96(pool))
                                    .divUp(sqrtPriceX96(pool))
                                : uint256(pool.liquidity()).divUp(1 << 96)) + 2;
                {
                    int256 wordStart = (int256(tick) / poolState.tickSpacing) >> 8;
                    int256 wordEnd = (int256(isToken0 ? range.tickUpper : range.tickLower) / poolState.tickSpacing) >> 8;
                    rounding *= uint256(wordEnd > wordStart ? wordEnd - wordStart : wordStart - wordEnd) + 2;
                }

                // And: The edge margins: u + 6 on the balance, 2n + 4 on the position.
                {
                    uint256 edge = TickMath.getSqrtPriceAtTick(isToken0 ? range.tickUpper : range.tickLower);
                    rounding += (isToken0 ? uint256(1 << 96).divUp(edge) : edge.divUp(1 << 96)) + 12;
                }
                least = FixedPointMathLib.max(least, (rounding + 1).fullMulDivUp(1e6, poolState.fee) + rounding);
            }
            // And: Room where the fee beats the rounding, a hole no bound expresses.
            vm.assume(least <= most);
            assets = bound(assets, least, most);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // And: The vault holding as much again, to pay a buy above the payment.
        ERC20Mock(vault.asset()).mint(address(vault), assets);

        // When: The caller deposits with no bound of its own.
        // Then: It reverts, the buy's fee taking more than the payment.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMVaultSync.ExcessiveInput.selector);
        vault.deposit(assets, users.unprivilegedAddress, 0);
    }

    function testFuzz_Revert_deposit_InsufficientOutput_BeyondTheSwapCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A max swap cost up to 10 bps above the pool's fee.
        maxSwapCostBps = bound(maxSwapCostBps, poolState.fee / 100 + 1, poolState.fee / 100 + 10);

        // And: A seeded vault holding a range, under that cost.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        givenValidCoreStateAboveTheRounding(
            coreState, poolState, range, isToken0, maxSwapCostBps * 100 - poolState.fee, 0
        );
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: A deposit of over twice maxDeposit, worth at most the room and half depth.
        {
            uint256 floor = 2 * IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress) + 1;
            uint256 ceiling = FixedPointMathLib.min(
                    almCore.totalCap_() - almCore.totalSupply(), mintableWithinDepth(isToken0, poolState.liquidityPool)
                )
                .fullMulDiv(holdingsValue(isToken0), almCore.totalSupply());
            // And: Room above twice maxDeposit, a hole no bound expresses.
            vm.assume(floor <= ceiling);
            assets = bound(assets, floor, ceiling);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits through the plain signature.
        // Then: It reverts, the swap stopping at the band's edge short of the need.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.deposit(assets, users.unprivilegedAddress);
    }

    function testFuzz_Revert_deposit_InsufficientOutput(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A funded caller asking for twice the shares the deposit is worth at spot.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        uint256 unreachable;
        {
            Range memory staged = almCore.getRange(0);
            (uint256 total0, uint256 total1) = amountsRoundedDown(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            uint256 total = total1 + almCore.bufferAmount1()
                + CLMath.convert(sqrtPriceX96(pool), true, total0 + almCore.bufferAmount0(), false);
            uint256 value = isToken0 ? CLMath.convert(sqrtPriceX96(pool), true, assets, false) : assets;
            unreachable = 2 * value.fullMulDiv(almCore.totalSupply(), total) + 1;
        }

        // When: The caller deposits under that bound.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.deposit(assets, users.unprivilegedAddress, unreachable);
    }

    function testFuzz_Success_deposit_AfterADonationMintsThePreview(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 donation,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range around the price.
        givenValidRangeState(range, poolState, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A third party added liquidity to the range's position.
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));
        assertGt(positionLiquidity(range.unstakedTokenId), range.liquidity);

        // And: A funded caller, and the shares its deposit previews.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        uint256 preview = vault.previewDeposit(assets);

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress);

        // Then: It minted the preview.
        assertEq(shares, preview);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_deposit_MintsThePreviewAtTheVaultsOwnFee(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 vaultFee,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price, and a fee of at least 0.01%.
        givenValidPoolState(poolState);
        poolState.fee = uint24(bound(poolState.fee, 100, Constants.MAX_POOL_FEE));
        setPoolState(poolState, false);

        // And: A seeded vault holding a range around the price.
        givenValidRangeState(range, poolState, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A swap hook charging the vault at most half the fee others pay.
        vaultFee = bound(vaultFee, 1, poolState.fee / 2);
        {
            address hook = makeAddr("swapHook");
            vm.etch(hook, hex"60206000f3");
            vm.mockCall(
                hook,
                abi.encodePacked(
                    bytes4(
                        keccak256("getBeforeSwapFee(address,(address,address,bool,int256,uint160,bytes,uint160,int24))")
                    ),
                    abi.encode(address(pool), uint256(0x40), address(vault))
                ),
                abi.encode(uint24(vaultFee))
            );
            vm.mockCall(
                hook,
                abi.encodePacked(
                    bytes4(keccak256("beforeSwap((address,address,bool,int256,uint160,bytes,uint160,int24))")),
                    abi.encode(uint256(0x20), address(vault))
                ),
                abi.encode(uint24(vaultFee))
            );
            (address[] memory pools, address[] memory hooks) = (new address[](1), new address[](1));
            (pools[0], hooks[0]) = (address(pool), hook);
            CL_FACTORY.setPoolSwapHook(pools, hooks);
        }
        IMetadexCLPool.SwapParams memory swapParams;
        swapParams.caller = address(vault);
        assertEq(IMetadexCLPool(address(pool)).beforeSwapFee(swapParams), vaultFee);
        assertEq(pool.fee(), poolState.fee);

        // And: A funded caller, and the shares its deposit previews.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        uint256 preview = vault.previewDeposit(assets);

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress);

        // Then: It minted the preview.
        assertEq(shares, preview);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_deposit_MinSharesEqualToTheShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A funded caller, and the shares its deposit mints.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        uint256 snapshot = vm.snapshotState();
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, 0);
        vm.revertToState(snapshot);

        // When: The caller deposits with a bound of exactly those shares.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress, shares);

        // Then: It minted the shares to the caller.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_deposit_RefundsOnlyInTheAsset(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A caller holding the asset and nothing of the non-asset token.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        ERC20Mock other = isToken0 ? token1 : token0;
        assertEq(other.balanceOf(users.unprivilegedAddress), 0);

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);

        // Then: Nothing of the non-asset token came back.
        assertEq(other.balanceOf(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_deposit_MinSharesSkipsTheValueLossCheck(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A max swap cost above the pool's fee.
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);

        // And: A seeded vault holding a range, under that cost.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: Buffers whose half max deposit buys a leg whose fee beats the rounding.
        {
            uint256 leg = uint256(4e6).divUp(poolState.fee);
            leg = isToken0
                ? leg.fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192)
                : leg.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
            givenValidCoreStateAboveTheRounding(
                coreState, poolState, range, isToken0, maxSwapCostBps * 100 - poolState.fee, 2 * leg + 2
            );
        }
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: A deposit of half to all of maxDeposit.
        assets = fundDeposit(
            vault,
            assets,
            IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress) / 2 + 1,
            type(uint256).max
        );
        uint256 supplyBefore = almCore.totalSupply();

        // And: A max swap cost of zero.
        setMaxSwapCost(0);

        // When: The caller deposits with a bound of one share.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, 1);

        // Then: It minted the shares to the caller.
        assertEq(almCore.totalSupply(), supplyBefore + shares);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_deposit_KeepsAFewWeiOfTheNonAsset(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, in a pool charging a fuzzed swap fee.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A deposit of at least 2^-60 of the pool's depth.
        assets = fundDeposit(
            vault,
            assets,
            isToken0
                ? (uint256(pool.liquidity()) >> 60).fullMulDivUp(1 << 96, sqrtPriceX96(pool))
                : (uint256(pool.liquidity()) >> 60).fullMulDivUp(sqrtPriceX96(pool), 1 << 96),
            type(uint256).max
        );
        uint256 balance = (isToken0 ? token1 : token0).balanceOf(address(vault));
        uint256 held = heldOut(isToken0);
        uint256 supply = almCore.totalSupply();

        // When: The caller deposits.
        vm.recordLogs();
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress);

        // Then: The vault kept at most the stranded non-asset of the deposit's buy.
        (, uint256 bought) = swapAmounts(address(vault));
        assertLe(
            (isToken0 ? token1 : token0).balanceOf(address(vault)) - balance,
            strandedOut(isToken0, held, supply, shares, bought)
        );
    }

    function testFuzz_Success_deposit_MintsItsPreviewWithUncountedFees(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 buffer,
        uint256 trade,
        uint256 assets,
        uint16 protocolSwapFeeBps,
        bool aroundSpot,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price, the protocol taking swap fees.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.prank(factory);
        almCore.setProtocolFees(0, uint16(bound(protocolSwapFeeBps, 0, Constants.MAX_FEE_BPS)), users.feeRecipient);

        // And: An uncapped vault holding a range anywhere, a sixteenth of its room.
        givenValidRangeState(range, poolState, aroundSpot);
        range.liquidity = uint128(
            FixedPointMathLib.max(range.liquidity / Constants.RANGE_ROOM_DIVISOR, Constants.MIN_FUZZED_LIQUIDITY)
        );
        range.liquidityStaked /= Constants.RANGE_ROOM_DIVISOR;
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        setUncapped();

        // And: The asset's buffer from nothing to what it held.
        {
            ERC20Mock asset = ERC20Mock(vault.asset());
            uint256 held = isToken0 ? almCore.bufferAmount0() : almCore.bufferAmount1();
            buffer = bound(buffer, 0, held);
            almCore.setBuffers(isToken0 ? buffer : almCore.bufferAmount0(), isToken0 ? almCore.bufferAmount1() : buffer);
            deal(address(asset), address(almCore), asset.balanceOf(address(almCore)) - (held - buffer));
        }

        roundTrip(isToken0, trade);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: A deposit within maxDeposit, the pool's slippage and the core's room.
        assets = fundDeposit(
            vault,
            assets,
            0,
            FixedPointMathLib.min(
                (isToken0
                        ? uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPriceX96(pool))
                        : uint256(pool.liquidity()).fullMulDiv(sqrtPriceX96(pool), 1 << 96))
                .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR),
                roomValue(isToken0)
            )
        );

        uint256 supplyBefore;
        uint256 balanceOut;
        uint256 heldBefore;
        uint256 shares;
        {
            // And: Its preview.
            uint256 quoted = vault.previewDeposit(assets);
            supplyBefore = almCore.totalSupply();
            uint256 balanceIn = ERC20Mock(vault.asset()).balanceOf(address(vault));
            balanceOut = (isToken0 ? token1 : token0).balanceOf(address(vault));
            heldBefore = heldOut(isToken0);

            // When: The caller deposits with the preview as its minimum.
            vm.recordLogs();
            vm.prank(users.unprivilegedAddress);
            shares = vault.deposit(assets, users.unprivilegedAddress, quoted);

            // Then: It minted the preview.
            assertEq(shares, quoted);
            assertEq(almCore.totalSupply(), supplyBefore + shares);

            // And: The core pulled no more than the vault held, kept none.
            assertEq(ERC20Mock(vault.asset()).balanceOf(address(vault)), balanceIn);
        }

        // And: The vault kept at most the stranded non-asset of the deposit's buy.
        (, uint256 bought) = swapAmounts(address(vault));
        assertLe(
            (isToken0 ? token1 : token0).balanceOf(address(vault)) - balanceOut,
            strandedOut(isToken0, heldBefore, supplyBefore, shares, bought)
        );
    }

    function testFuzz_Success_deposit_MaxDepositOfATinyRoom(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 room,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range in the pool's virtual non-asset, supply to 1e9, room of 2 to 100.
        givenValidRangeState(range, poolState, false);
        uint256 roundingIn;
        uint256 roundingOut;
        {
            uint256 sqrtPrice = sqrtPriceX96(pool);
            (roundingIn, roundingOut) = (uint256(1 << 96).divUp(sqrtPrice) + 3, sqrtPrice.divUp(1 << 96) + 3);
            if (!isToken0) (roundingIn, roundingOut) = (roundingOut, roundingIn);
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                uint160(sqrtPrice), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 amountOut = isToken0 ? amount1 : amount0;
            uint256 reserve = isToken0
                ? uint256(pool.liquidity()).fullMulDiv(sqrtPrice, 1 << 96)
                : uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPrice);
            if (amountOut > reserve) {
                range.liquidity = uint128(uint256(range.liquidity).fullMulDiv(reserve, amountOut));
                range.liquidityStaked = uint128(uint256(range.liquidityStaked).fullMulDiv(reserve, amountOut));
            }
        }
        coreState.supply = bound(coreState.supply, almCore.DEAD_SHARES_(), Constants.MAX_TINY_ROOM_SUPPLY);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        room = bound(room, Constants.MIN_TINY_ROOM, Constants.MAX_TINY_ROOM);

        // And: The room's legs at 5/2 of their losses, fee under a tenth.
        {
            uint256 leastOut;
            uint256 leastIn;
            {
                uint256 sqrtPrice = sqrtPriceX96(pool);
                uint256 unit =
                    (isToken0 ? uint256(pool.liquidity()) : CLMath.convert(sqrtPrice, false, pool.liquidity(), false))
                        >> 96;
                leastOut = (5 * (unit + roundingOut + 4)).divUp(2) * (coreState.supply / room + 1);
                leastIn = (5 * (roundingIn + 7)).divUp(2) * (coreState.supply / room + 1);
            }
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            if (isToken0) {
                coreState.buffer1 = amount1 + leastOut;
                givenValidCoreState(coreState, poolState, range, coreState.supply, leastIn, leastOut);
            } else {
                coreState.buffer0 = amount0 + leastOut;
                givenValidCoreState(coreState, poolState, range, coreState.supply, leastOut, leastIn);
            }
        }

        // And: A seeded vault with that per user cap room.
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        vm.prank(factory);
        almCore.setPerUserCap(room);

        // And: The most a deposit takes, and a caller holding it.
        uint256 assets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);

        // And: A deposit that mints, the ZeroShares limit (audit doc 6.4) excluded.
        vm.assume(vault.previewDeposit(assets) > 0);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));
        ERC20Mock asset = ERC20Mock(vault.asset());
        uint256 poolBefore = asset.balanceOf(address(pool));
        uint256 coreBefore = asset.balanceOf(address(almCore));

        // When: The caller deposits it through the plain signature.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress);

        // Then: It minted at least a share to the caller.
        assertGe(shares, 1);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);

        // And: The caller got back the asset the pool and the core did not take.
        assertEq(
            asset.balanceOf(users.unprivilegedAddress),
            assets - (asset.balanceOf(address(pool)) - poolBefore) - (asset.balanceOf(address(almCore)) - coreBefore)
        );
    }

    function testFuzz_Success_deposit_ZeroMintsNothing(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        uint256 supplyBefore = almCore.totalSupply();

        // When: The caller deposits nothing through the plain signature.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(0, users.unprivilegedAddress);

        // Then: Nothing was minted.
        assertEq(shares, 0);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
        assertEq(almCore.totalSupply(), supplyBefore);
    }

    function testFuzz_Success_deposit_MintsToTheReceiver(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A funded caller.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        uint256 supplyBefore = almCore.totalSupply();

        // When: The caller deposits to someone else.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, controller);

        // Then: The receiver holds exactly what was minted, and the caller none of it.
        assertEq(almCore.balanceOf(controller), shares);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
        assertEq(almCore.totalSupply(), supplyBefore + shares);

        // And: The vault kept no share of its own.
        assertEq(almCore.balanceOf(address(vault)), 0);
    }

    function testFuzz_Success_deposit_SpendsOnlyWhatItTook(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A funded caller.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        ERC20Mock asset = ERC20Mock(vault.asset());
        uint256 poolBefore = asset.balanceOf(address(pool));
        uint256 coreBefore = asset.balanceOf(address(almCore));

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);

        // Then: The caller got back exactly the asset the pool and the core did not take.
        assertEq(
            asset.balanceOf(users.unprivilegedAddress),
            assets - (asset.balanceOf(address(pool)) - poolBefore) - (asset.balanceOf(address(almCore)) - coreBefore)
        );

        // And: The vault kept nothing of the asset for itself.
        assertEq(asset.balanceOf(address(vault)), 0);
    }

    function testFuzz_Success_deposit_SwapsIntoTheNearestRange(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 foreignLiquidity,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot, its upper tick three spacings inside the band.
        range.tickUpper = int24(
            bound(
                range.tickUpper / poolState.tickSpacing,
                (poolState.tickCurrent + poolState.tickSpacing) / poolState.tickSpacing,
                bandTick(poolState.tickSpacing) / poolState.tickSpacing - 3
            )
        ) * poolState.tickSpacing;
        givenValidRangeState(range, poolState, true);

        // And: A token0 vault seeded with it, and no token0 in the buffer.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        almCore.setBuffers(0, almCore.bufferAmount1());

        // And: Spot two spacings above the range in the band, the TWAP caught up.
        parkSpotAt(poolState, range, range.tickUpper + 2 * poolState.tickSpacing);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        uint160 upperEdge = TickMath.getSqrtPriceAtTick(range.tickUpper);

        // And: A foreign position from the range's edge past spot.
        foreignLiquidity = uint128(
            bound(
                foreignLiquidity,
                Constants.MIN_FUZZED_LIQUIDITY,
                FixedPointMathLib.max(pool.liquidity(), Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPriceX96(pool), range.tickUpper, range.tickUpper + 4 * poolState.tickSpacing, foreignLiquidity
            );
            mintPosition(
                pool,
                users.liquidityProvider,
                range.tickUpper,
                range.tickUpper + 4 * poolState.tickSpacing,
                amount0,
                amount1
            );
        }

        // And: A deposit whose balance a spacing into the range beats the core's ratio.
        uint256 least;
        {
            uint160 inside = TickMath.getSqrtPriceAtTick(range.tickUpper - poolState.tickSpacing);
            uint256 total0;
            uint256 total1;
            {
                Range memory staged = almCore.getRange(0);
                (total0, total1) = amountsRoundedUp(
                    inside,
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
                (total0, total1) = (total0 + fees0, total1 + fees1 + almCore.bufferAmount1());
            }
            {
                uint256 toInside;
                uint256 boughtInside;
                {
                    Range memory staged = almCore.getRange(0);
                    uint128 liquidityInside = pool.liquidity() - foreignLiquidity
                        + positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity;
                    toInside = SqrtPriceMath.getAmount0Delta(upperEdge, sqrtPriceX96(pool), pool.liquidity(), true)
                        + SqrtPriceMath.getAmount0Delta(inside, upperEdge, liquidityInside, true);
                    boughtInside = SqrtPriceMath.getAmount1Delta(inside, upperEdge, liquidityInside, false);
                    boughtInside += SqrtPriceMath.getAmount1Delta(
                        upperEdge, sqrtPriceX96(pool), pool.liquidity(), false
                    );
                }
                total0 += toInside.fullMulDivUp(poolState.fee, 1e6 - poolState.fee);
                least = toInside.fullMulDivUp(1e6, 1e6 - poolState.fee);
                least += boughtInside.fullMulDivUp(total0, total1) + 2;
            }

            // And: A token0 leg there covering the mint's rounding and a share.
            uint256 rounding = uint256(1 << 96).divUp(inside) + 3 + total0.divUp(almCore.totalSupply());
            rounding = rounding.fullMulDivUp(total0 + total1.fullMulDivUp(1 << 192, uint256(inside) * inside), total0);
            rounding = rounding.fullMulDivUp(1e6, 1e6 - poolState.fee);
            least = FixedPointMathLib.max(least, rounding);
        }
        assets = fundDeposit(
            vault,
            assets,
            least,
            CLMath.convert(sqrtPriceX96(pool), false, Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1(), false)
        );
        uint256 supplyBefore = almCore.totalSupply();

        // When: The caller deposits with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, 0);

        // Then: The deposit's swap moved spot into the range.
        assertLe(sqrtPriceX96(pool), upperEdge);

        // And: It minted the shares.
        assertEq(almCore.totalSupply(), supplyBefore + shares);
    }

    function testFuzz_Success_deposit_SellsAllAcrossATick(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 foreignLiquidity,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot, a spacing and over a tick inside the band.
        givenValidRangeState(range, poolState, true);
        range.tickUpper = int24(
            bound(
                range.tickUpper / poolState.tickSpacing,
                (poolState.tickCurrent + poolState.tickSpacing) / poolState.tickSpacing,
                (bandTick(poolState.tickSpacing) - poolState.tickSpacing - 2) / poolState.tickSpacing
            )
        ) * poolState.tickSpacing;

        // And: A token0 vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot a tick above a spacing over the range, inside the band.
        parkSpotAt(poolState, range, range.tickUpper + poolState.tickSpacing + 1);

        // And: The TWAP caught up, and no token0 in the buffer.
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        almCore.setBuffers(0, almCore.bufferAmount1());

        // And: A foreign position from a spacing above the range, just below spot.
        foreignLiquidity = uint128(bound(foreignLiquidity, Constants.MIN_FUZZED_LIQUIDITY, pool.liquidity()));
        uint160 foreignSqrtPrice = TickMath.getSqrtPriceAtTick(range.tickUpper + poolState.tickSpacing);
        {
            int24 foreignTick = range.tickUpper + poolState.tickSpacing;
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPriceX96(pool), foreignTick, foreignTick + 2 * poolState.tickSpacing, foreignLiquidity
            );
            mintPosition(
                pool, users.liquidityProvider, foreignTick, foreignTick + 2 * poolState.tickSpacing, amount0, amount1
            );
        }

        // And: A deposit past that tick, short of the range and the buffer's room.
        uint160 sqrtPriceStart = sqrtPriceX96(pool);
        uint256 rounding;
        {
            int256 wordStart = (int256(TickMath.getTickAtSqrtPrice(sqrtPriceStart)) / poolState.tickSpacing) >> 8;
            int256 wordEnd = (int256(range.tickUpper) / poolState.tickSpacing) >> 8;
            rounding = (uint256(wordEnd > wordStart ? wordEnd - wordStart : wordStart - wordEnd) + 3)
                * (uint256(pool.liquidity())
                        .fullMulDivUp(1 << 96, sqrtPriceStart)
                        .divUp(TickMath.getSqrtPriceAtTick(range.tickUpper))
                    + 2);

            // And: The edge margins: u + 6 on the balance, 2n + 4 on the position.
            rounding += uint256(1 << 96).divUp(TickMath.getSqrtPriceAtTick(range.tickUpper)) + 12;
        }
        {
            uint256 most = (SqrtPriceMath.getAmount0Delta(foreignSqrtPrice, sqrtPriceStart, pool.liquidity(), false)
                    + SqrtPriceMath.getAmount0Delta(
                        TickMath.getSqrtPriceAtTick(range.tickUpper),
                        foreignSqrtPrice,
                        pool.liquidity() - foreignLiquidity,
                        false
                    ))
            .fullMulDiv(1e6, 1e6 - poolState.fee);
            {
                uint256 drop =
                    (Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1()).fullMulDiv(1 << 96, pool.liquidity());
                if (drop < sqrtPriceStart) {
                    most = FixedPointMathLib.min(
                        most,
                        SqrtPriceMath.getAmount0Delta(
                            uint160(sqrtPriceStart - drop), sqrtPriceStart, pool.liquidity(), false
                        )
                    );
                }
            }
            uint256 least = SqrtPriceMath.getAmount0Delta(foreignSqrtPrice, sqrtPriceStart, pool.liquidity(), true)
                    .fullMulDivUp(1e6, 1e6 - poolState.fee) + 1 + rounding;
            assets = fundDeposit(vault, assets, least, most);
        }
        uint256 supplyBefore = almCore.totalSupply();
        uint256 held = token0.balanceOf(users.unprivilegedAddress) - assets;

        // When: The caller deposits with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, 0);

        // Then: The swap crossed the tick and stopped above the range.
        assertLt(sqrtPriceX96(pool), foreignSqrtPrice);
        assertGt(sqrtPriceX96(pool), TickMath.getSqrtPriceAtTick(range.tickUpper));

        // And: It sold all the asset but the step rounding, the vault keeping none.
        assertLe(token0.balanceOf(users.unprivilegedAddress) - held, rounding);
        assertEq(token0.balanceOf(address(vault)), 0);

        // And: It minted the shares.
        assertEq(almCore.totalSupply(), supplyBefore + shares);
    }

    function testFuzz_Success_deposit_SwapsPastATick_LiquidityFalls(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 foreignLiquidity,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price off its spaced ticks.
        givenValidPoolState(poolState);
        {
            int24 tick = TickMath.getTickAtSqrtPrice(uint160(poolState.sqrtPrice));
            int24 spaced = tick / poolState.tickSpacing * poolState.tickSpacing;
            if (spaced > tick) spaced -= poolState.tickSpacing;
            vm.assume(TickMath.getSqrtPriceAtTick(spaced) != poolState.sqrtPrice);
        }
        setPoolState(poolState, false);

        // And: A seeded token0 vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A foreign position over spot, its lower tick the nearest below spot.
        uint160 foreignSqrtPrice;
        {
            int24 tick = currentTick(pool);
            int24 foreignTick = tick / poolState.tickSpacing * poolState.tickSpacing;
            if (foreignTick > tick) foreignTick -= poolState.tickSpacing;
            foreignSqrtPrice = TickMath.getSqrtPriceAtTick(foreignTick);
            foreignLiquidity = uint128(bound(foreignLiquidity, Constants.MIN_FUZZED_LIQUIDITY, pool.liquidity()));
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPriceX96(pool), foreignTick, foreignTick + poolState.tickSpacing, foreignLiquidity
            );
            (, foreignLiquidity) = mintPosition(
                pool, users.liquidityProvider, foreignTick, foreignTick + poolState.tickSpacing, amount0, amount1
            );
        }

        // And: Up to a 1% sale, its balance past the tick beating the core's ratio.
        {
            uint256 least;
            {
                uint128 liquidityPast = pool.liquidity() - foreignLiquidity;
                uint160 past = foreignSqrtPrice - uint160(uint256(1 << 96).divUp(liquidityPast) + 1);
                uint256 sold = SqrtPriceMath.getAmount0Delta(
                        foreignSqrtPrice, sqrtPriceX96(pool), pool.liquidity(), true
                    )
                    .fullMulDivUp(1e6, 1e6 - poolState.fee)
                + SqrtPriceMath.getAmount0Delta(past, foreignSqrtPrice, liquidityPast, true)
                    .fullMulDivUp(1e6, 1e6 - poolState.fee);
                uint256 total0;
                uint256 total1;
                {
                    Range memory staged = almCore.getRange(0);
                    (total0,) = amountsRoundedUp(
                        past,
                        staged.tickLower,
                        staged.tickUpper,
                        positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                    );
                    (, total1) = amountsRoundedDown(
                        past,
                        staged.tickLower,
                        staged.tickUpper,
                        positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                    );
                }
                total0 += almCore.bufferAmount0() + sold.fullMulDivUp(poolState.fee, 1e6) + uint256(1 << 96).divUp(past)
                + 3;
                least = (SqrtPriceMath.getAmount1Delta(foreignSqrtPrice, sqrtPriceX96(pool), pool.liquidity(), false)
                        + SqrtPriceMath.getAmount1Delta(past, foreignSqrtPrice, liquidityPast, true))
                    .fullMulDivUp(total0, total1 + almCore.bufferAmount1()) + sold + 2;
            }
            assets = fundDeposit(
                vault,
                assets,
                least,
                uint256(pool.liquidity())
                    .fullMulDiv(1 << 96, sqrtPriceX96(pool))
                    .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR)
            );
        }
        uint256 held0 = token0.balanceOf(address(pool)) + token0.balanceOf(address(almCore));
        uint256 held1 = token1.balanceOf(address(pool)) + token1.balanceOf(address(almCore));

        // And: A vault holding no token1.
        assertEq(token1.balanceOf(address(vault)), 0);

        // When: The caller deposits with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress, 0);

        // Then: The swap crossed the tick.
        assertLt(sqrtPriceX96(pool), foreignSqrtPrice);

        // And: The caller got back the token0 the pool and the core did not take.
        assertEq(
            token0.balanceOf(users.unprivilegedAddress),
            assets + held0 - token0.balanceOf(address(pool)) - token0.balanceOf(address(almCore))
        );
        assertEq(token0.balanceOf(address(vault)), 0);

        // And: The vault kept the token1 the pool paid out and the core did not take.
        assertEq(
            token1.balanceOf(address(vault)),
            held1 - token1.balanceOf(address(pool)) - token1.balanceOf(address(almCore))
        );
    }

    function testFuzz_Success_deposit_SwapsPastATick_LiquidityRises(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 foreignLiquidity,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price off its spaced ticks.
        givenValidPoolState(poolState);
        {
            int24 tick = TickMath.getTickAtSqrtPrice(uint160(poolState.sqrtPrice));
            int24 spaced = tick / poolState.tickSpacing * poolState.tickSpacing;
            if (spaced > tick) spaced -= poolState.tickSpacing;
            vm.assume(TickMath.getSqrtPriceAtTick(spaced) != poolState.sqrtPrice);
        }
        setPoolState(poolState, false);

        // And: A seeded token0 vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A foreign position below spot, its upper tick the nearest below spot.
        uint160 foreignSqrtPrice;
        {
            int24 tick = currentTick(pool);
            int24 foreignTick = tick / poolState.tickSpacing * poolState.tickSpacing;
            if (foreignTick > tick) foreignTick -= poolState.tickSpacing;
            foreignSqrtPrice = TickMath.getSqrtPriceAtTick(foreignTick);
            foreignLiquidity = uint128(bound(foreignLiquidity, Constants.MIN_FUZZED_LIQUIDITY, pool.liquidity()));
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPriceX96(pool), foreignTick - poolState.tickSpacing, foreignTick, foreignLiquidity
            );
            (, foreignLiquidity) = mintPosition(
                pool, users.liquidityProvider, foreignTick - poolState.tickSpacing, foreignTick, amount0, amount1
            );
        }

        // And: Up to a 1% sale, its balance past the tick beating the core's ratio.
        {
            uint256 least;
            {
                uint128 liquidityPast = pool.liquidity() + foreignLiquidity;
                uint160 past = foreignSqrtPrice - uint160(uint256(1 << 96).divUp(liquidityPast) + 1);
                uint256 sold = SqrtPriceMath.getAmount0Delta(
                        foreignSqrtPrice, sqrtPriceX96(pool), pool.liquidity(), true
                    )
                    .fullMulDivUp(1e6, 1e6 - poolState.fee)
                + SqrtPriceMath.getAmount0Delta(past, foreignSqrtPrice, liquidityPast, true)
                    .fullMulDivUp(1e6, 1e6 - poolState.fee);
                uint256 total0;
                uint256 total1;
                {
                    Range memory staged = almCore.getRange(0);
                    (total0,) = amountsRoundedUp(
                        past,
                        staged.tickLower,
                        staged.tickUpper,
                        positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                    );
                    (, total1) = amountsRoundedDown(
                        past,
                        staged.tickLower,
                        staged.tickUpper,
                        positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                    );
                }
                total0 += almCore.bufferAmount0() + sold.fullMulDivUp(poolState.fee, 1e6) + uint256(1 << 96).divUp(past)
                + 3;
                least = (SqrtPriceMath.getAmount1Delta(foreignSqrtPrice, sqrtPriceX96(pool), pool.liquidity(), false)
                        + SqrtPriceMath.getAmount1Delta(past, foreignSqrtPrice, liquidityPast, true))
                    .fullMulDivUp(total0, total1 + almCore.bufferAmount1()) + sold + 2;
            }
            assets = fundDeposit(
                vault,
                assets,
                least,
                uint256(pool.liquidity())
                    .fullMulDiv(1 << 96, sqrtPriceX96(pool))
                    .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR)
            );
        }
        uint256 held0 = token0.balanceOf(address(pool)) + token0.balanceOf(address(almCore));
        uint256 held1 = token1.balanceOf(address(pool)) + token1.balanceOf(address(almCore));

        // And: A vault holding no token1.
        assertEq(token1.balanceOf(address(vault)), 0);

        // When: The caller deposits with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress, 0);

        // Then: The swap crossed the tick.
        assertLt(sqrtPriceX96(pool), foreignSqrtPrice);

        // And: The caller got back the token0 the pool and the core did not take.
        assertEq(
            token0.balanceOf(users.unprivilegedAddress),
            assets + held0 - token0.balanceOf(address(pool)) - token0.balanceOf(address(almCore))
        );
        assertEq(token0.balanceOf(address(vault)), 0);

        // And: The vault kept the token1 the pool paid out and the core did not take.
        assertEq(
            token1.balanceOf(address(vault)),
            held1 - token1.balanceOf(address(pool)) - token1.balanceOf(address(almCore))
        );
    }

    function testFuzz_Success_deposit_QuoteEndsAtARangeEdgeWithoutABuy(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 otherLiquidity,
        uint256 sqrtPrice,
        uint256 assets,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool at a fuzzed price, others' depth in half the next ceiling.
        givenValidPoolState(poolState);
        poolState.liquidityPool = uint128(
            bound(
                poolState.liquidityPool,
                Constants.MIN_FUZZED_LIQUIDITY,
                isToken0 ? 1 << 94 : poolState.sqrtPrice * poolState.sqrtPrice >> 98
            )
        );
        setPoolState(poolState, false);

        // And: A range around spot, its edge in the deposit's direction.
        givenValidRangeState(range, poolState, true);
        uint160 edge = TickMath.getSqrtPriceAtTick(isToken0 ? range.tickLower : range.tickUpper);

        // And: Core and other liquidity under which a wei of tokenOut spans 2 units.
        {
            uint256 ceiling = isToken0 ? 1 << 95 : uint256(edge).fullMulDiv(edge, 1 << 97);
            ceiling = FixedPointMathLib.min(
                (ceiling - pool.liquidity()) / 2,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            );
            range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, ceiling));
            range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, ceiling - range.liquidity));
            otherLiquidity = uint128(
                bound(otherLiquidity, Constants.MIN_FUZZED_LIQUIDITY, range.liquidity + range.liquidityStaked)
            );
        }

        // And: A vault seeded with the range, no buffers, a supply that fits the caps.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            Snapshot memory oneRange;
            oneRange.ranges = new PricedRange[](1);
            coreState.supply = FixedPointMathLib.min(
                coreState.supply, type(uint128).max / (snapshotLib.getRounding(oneRange, edge, !isToken0) + 3)
            );
        }
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);
        setMaxSwapCost(maxSwapCostBps);
        {
            (uint256 buffer0, uint256 buffer1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
            almCore.setBuffers(0, 0);
            deal(address(token0), address(almCore), token0.balanceOf(address(almCore)) - buffer0);
            deal(address(token1), address(almCore), token1.balanceOf(address(almCore)) - buffer1);
        }

        // And: The other providers' liquidity over the band.
        {
            int24 band = bandTick(poolState.tickSpacing);
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(sqrtPriceX96(pool), -band, band, otherLiquidity);
            mintPosition(pool, users.liquidityProvider, -band, band, amount0, amount1);
        }

        // And: Spot under a wei of output from the edge, past spot and within the band.
        {
            uint256 least;
            uint256 most;
            if (isToken0) {
                least = (uint256(range.liquidity) + range.liquidityStaked).fullMulDivN(edge, 96) + 1;
                least = least.fullMulDivUp(1 << 96, uint256(range.liquidity) + range.liquidityStaked);
                most = FixedPointMathLib.min(
                    SqrtPriceMath.getNextSqrtPriceFromInput(edge, pool.liquidity(), 1, false) - 1,
                    sqrtPriceX96(pool) - 1
                );
                most = FixedPointMathLib.min(
                    most, snapshotLib.getSwapCostLimit(edge, pool.fee(), maxSwapCostBps, false)
                );
            } else {
                least = FixedPointMathLib.max(
                    SqrtPriceMath.getNextSqrtPriceFromInput(edge, pool.liquidity(), 1, true) + 1, sqrtPriceX96(pool) + 1
                );
                least = FixedPointMathLib.max(
                    least, snapshotLib.getSwapCostLimit(edge, pool.fee(), maxSwapCostBps, true)
                );
                most = (uint256(range.liquidity) + range.liquidityStaked).fullMulDiv(1 << 96, edge) + 1;
                most = (uint256(range.liquidity) + range.liquidityStaked).fullMulDiv(1 << 96, most);
            }
            // And: Where amountsAt's floor steps, a hole no bound expresses.
            vm.assume(least <= most);
            sqrtPrice = bound(sqrtPrice, least, most);
            parkSpotAt(uint160(sqrtPrice), pool.liquidity(), pool.fee());
        }
        assertEq(sqrtPriceX96(pool), sqrtPrice);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: A room of a supply over maxDeposit's tokenOut rounding at spot.
        {
            Snapshot memory oneRange;
            oneRange.ranges = new PricedRange[](1);
            uint256 room = (snapshotLib.getRounding(oneRange, edge, !isToken0) + 2) * almCore.totalSupply();
            vm.startPrank(factory);
            almCore.setTotalCap(almCore.totalSupply() + room);
            almCore.setPerUserCap(room);
            vm.stopPrank();
        }

        // And: Under maxDeposit and the cap past the edge, over 2 swaps and a share.
        {
            Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(vault));
            uint256 least = (isToken0
                    ? SqrtPriceMath.getAmount0Delta(edge, uint160(sqrtPrice), pool.liquidity(), true)
                    : SqrtPriceMath.getAmount1Delta(uint160(sqrtPrice), edge, pool.liquidity(), true))
            .fullMulDivUp(1e6, 1e6 - pool.fee());
            least = 2 * least + snapshotLib.getRounding(snapshot, edge, isToken0) + 3;
            {
                (uint256 shareIn,,) = SnapshotLib.getMintAmounts(snapshot, edge, 1, isToken0);
                least += shareIn;
            }
            uint256 most = pool.liquidity() - range.liquidity - range.liquidityStaked;
            most = isToken0
                ? DepositOptimizationMath.MAX_NORMALIZED.fullMulDiv(most, sqrtPrice << 96)
                : DepositOptimizationMath.MAX_NORMALIZED.fullMulDiv(sqrtPrice, 1 << 160).fullMulDiv(most, 1 << 128);
            most = FixedPointMathLib.min(
                FixedPointMathLib.min(most, Constants.MAX_FUZZED_AMOUNT),
                IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress)
            );
            // And: Room above that floor, the dust room of the ZeroShares limit (audit doc 6.4) excluded.
            vm.assume(least <= most);
            assets = bound(assets, least, most);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));
        uint256 preview = vault.previewDeposit(assets);

        // And: A quote off spot, the dust leg of the ZeroShares limit (audit doc 6.4) excluded.
        vm.assume(preview > 0);
        ERC20Mock asset = ERC20Mock(vault.asset());
        uint256 balance = asset.balanceOf(users.unprivilegedAddress);

        // When: The caller deposits.
        vm.prank(users.unprivilegedAddress);
        vault.deposit(assets, users.unprivilegedAddress);

        // Then: It mints at least the preview.
        assertGe(almCore.balanceOf(users.unprivilegedAddress), preview);

        // And: The pool ends at the range's edge, the quote's end price.
        assertEq(sqrtPriceX96(pool), edge);

        // And: The caller paid at most the assets.
        assertLe(balance - asset.balanceOf(users.unprivilegedAddress), assets);
    }

    function testFuzz_Success_deposit_LeavesStrayTokensUntouched(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 strayAsset,
        uint256 strayOther,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, and a funded deposit within maxDeposit.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        assets = fundDeposit(vault, assets, 0, type(uint256).max);

        // And: Stray asset and other pool token donated to the vault.
        ERC20Mock other = isToken0 ? token1 : token0;
        strayAsset = bound(strayAsset, 1, Constants.MAX_FUZZED_AMOUNT);
        strayOther = bound(strayOther, 1, Constants.MAX_FUZZED_AMOUNT);
        ERC20Mock(vault.asset()).mint(address(vault), strayAsset);
        other.mint(address(vault), strayOther);
        uint256 poolOther = other.balanceOf(address(pool));
        uint256 coreOther = other.balanceOf(address(almCore));
        uint256 supplyBefore = almCore.totalSupply();

        // When: The caller deposits through the plain signature.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress);

        // Then: It minted the shares.
        assertEq(almCore.totalSupply(), supplyBefore + shares);

        // And: The vault still holds the stray tokens, beside the other token it kept.
        assertEq(ERC20Mock(vault.asset()).balanceOf(address(vault)), strayAsset);
        assertEq(
            other.balanceOf(address(vault)),
            strayOther + poolOther - other.balanceOf(address(pool)) - (other.balanceOf(address(almCore)) - coreOther)
        );
    }

    function testFuzz_Success_deposit_LosesAtMostTheFeeWithADustAssetLeg(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 leg,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault, token1 in a range below spot, a token0 buffer of a leg.
        leg = bound(leg, 0, Constants.MAX_FUZZED_AMOUNT / 4);
        ALMVaultSync vault = seededThinLegVault(poolState, coreState, range, true, leg, maxSwapCostBps);

        // And: A funded deposit within maxDeposit.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);

        // And: A preview above zero, the dust leg of known issue 4 excluded.
        vm.assume(vault.previewDeposit(assets) > 0);

        // When: The caller deposits with the preview as its minimum.
        // Then: It minted shares, losing at most the pool's fee and the rounding.
        depositAtThePreview(vault, assets);
    }

    function testFuzz_Revert_deposit_ZeroShares_ADustOtherLeg(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 leg,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault, token0 in a range above spot, a token1 buffer of a leg.
        leg = bound(leg, 1, Constants.MAX_FUZZED_AMOUNT / 4);
        ALMVaultSync vault = seededThinLegVault(poolState, coreState, range, false, leg, maxSwapCostBps);

        // And: A funded deposit within maxDeposit, its token1 leg under half a wei.
        assets = bound(
            assets,
            1,
            FixedPointMathLib.max(
                FixedPointMathLib.min(
                    holdingsValue(true) / (2 * leg),
                    IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress)
                ),
                1
            )
        );
        fundVaultCaller(users.unprivilegedAddress, address(token0), assets, address(vault));
        assertEq(vault.previewDeposit(assets), 0);

        // When: The caller deposits.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMCore.ZeroShares.selector);
        vault.deposit(assets, users.unprivilegedAddress);
    }

    function testFuzz_Success_deposit_LosesAtMostTheFeeWithADustOtherLeg(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 leg,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault, token0 in a range above spot, a token1 buffer of a leg.
        leg = bound(leg, 1, Constants.MAX_FUZZED_AMOUNT / 4);
        ALMVaultSync vault = seededThinLegVault(poolState, coreState, range, false, leg, maxSwapCostBps);

        // And: A funded deposit within maxDeposit.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);

        // And: A preview above zero, the dust leg of known issue 4 excluded.
        vm.assume(vault.previewDeposit(assets) > 0);

        // When: The caller deposits with the preview as its minimum.
        // Then: It minted shares, losing at most the pool's fee and the rounding.
        depositAtThePreview(vault, assets);
    }

    function testFuzz_Success_deposit_LosesAtMostTheFeeWithADustRange(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault holding a token1 buffer and a dust range around spot.
        ALMVaultSync vault = seededDustRangeVault(poolState, coreState, range, maxSwapCostBps);

        // And: A funded deposit within maxDeposit and the core's room.
        assets = fundDeposit(vault, assets, 0, roomValue(true));

        // When: The caller deposits with the preview as its minimum.
        // Then: It minted the preview, losing at most the pool's fee and the rounding.
        depositAtThePreview(vault, assets);
    }

    function testFuzz_Success_deposit_LosesAtMostTheFeeWithADustRangeAboveTheSupply(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault holding a token1 buffer and a dust range around spot.
        ALMVaultSync vault = seededDustRangeVault(poolState, coreState, range, maxSwapCostBps);

        // And: A funded deposit over the core's value, within maxDeposit and its room.
        assets = fundDeposit(vault, assets, holdingsValue(true) + 1, roomValue(true));

        // When: The caller deposits with the preview as its minimum.
        // Then: It minted the preview, losing at most the pool's fee and the rounding.
        depositAtThePreview(vault, assets);
    }

    function testFuzz_Success_deposit_TheMintQuoteMintsAtMostTheRoundingLess(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 trade,
        uint256 shares,
        uint256 protocolSwapFeeBps,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault with a range around spot, the protocol taking swap fees.
        ALMVaultSync vault = seededFeeCarryVault(poolState, coreState, range, protocolSwapFeeBps, maxSwapCostBps);

        roundTrip(true, trade);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: A mint up to the supply and maxMint, over the rounding's shares.
        uint256 slack;
        {
            uint256 most = FixedPointMathLib.min(
                almCore.totalSupply(), IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress)
            );
            uint256 value = holdingsValue(true);
            // The solve's precision, each token's margins and pool steps.
            uint256 sqrtPrice = sqrtPriceX96(pool);
            (uint256 total0, uint256 total1,) = almCore.getUnstakedPositions();
            (total0, total1) = (total0 + almCore.bufferAmount0(), total1 + almCore.bufferAmount1());
            {
                Range memory staged = almCore.getRange(0);
                (uint256 amount0, uint256 amount1) = amountsRoundedDown(
                    uint160(sqrtPrice),
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                (total0, total1) = (total0 + amount0, total1 + amount1);
            }
            slack = (value.fullMulDiv(most, almCore.totalSupply()) / (1 << 64))
            .fullMulDivUp(almCore.totalSupply(), value) + 3;
            uint256 liquidity = pool.liquidity();
            if (total0 > 0) {
                slack += (uint256(1 << 96).divUp(sqrtPrice)
                    + 12
                    + 2
                    * liquidity.fullMulDivUp(1 << 96, sqrtPrice).divUp(sqrtPrice))
                .fullMulDivUp(almCore.totalSupply(), total0);
            }
            if (total1 > 0) {
                slack += (sqrtPrice.divUp(1 << 96) + 12 + 2 * liquidity.divUp(1 << 96))
                .fullMulDivUp(almCore.totalSupply(), total1);
            }
            // And: Where the rounding slack fills the room, a hole no bound expresses.
            vm.assume(slack < most);
            shares = bound(shares, slack + 1, most);
        }

        // And: The quote of that mint, and a caller funded with it.
        uint256 quote = IALMSyncExtension(address(vault)).previewMint(shares);
        fundVaultCaller(users.unprivilegedAddress, address(token0), quote, address(vault));

        // And: A deposit preview above zero, the dust leg of known issue 4 excluded.
        vm.assume(vault.previewDeposit(quote) > 0);

        // When: The caller deposits the quote.
        vm.prank(users.unprivilegedAddress);
        uint256 minted = vault.deposit(quote, users.unprivilegedAddress);

        // Then: It mints at most the shares, short by at most that slack.
        assertLe(minted, shares);
        assertGe(minted + slack, shares);
    }

    function testFuzz_Success_deposit_FillsAtThePreviewAboveTheSupply(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 trade,
        uint256 assets,
        uint256 protocolSwapFeeBps,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault with a range around spot, the protocol taking swap fees.
        ALMVaultSync vault = seededFeeCarryVault(poolState, coreState, range, protocolSwapFeeBps, maxSwapCostBps);

        roundTrip(true, trade);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: A funded deposit over the core's value, within maxDeposit and its room.
        assets = fundDeposit(vault, assets, holdingsValue(true) + 1, roomValue(true));

        // When: The caller deposits with the preview as its minimum.
        // Then: It mints the preview, losing at most the fee and the rounding.
        depositAtThePreview(vault, assets);
    }

    function testFuzz_Success_deposit_FillsAtThePreviewAboveTheSupplyWithoutAFeeCarry(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 trade,
        uint256 assets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault with a range around spot, and no protocol swap fee.
        ALMVaultSync vault = seededFeeCarryVault(poolState, coreState, range, 0, maxSwapCostBps);

        roundTrip(true, trade);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: A funded deposit over the core's value, within maxDeposit and its room.
        assets = fundDeposit(vault, assets, holdingsValue(true) + 1, roomValue(true));

        // And: The token0 fees the core reads after the deposit's buy alone.
        Snapshot memory snapshot = snapshotLib.getSnapshot(address(almCore), address(pool), address(vault));
        (uint160 sqrtPriceNew, uint256 swapIn, uint256 swapOut, uint256 feesModel,) =
            depositMath.computeSwap(snapshot, address(pool), true, assets);
        uint256 feesActual = feesModel;
        if (swapOut > 0) {
            uint256 snapshotId = vm.snapshotState();
            token0.mint(users.liquidityProvider, swapIn);
            vm.startPrank(users.liquidityProvider);
            token0.approve(address(SWAP_ROUTER), swapIn);
            IMetadexSwapRouter(address(SWAP_ROUTER))
                .exactOutputSingle(
                    IMetadexSwapRouter.ExactOutputSingleParams({
                        tokenIn: address(token0),
                        tokenOut: address(token1),
                        tickSpacing: pool.tickSpacing(),
                        recipient: users.liquidityProvider,
                        deadline: vm.getBlockTimestamp(),
                        amountOut: swapOut,
                        amountInMaximum: swapIn,
                        sqrtPriceLimitX96: sqrtPriceNew
                    })
                );
            vm.stopPrank();
            (feesActual,,) = almCore.getUnstakedPositions();
            vm.revertToState(snapshotId);
        }

        // When: The caller deposits with the preview as its minimum.
        depositAtThePreview(vault, assets);

        // Then: The buy carried no fee wei past the model, minting the preview.
        assertLe(feesActual, feesModel);
    }
}
