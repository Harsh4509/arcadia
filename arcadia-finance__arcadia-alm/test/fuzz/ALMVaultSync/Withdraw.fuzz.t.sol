/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "withdraw" of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(reentrancy-events, unused-return)
contract Withdraw_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
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

    function testFuzz_Revert_withdraw_Paused(
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

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);

        // And: The factory paused it.
        vm.prank(factory);
        vault.setPaused(true);

        // When: The holder withdraws.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.withdraw(assets, users.steward, users.steward, type(uint256).max);
    }

    function testFuzz_Revert_withdraw_Paused_BeforeThePlainPreview(
        PoolState memory poolState,
        uint256 amount,
        bool isToken0
    ) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // And: The factory paused it.
        vm.prank(factory);
        vault.setPaused(true);

        // When: Calling the plain withdraw().
        // Then: It reverts on the pause, before the preview.
        vm.prank(users.steward);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.withdraw(amount, users.steward, users.steward);
    }

    function testFuzz_Revert_withdraw_PriceDeviation(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
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
        assets = bound(assets, 1, Constants.MAX_FUZZED_AMOUNT);

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

        // When: The holder withdraws, with no bound of its own.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.PriceDeviation.selector);
        vault.withdraw(assets, users.steward, users.steward, type(uint256).max);
    }

    function testFuzz_Revert_withdraw_InsufficientAllowance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 allowance,
        address caller,
        bool isToken0,
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

        // And: A withdraw of at most the holder's maxWithdraw, worth at least a share.
        uint256 value = holdingsValue(isToken0);
        {
            uint256 least = value.divUp(almCore.totalSupply());
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is under a share's worth, a hole no bound expresses.
            vm.assume(least <= most);
            assets = bound(assets, least, most);
        }

        // And: A caller other than the holder, approved below what the assets are worth.
        vm.assume(caller != users.steward && caller != address(vault));
        allowance = bound(allowance, 0, assets.fullMulDiv(almCore.totalSupply(), value) - 1);
        vm.prank(users.steward);
        almCore.approve(caller, allowance);

        // When: The caller withdraws from the holder.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        vault.withdraw(assets, caller, users.steward, type(uint256).max);
    }

    function testFuzz_Revert_withdraw_InsufficientOutput_BeyondTheSwapCost(
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

        // And: A max swap cost above the pool's fee and below the whole value.
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);

        // And: A range, and a seed receiver holding at least the dead shares in aLP.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 2 * almCore.DEAD_SHARES_(), 0, 0);
        uint160 limit = SnapshotLib.getSwapCostLimit(poolState.sqrtPrice, poolState.fee, maxSwapCostBps, !isToken0);

        // And: A non-asset buffer whose part in half the aLP exceeds the band's input.
        {
            uint128 liquidity = uint128(uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked);
            uint256 capacity = (isToken0
                    ? SqrtPriceMath.getAmount1Delta(uint160(poolState.sqrtPrice), limit, liquidity, true)
                    : SqrtPriceMath.getAmount0Delta(limit, uint160(poolState.sqrtPrice), liquidity, true))
            .fullMulDivUp(1e6, 1e6 - poolState.fee);
            uint256 least =
                (capacity + 2).fullMulDivUp(2 * coreState.supply, coreState.supply - almCore.DEAD_SHARES_()) + 3;
            givenValidCoreState(
                coreState, poolState, range, coreState.supply, isToken0 ? 0 : least, isToken0 ? least : 0
            );
        }
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: A withdraw above half the aLP's burn and the band's output, to its redeem.
        {
            uint256 half = almCore.balanceOf(users.steward) / 2;
            uint128 liquidity = uint128(uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked);
            uint256 least =
                (isToken0
                            ? SqrtPriceMath.getAmount0Delta(uint160(poolState.sqrtPrice), limit, liquidity, false)
                            : SqrtPriceMath.getAmount1Delta(limit, uint160(poolState.sqrtPrice), liquidity, false)) + 1;
            {
                uint256 supply = almCore.totalSupply();
                Range memory staged = almCore.getRange(0);
                (uint256 burn0, uint256 burn1) = amountsRoundedDown(
                    sqrtPriceX96(pool),
                    staged.tickLower,
                    staged.tickUpper,
                    uint128(
                        (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
                        .fullMulDiv(half, supply)
                    )
                );
                least += isToken0
                    ? burn0 + almCore.bufferAmount0().fullMulDiv(half, supply)
                    : burn1 + almCore.bufferAmount1().fullMulDiv(half, supply);
            }
            uint256 most = vault.previewRedeem(half);
            // And: Where half the aLP pays under the output, a hole no bound expresses.
            vm.assume(least <= most);
            assets = bound(assets, least, most);
        }

        // When: The holder withdraws through the plain signature.
        // Then: It reverts, the sale stopping at the band's edge short of the burn.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.withdraw(assets, users.steward, users.steward);
    }

    function testFuzz_Revert_withdraw_InsufficientOutput(
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

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);

        // And: A withdraw of two wei to the holder's maxWithdraw.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is under two wei, a hole no bound expresses.
            vm.assume(most > 1);
            assets = bound(assets, 2, most);
        }

        // And: A burn releasing a wei of the other token, and a sale delivering one wei.
        vm.mockCall(
            address(almCore),
            abi.encodeWithSelector(IALMCore.trustedBurn.selector),
            abi.encode(isToken0 ? 0 : 1, isToken0 ? 1 : 0)
        );
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(IMetadexCLPool.swap.selector),
            abi.encode(isToken0 ? int256(-1) : int256(1), isToken0 ? int256(1) : int256(-1))
        );

        // When: The holder withdraws.
        // Then: It reverts, the sale falling short of the assets.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.withdraw(assets, users.steward, users.steward, type(uint256).max);
    }

    function testFuzz_Revert_withdraw_InsufficientOutput_ThePoolRunsDry(
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

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);

        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A non-asset buffer of at least a wei per aLP.
        fundBuffer(isToken0 ? 0 : almCore.totalSupply(), isToken0 ? almCore.totalSupply() : 0);
        approveVault(users.steward, vault, type(uint256).max);

        // And: Spot a spacing past every position, where the pool buys no non-asset.
        parkSpotAt(
            poolState,
            range,
            isToken0
                ? bandTick(poolState.tickSpacing) + poolState.tickSpacing
                : -bandTick(poolState.tickSpacing) - poolState.tickSpacing
        );
        assertEq(pool.liquidity(), 0);

        // And: Holdings within the core's int128 token deltas at that spot.
        {
            Range memory staged = almCore.getRange(0);
            (uint256 total0, uint256 total1) = amountsRoundedDown(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            (total0, total1) = (total0 + almCore.bufferAmount0(), total1 + almCore.bufferAmount1());
            // And: Where the holdings outgrow an amount, a hole no bound expresses.
            vm.assume(total0 <= Constants.MAX_FUZZED_AMOUNT && total1 <= Constants.MAX_FUZZED_AMOUNT);
        }

        // And: A TWAP window, and a withdraw of up to half the asset past its rounding.
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        uint256 leg0;
        uint256 leg1;
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            uint256 owed = (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
            .fullMulDiv(almCore.balanceOf(users.steward), supply);
            (leg0, leg1) = amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, uint128(owed));
            leg0 += almCore.bufferAmount0().fullMulDiv(almCore.balanceOf(users.steward), supply);
            leg1 += almCore.bufferAmount1().fullMulDiv(almCore.balanceOf(users.steward), supply);
        }
        uint256 most = (isToken0 ? leg0 : leg1)
        .zeroFloorSub(
            almCore.getRangesLength()
                * ((isToken0 ? uint256(1 << 96).divUp(sqrtPriceX96(pool)) : uint256(sqrtPriceX96(pool)).divUp(1 << 96))
                    + 2) + 1
        ) / 2;
        // And: Where no asset wei fits, a hole no bound expresses.
        vm.assume(most > 0);
        assets = bound(assets, 1, most);

        // When: The holder withdraws, with no bound of its own.
        // Then: It reverts, the pool buying less than the non-asset the burn releases.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.withdraw(assets, users.steward, users.steward, type(uint256).max);
    }

    function testFuzz_Revert_withdraw_ExcessiveInput(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 maxShares,
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

        // And: A withdraw of at most the holder's maxWithdraw, worth at least a share.
        uint256 value = holdingsValue(isToken0);
        {
            uint256 least = value.divUp(almCore.totalSupply());
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is under a share's worth, a hole no bound expresses.
            vm.assume(least <= most);
            assets = bound(assets, least, most);
        }

        // And: A share bound below the shares the assets are worth at spot.
        maxShares = bound(maxShares, 0, assets.fullMulDiv(almCore.totalSupply(), value) - 1);

        givenValidRedeemWithinThePoolDepth(isToken0, almCore.balanceOf(users.steward), poolState.liquidityPool);

        // When: The holder withdraws under that bound.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.ExcessiveInput.selector);
        vault.withdraw(assets, users.steward, users.steward, maxShares);
    }

    function testFuzz_Success_withdraw_PaysTheReceiverAtLeastTheAssets(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        address receiver,
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

        // And: A receiver that is neither the holder, the vault, the core nor the pool.
        vm.assume(receiver != users.steward && receiver != address(vault) && receiver != address(0));
        vm.assume(receiver != address(almCore) && receiver != address(pool));

        // And: A withdraw of at most the holder's maxWithdraw.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is zero, a hole no bound expresses.
            vm.assume(most > 0);
            assets = bound(assets, 1, most);
        }
        uint256 receiverBefore = ERC20Mock(vault.asset()).balanceOf(receiver);
        uint256 ownerBefore = ERC20Mock(vault.asset()).balanceOf(users.steward);
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        givenValidRedeemWithinThePoolDepth(isToken0, almCore.balanceOf(users.steward), poolState.liquidityPool);

        // When: The holder withdraws through the plain signature, to the receiver.
        vm.prank(users.steward);
        uint256 spent = vault.withdraw(assets, receiver, users.steward);

        // Then: It burned the shares it returned from the holder.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - spent);

        // And: The receiver got at least the assets, and the holder none.
        assertGe(ERC20Mock(vault.asset()).balanceOf(receiver) - receiverBefore, assets);
        assertEq(ERC20Mock(vault.asset()).balanceOf(users.steward), ownerBefore);
    }

    function testFuzz_Success_withdraw_MaxSharesEqualToTheShares(
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

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);

        // And: A withdraw of at most the holder's maxWithdraw, and the shares it burns.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is zero, a hole no bound expresses.
            vm.assume(most > 0);
            assets = bound(assets, 1, most);
        }
        givenValidRedeemWithinThePoolDepth(isToken0, almCore.balanceOf(users.steward), poolState.liquidityPool);
        uint256 balanceBefore = almCore.balanceOf(users.steward);
        uint256 snapshot = vm.snapshotState();
        vm.prank(users.steward);
        uint256 shares = vault.withdraw(assets, users.steward, users.steward, type(uint256).max);
        vm.revertToState(snapshot);

        // When: The holder withdraws with a bound of exactly those shares.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward, shares);

        // Then: It burned those shares.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
    }

    function testFuzz_Success_withdraw_ZeroBurnsNothing(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address receiver,
        bool isToken0,
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
        uint256 receiverBefore = ERC20Mock(vault.asset()).balanceOf(receiver);
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // When: The holder withdraws nothing through the plain signature.
        vm.prank(users.steward);
        uint256 burned = vault.withdraw(0, receiver, users.steward);

        // Then: It burned none of the holder's shares.
        assertEq(burned, 0);
        assertEq(almCore.balanceOf(users.steward), balanceBefore);

        // And: The receiver got nothing.
        assertEq(ERC20Mock(vault.asset()).balanceOf(receiver), receiverBefore);
    }

    function testFuzz_Success_withdraw_MaxWithdrawOfATinyHolder(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 held,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver keeping up to the dead shares in aLP.
        held = bound(held, 1, Constants.DEAD_SHARES);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + held, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        uint256 rest = almCore.balanceOf(users.steward) - held;
        vm.prank(users.steward);
        almCore.transfer(users.unprivilegedAddress, rest);

        // And: A max swap cost above the pool's fee and below the whole value.
        maxSwapCostBps = bound(maxSwapCostBps, poolState.fee / 100 + 1, ConfigLib.BPS_DENOMINATOR - 1);
        setMaxSwapCost(maxSwapCostBps);

        // And: The holder's maxWithdraw.
        uint256 assets = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(users.steward);

        // When: The holder withdraws it through the plain signature.
        if (assets > 0) {
            vm.prank(users.steward);
            uint256 burned = vault.withdraw(assets, users.steward, users.steward);

            // Then: It paid at least the assets, and burned at most the holder's shares.
            assertGe(ERC20Mock(vault.asset()).balanceOf(users.steward) - assetsBefore, assets);
            assertLe(burned, held);
        }
    }

    function testFuzz_Success_withdraw_InsideTheBand(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 deviation,
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

        // And: A withdraw of at most the holder's maxWithdraw.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is zero, a hole no bound expresses.
            vm.assume(most > 0);
            assets = bound(assets, 1, most);
        }
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // And: A ratio band holding spot's own ratio to the TWAP.
        setSpotFromTwap(insideBand(deviation, spotFromTwap(true)));

        givenValidRedeemWithinThePoolDepth(isToken0, almCore.balanceOf(users.steward), poolState.liquidityPool);

        // When: The holder withdraws to someone else, with no bound of its own.
        vm.prank(users.steward);
        uint256 spent = vault.withdraw(assets, controller, users.steward, type(uint256).max);

        // Then: The returned shares are burned, and the receiver got at least the assets.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - spent);
        assertGe(ERC20Mock(vault.asset()).balanceOf(controller), assets);
    }

    function testFuzz_Success_withdraw_ByOperator(
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

        // And: A seeded vault holding a range, and a holder that approved no one.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A withdraw of at most the holder's maxWithdraw.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is zero, a hole no bound expresses.
            vm.assume(most > 0);
            assets = bound(assets, 1, most);
        }
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // And: The holder made another account its operator.
        vm.prank(users.steward);
        vault.setOperator(secondController, true);

        givenValidRedeemWithinThePoolDepth(isToken0, almCore.balanceOf(users.steward), poolState.liquidityPool);

        // When: The operator withdraws from the holder to itself.
        vm.prank(secondController);
        uint256 spent = vault.withdraw(assets, secondController, users.steward, balanceBefore);

        // Then: The holder's shares are burned, the operator holding at least the assets.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - spent);
        assertGe(ERC20Mock(vault.asset()).balanceOf(secondController), assets);
        assertEq(almCore.allowance(users.steward, secondController), 0);
    }

    function testFuzz_Success_withdraw_ByTheOwnerWithoutApproval(
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

        // And: A seeded vault holding a range, and a holder that approved no one.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A withdraw of at most the holder's maxWithdraw.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is zero, a hole no bound expresses.
            vm.assume(most > 0);
            assets = bound(assets, 1, most);
        }
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        givenValidRedeemWithinThePoolDepth(isToken0, almCore.balanceOf(users.steward), poolState.liquidityPool);

        // When: The holder withdraws to someone else, bounded by its shares.
        vm.prank(users.steward);
        uint256 spent = vault.withdraw(assets, controller, users.steward, balanceBefore);

        // Then: The holder's shares are burned, the receiver holding at least the assets.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - spent);
        assertGe(ERC20Mock(vault.asset()).balanceOf(controller), assets);
    }

    function testFuzz_Success_withdraw_BySpender(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 allowance,
        address spender,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, and a holder's shares.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A withdraw of at most the holder's maxWithdraw.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is zero, a hole no bound expresses.
            vm.assume(most > 0);
            assets = bound(assets, 1, most);
        }
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // And: A spender other than the holder, approved for all the holder's shares.
        vm.assume(spender != users.steward && spender != address(0));
        allowance = bound(allowance, balanceBefore, type(uint256).max - 1);
        vm.prank(users.steward);
        almCore.approve(spender, allowance);

        givenValidRedeemWithinThePoolDepth(isToken0, almCore.balanceOf(users.steward), poolState.liquidityPool);

        // When: The spender withdraws from the holder to someone else.
        vm.prank(spender);
        uint256 spent = vault.withdraw(assets, controller, users.steward, balanceBefore);

        // Then: The shares are burned, and the allowance dropped by them.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - spent);
        assertEq(almCore.allowance(users.steward, spender), allowance - spent);
    }

    function testFuzz_Success_withdraw_SellsPastTheRangeEdgeSpotIsPinnedAt(
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

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A range over a tick wide, so a tick inside its edge is not its other edge.
        {
            int24 tickSpacing = poolState.tickSpacing;
            int24 band = bandTick(tickSpacing) / tickSpacing;
            int24 width = (2 + tickSpacing - 1) / tickSpacing;
            range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, band - 1 - width)) * tickSpacing;
            range.tickUpper = int24(
                bound(range.tickUpper / tickSpacing, range.tickLower / tickSpacing + width, band - 1)
            ) * tickSpacing;
        }

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);

        // And: Spot a tick inside the range's edge in the sale's direction.
        parkSpotAt(poolState, range, isToken0 ? range.tickUpper - 1 : range.tickLower + 1);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: Holdings within the core's int128 token deltas at that spot.
        {
            Range memory staged = almCore.getRange(0);
            (uint256 total0, uint256 total1) = amountsRoundedDown(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
            // And: Where the holdings outgrow an amount, a hole no bound expresses.
            vm.assume(
                total0 + fees0 + almCore.bufferAmount0() <= Constants.MAX_FUZZED_AMOUNT
                    && total1 + fees1 + almCore.bufferAmount1() <= Constants.MAX_FUZZED_AMOUNT
            );
        }

        // And: A withdraw the asset of shares selling within slippage covers.
        {
            uint256 shares = redeemableWithinSlippage(vault);
            uint256 most;
            {
                Range memory staged = almCore.getRange(0);
                (uint256 leg0, uint256 leg1) = amountsRoundedDown(
                    sqrtPriceX96(pool),
                    staged.tickLower,
                    staged.tickUpper,
                    uint128(
                        (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
                        .fullMulDiv(shares, almCore.totalSupply())
                    )
                );
                most = isToken0 ? leg0 : leg1;
            }
            {
                (uint256 fees0, uint256 fees1) = positionFees(pool, almCore.getRange(0).unstakedTokenId);
                uint256 idle = isToken0
                    ? almCore.bufferAmount0() + fees0
                        - fees0.fullMulDiv(almCore.protocolSwapFeeBps_(), ConfigLib.BPS_DENOMINATOR)
                    : almCore.bufferAmount1() + fees1
                        - fees1.fullMulDiv(almCore.protocolSwapFeeBps_(), ConfigLib.BPS_DENOMINATOR);
                most += idle.fullMulDiv(shares, almCore.totalSupply());
            }
            most = FixedPointMathLib.min(most, IALMSyncExtension(address(vault)).maxWithdraw(users.steward));
            // And: Where no asset wei fits, a hole no bound expresses.
            vm.assume(most > 0);
            assets = bound(assets, 1, most);
        }

        // When: The holder withdraws.
        vm.prank(users.steward);
        vault.withdraw(assets, users.steward, users.steward);

        // Then: The vault kept none of the other token, the sale taking it all.
        assertEq(ERC20Mock(isToken0 ? pool.token1() : pool.token0()).balanceOf(address(vault)), 0);
    }

    function testFuzz_Success_withdraw_MaxSharesSkipsTheValueLossCheck(
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

        // And: A seed receiver holding at least the dead shares in aLP.
        givenValidCoreState(coreState, poolState, range, 2 * almCore.DEAD_SHARES_(), 0, 0);

        // And: A non-asset buffer whose part in a quarter of the aLP sells above them.
        {
            uint256 liquidity = uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked;
            uint256 worth = uint256(4e6).divUp(poolState.fee) + 2
                * (isToken0
                        ? liquidity.fullMulDivUp(1 << 96, poolState.sqrtPrice * poolState.sqrtPrice)
                        : liquidity >> 96) + 2;
            uint256 leg = isToken0
                ? worth.fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192)
                : worth.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
            uint256 least = (leg + 2).fullMulDivUp(4 * coreState.supply, coreState.supply - almCore.DEAD_SHARES_()) + 3;
            givenValidCoreState(
                coreState, poolState, range, coreState.supply, isToken0 ? 0 : least, isToken0 ? least : 0
            );
        }
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A withdraw worth over a quarter of the aLP, up to the maxWithdraw.
        {
            uint256 least =
                (almCore.balanceOf(users.steward) / 4 + 1).fullMulDivUp(holdingsValue(isToken0), almCore.totalSupply());
            uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
            // And: Where maxWithdraw is under the quarter, a hole no bound expresses.
            vm.assume(least <= most);
            assets = bound(assets, least, most);
        }
        uint256 balanceBefore = almCore.balanceOf(users.steward);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(users.steward);

        // And: A max swap cost of zero.
        setMaxSwapCost(0);

        givenValidRedeemWithinThePoolDepth(isToken0, almCore.balanceOf(users.steward), poolState.liquidityPool);

        // When: The holder withdraws bounded by its shares.
        vm.prank(users.steward);
        uint256 spent = vault.withdraw(assets, users.steward, users.steward, balanceBefore);

        // Then: It burned the shares it returned and paid at least the assets.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - spent);
        assertGe(ERC20Mock(vault.asset()).balanceOf(users.steward) - assetsBefore, assets);
    }

    function testFuzz_Success_withdraw_MaxWithdrawOverAPoolThinnerThanItsPrice(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 held,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool whose other providers' depth is at most its raw price.
        givenValidPoolState(poolState);
        poolState.liquidityPool = uint128(
            bound(
                poolState.liquidityPool, 1, FixedPointMathLib.max(poolState.sqrtPrice * poolState.sqrtPrice >> 192, 1)
            )
        );
        setPoolState(poolState, false);

        // And: A range below spot, so the core holds token0 only as its seed's buffer.
        uint256 supply = bound(coreState.supply, Constants.DEAD_SHARES + 1, Constants.MAX_FUZZED_AMOUNT);
        givenValidDustState(coreState, poolState, range, true, 0, 0);

        // And: A token0 vault over any supply, a share worth under a wei or more.
        givenValidCoreState(coreState, poolState, range, supply, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: An owner of part of the aLP, the rest transferred away.
        held = bound(held, 1, almCore.balanceOf(users.steward));
        uint256 rest = almCore.balanceOf(users.steward) - held;
        vm.prank(users.steward);
        almCore.transfer(users.unprivilegedAddress, rest);

        // And: The owner's maxWithdraw, and the shares its preview burns.
        uint256 assets = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
        uint256 preview = vault.previewWithdraw(assets);
        uint256 assetsBefore = token0.balanceOf(users.steward);

        // When: The owner withdraws it.
        vm.prank(users.steward);
        uint256 burned = vault.withdraw(assets, users.steward, users.steward);

        // Then: The preview is within the owner's shares, and the withdraw burns it.
        assertLe(preview, held);
        assertEq(burned, preview);

        // And: It paid at least the assets.
        assertGe(token0.balanceOf(users.steward) - assetsBefore, assets);
    }
}
