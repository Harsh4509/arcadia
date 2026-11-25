/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { SwapMath } from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Vm } from "@forge-std/Vm.sol";

/**
 * @notice Fuzz tests for the function "redeem" of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(reentrancy-events, unused-return)
contract Redeem_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
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

    function testFuzz_Revert_redeem_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        approveVault(users.steward, vault, shares);

        // And: The factory paused it.
        vm.prank(factory);
        vault.setPaused(true);

        // When: The holder redeems.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.redeem(shares, users.steward, users.steward, 0);
    }

    function testFuzz_Revert_redeem_Paused_BeforeThePlainPreview(
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

        // When: Calling the plain redeem().
        // Then: It reverts on the pause, before the preview.
        vm.prank(users.steward);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.redeem(amount, users.steward, users.steward);
    }

    function testFuzz_Revert_redeem_InsufficientAllowance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 allowance,
        address caller,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, and its holder's shares.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        shares = bound(shares, 1, almCore.balanceOf(users.steward));

        // And: A caller other than the holder, approved for less.
        vm.assume(caller != users.steward && caller != address(vault));
        allowance = bound(allowance, 0, shares - 1);
        vm.prank(users.steward);
        almCore.approve(caller, allowance);

        // When: The caller redeems the holder's shares.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        vault.redeem(shares, caller, users.steward, 0);
    }

    function testFuzz_Revert_redeem_InsufficientOutput(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        approveVault(users.steward, vault, shares);

        // And: A floor one wei above the pro-rata share valued at spot.
        uint256 leg0;
        uint256 leg1;
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            uint256 owed = (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
            .fullMulDiv(shares, supply);
            (leg0, leg1) = amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, uint128(owed));
            leg0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
            leg1 += almCore.bufferAmount1().fullMulDiv(shares, supply);
        }
        uint256 unreachable = isToken0
            ? leg0 + CLMath.convert(sqrtPriceX96(pool), false, leg1, false) + 1
            : leg1 + CLMath.convert(sqrtPriceX96(pool), true, leg0, false) + 1;

        // When: The holder redeems under that floor.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.redeem(shares, users.steward, users.steward, unreachable);
    }

    function testFuzz_Revert_redeem_InsufficientOutput_ThePoolRunsDry(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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

        // And: A non-asset buffer of at least a wei per aLP.
        fundBuffer(isToken0 ? 0 : almCore.totalSupply(), isToken0 ? almCore.totalSupply() : 0);

        // And: A redeem of up to the holder's aLP.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        approveVault(users.steward, vault, shares);

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

        // And: A TWAP window at that spot.
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // When: The holder redeems, with no bound of its own.
        // Then: It reverts, the pool buying less than the non-asset the burn releases.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.redeem(shares, users.steward, users.steward, 0);
    }

    function testFuzz_Revert_redeem_PriceDeviation(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        approveVault(users.steward, vault, shares);

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

        // When: The holder redeems, with no bound of its own.
        // Then: It reverts.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.PriceDeviation.selector);
        vault.redeem(shares, users.steward, users.steward, 0);
    }

    function testFuzz_Revert_redeem_InsufficientOutput_BeyondTheSwapCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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

        // And: A non-asset buffer whose part in half the aLP exceeds the band's input.
        {
            uint160 limit = SnapshotLib.getSwapCostLimit(poolState.sqrtPrice, poolState.fee, maxSwapCostBps, !isToken0);
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

        // And: A redeem of over half the receiver's aLP, up to all of it.
        {
            uint256 balance = almCore.balanceOf(users.steward);
            shares = bound(shares, balance / 2 + 1, balance);
        }

        // When: The holder redeems through the plain signature.
        // Then: It reverts, the sale stopping at the band's edge short of the burn.
        vm.prank(users.steward);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.redeem(shares, users.steward, users.steward);
    }

    function testFuzz_Revert_redeem_SPL_TheSwapCostIsWithinTheFee(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A vault seeded with it, and a seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A redeem of up to the holder's aLP whose burn releases the non-asset.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            uint256 owed = (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
            .fullMulDiv(shares, supply);
            (uint256 leg0, uint256 leg1) =
                amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, uint128(owed));
            leg0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
            leg1 += almCore.bufferAmount1().fullMulDiv(shares, supply);
            // And: Where the shares hold none of the non-asset, a hole.
            vm.assume((isToken0 ? leg1 : leg0) > 0);
        }

        // And: A max swap cost of at most the pool's fee.
        maxSwapCostBps = bound(maxSwapCostBps, 0, poolState.fee / 100);
        setMaxSwapCost(maxSwapCostBps);

        // When: The holder redeems through the plain signature.
        // Then: It reverts in the pool, the sale's limit being spot.
        vm.prank(users.steward);
        vm.expectRevert(bytes("SPL"));
        vault.redeem(shares, users.steward, users.steward);
    }

    function testFuzz_Success_redeem_PaysOnlyInTheAsset(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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

        // And: A redeem whose sale stays within slippage.
        {
            uint256 most = redeemableWithinSlippage(vault);
            // And: Where no share sells within slippage, a hole no bound expresses.
            vm.assume(most > 0);
            shares = bound(shares, 1, most);
        }
        approveVault(users.steward, vault, shares);
        uint256 balanceBefore = almCore.balanceOf(users.steward);
        uint256 supplyBefore = almCore.totalSupply();
        uint256 released =
            ERC20Mock(vault.asset()).balanceOf(address(pool)) + ERC20Mock(vault.asset()).balanceOf(address(almCore));

        // When: The holder redeems to someone else, with no bound of its own.
        vm.prank(users.steward);
        uint256 assets = vault.redeem(shares, controller, users.steward, 0);

        // Then: The shares are burned from the holder.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
        assertEq(almCore.totalSupply(), supplyBefore - shares);

        // And: The receiver got what the pool and the core released, none of the other.
        assertEq(ERC20Mock(vault.asset()).balanceOf(controller), assets);
        assertEq(
            assets,
            released - ERC20Mock(vault.asset()).balanceOf(address(pool))
                - ERC20Mock(vault.asset()).balanceOf(address(almCore))
        );
        assertEq((isToken0 ? token1 : token0).balanceOf(controller), 0);

        // And: The vault kept neither token, the sale taking all the burn released.
        assertEq(ERC20Mock(vault.asset()).balanceOf(address(vault)), 0);
        assertEq((isToken0 ? token1 : token0).balanceOf(address(vault)), 0);
    }

    function testFuzz_Success_redeem_InsideTheBand(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        approveVault(users.steward, vault, shares);
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // And: A ratio band holding spot's own ratio to the TWAP.
        setSpotFromTwap(insideBand(deviation, spotFromTwap(true)));

        givenValidRedeemWithinThePoolDepth(isToken0, shares, poolState.liquidityPool);

        // When: The holder redeems, with no bound of its own.
        vm.prank(users.steward);
        uint256 assets = vault.redeem(shares, controller, users.steward, 0);

        // Then: The shares are burned and the receiver got the asset paid out.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
        assertEq(ERC20Mock(vault.asset()).balanceOf(controller), assets);
    }

    function testFuzz_Success_redeem_MaxRedeemOfATinyHolder(
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

        // And: The holder's maxRedeem.
        uint256 shares = IALMSyncExtension(address(vault)).maxRedeem(users.steward);

        // When: The holder redeems it through the plain signature.
        if (shares > 0) {
            vm.prank(users.steward);
            vault.redeem(shares, users.steward, users.steward);

            // Then: The holder's balance fell by the shares.
            assertEq(almCore.balanceOf(users.steward), held - shares);
        }
    }

    function testFuzz_Success_redeem_EmitsWithdraw(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        approveVault(users.steward, vault, shares);

        // And: The receiver's asset balance before the redeem.
        uint256 balanceBefore = ERC20Mock(vault.asset()).balanceOf(controller);

        givenValidRedeemWithinThePoolDepth(isToken0, shares, poolState.liquidityPool);

        // When: The holder redeems.
        vm.recordLogs();
        vm.prank(users.steward);
        vault.redeem(shares, controller, users.steward, 0);

        // Then: The vault reports caller, receiver, owner, asset paid and shares.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool emitted;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(vault) || logs[i].topics[0] != BaseVault.Withdraw.selector) continue;
            emitted = true;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), users.steward);
            assertEq(address(uint160(uint256(logs[i].topics[2]))), controller);
            assertEq(address(uint160(uint256(logs[i].topics[3]))), users.steward);
            (uint256 assets, uint256 burned) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(assets, ERC20Mock(vault.asset()).balanceOf(controller) - balanceBefore);
            assertEq(burned, shares);
        }
        assertTrue(emitted);
    }

    function testFuzz_Success_redeem_ByOperator(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // And: The holder made another account its operator.
        vm.prank(users.steward);
        vault.setOperator(secondController, true);

        givenValidRedeemWithinThePoolDepth(isToken0, shares, poolState.liquidityPool);

        // When: The operator redeems the holder's shares to itself.
        vm.prank(secondController);
        uint256 assets = vault.redeem(shares, secondController, users.steward, 0);

        // Then: The holder's shares are burned and the operator holds what they paid.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
        assertEq(ERC20Mock(vault.asset()).balanceOf(secondController), assets);
        assertEq(almCore.allowance(users.steward, secondController), 0);
    }

    function testFuzz_Success_redeem_ByTheOwnerWithoutApproval(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        uint256 balanceBefore = almCore.balanceOf(users.steward);
        uint256 assetsBefore = ERC20Mock(vault.asset()).balanceOf(users.steward);

        givenValidRedeemWithinThePoolDepth(isToken0, shares, poolState.liquidityPool);

        // When: The holder redeems its own shares.
        vm.prank(users.steward);
        uint256 assets = vault.redeem(shares, users.steward, users.steward, 0);

        // Then: The shares are burned and the holder got the asset paid out.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
        assertEq(ERC20Mock(vault.asset()).balanceOf(users.steward) - assetsBefore, assets);
    }

    function testFuzz_Success_redeem_BySpender(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // And: A spender other than the holder, approved for at least the shares.
        vm.assume(spender != users.steward && spender != address(0));
        allowance = bound(allowance, shares, type(uint256).max - 1);
        vm.prank(users.steward);
        almCore.approve(spender, allowance);

        givenValidRedeemWithinThePoolDepth(isToken0, shares, poolState.liquidityPool);

        // When: The spender redeems the holder's shares to itself.
        vm.prank(spender);
        vault.redeem(shares, spender, users.steward, 0);

        // Then: The shares are burned, and the allowance dropped by them.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
        assertEq(almCore.allowance(users.steward, spender), allowance - shares);
    }

    function testFuzz_Success_redeem_SellsALegWorthUnderAWei(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault over the dearer token, holding a range.
        bool isToken0 = poolState.sqrtPrice > SQRT_PRICE_ONE_X96;
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        ERC20Mock other = isToken0 ? token1 : token0;

        // And: An approved redeem whose non-asset leg is worth at most an asset wei.
        uint256 worth = isToken0 ? token0ToToken1(sqrtPriceX96(pool), 1) : token1ToToken0(sqrtPriceX96(pool), 1);
        uint256 total;
        {
            Range memory staged = almCore.getRange(0);
            (uint256 total0, uint256 total1) = amountsRoundedDown(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            total = isToken0 ? total1 + almCore.bufferAmount1() : total0 + almCore.bufferAmount0();
        }
        uint256 supply = almCore.totalSupply();
        {
            uint256 upper = FixedPointMathLib.min(supply.fullMulDiv(worth, total + 1), almCore.balanceOf(users.steward));
            uint256 lower = supply / (total + 1) + 1;
            // And: Where no share count prices such a leg, a hole no bound expresses.
            vm.assume(lower <= upper);
            shares = bound(shares, lower, upper);
        }
        {
            Range memory staged = almCore.getRange(0);
            uint256 owed = (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
            .fullMulDiv(shares, supply);
            (uint256 leg0, uint256 leg1) =
                amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, uint128(owed));
            uint256 leg = isToken0
                ? leg1 + almCore.bufferAmount1().fullMulDiv(shares, supply)
                : leg0 + almCore.bufferAmount0().fullMulDiv(shares, supply);
            // And: Where the leg's rounding leaves that band, a hole no bound expresses.
            vm.assume(leg > 0 && leg <= worth);
        }
        approveVault(users.steward, vault, shares);
        uint256 dustBefore = other.balanceOf(address(vault));

        // And: A max swap cost of zero.
        setMaxSwapCost(0);

        // When: The holder redeems, with no bound of its own.
        vm.prank(users.steward);
        vault.redeem(shares, controller, users.steward, 0);

        // Then: The redeem paid none of the non-asset, and the vault sold the whole leg.
        assertEq(other.balanceOf(controller), 0);
        assertEq(other.balanceOf(address(vault)), dustBefore);
    }

    function testFuzz_Success_redeem_SellsTheNonAssetLegAtZeroActiveLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault, and a redeem whose non-asset leg can be sold.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        uint256 most = redeemableWithinSlippage(vault);
        // And: Where no share sells within slippage, a hole no bound expresses.
        vm.assume(most > 0);
        shares = bound(shares, 1, most);
        uint256 leg0;
        uint256 leg1;
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            uint256 owed = (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
            .fullMulDiv(shares, supply);
            (leg0, leg1) = amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, uint128(owed));
            leg0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
            leg1 += almCore.bufferAmount1().fullMulDiv(shares, supply);
        }
        uint256 leg = isToken0 ? leg1 : leg0;
        (,, uint256 sellable,) = SwapMath.computeSwapStep(
            sqrtPriceX96(pool),
            isToken0 ? TickMath.MAX_SQRT_PRICE - 1 : TickMath.MIN_SQRT_PRICE + 1,
            pool.liquidity(),
            -int256(leg),
            pool.fee()
        );
        // And: Where the pool buys no non-asset, a hole no bound expresses.
        vm.assume(sellable > 0);
        approveVault(users.steward, vault, shares);
        uint256 dustBefore = (vault.asset() == address(token0) ? token1 : token0).balanceOf(address(vault));

        // And: A pool that reports no active liquidity, so no quote prices the sale.
        vm.mockCall(address(pool), abi.encodeWithSelector(IMetadexCLPool.liquidity.selector), abi.encode(uint128(0)));

        // When: The holder redeems, with no bound of its own.
        vm.prank(users.steward);
        vault.redeem(shares, controller, users.steward, 0);

        // Then: The vault sold the whole non-asset leg through the pool.
        assertEq((vault.asset() == address(token0) ? token1 : token0).balanceOf(address(vault)), dustBefore);
        assertEq((vault.asset() == address(token0) ? token1 : token0).balanceOf(controller), 0);
    }

    function testFuzz_Success_redeem_MinAssetsSkipsTheValueLossCheck(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding at least the dead shares in aLP.
        givenValidCoreState(coreState, poolState, range, 2 * almCore.DEAD_SHARES_(), 0, 0);

        // And: A non-asset buffer whose part in half the aLP sells above the roundings.
        {
            uint256 liquidity = uint256(poolState.liquidityPool) + range.liquidity + range.liquidityStaked;
            uint256 worth = uint256(4e6).divUp(poolState.fee) + 2
                * (isToken0
                        ? liquidity.fullMulDivUp(1 << 96, poolState.sqrtPrice * poolState.sqrtPrice)
                        : liquidity >> 96) + 2;
            uint256 leg = isToken0
                ? worth.fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192)
                : worth.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
            uint256 least = (leg + 2).fullMulDivUp(2 * coreState.supply, coreState.supply - almCore.DEAD_SHARES_()) + 3;
            givenValidCoreState(
                coreState, poolState, range, coreState.supply, isToken0 ? 0 : least, isToken0 ? least : 0
            );
        }
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A redeem of half to all of the holder's shares.
        shares = bound(shares, almCore.balanceOf(users.steward) / 2 + 1, almCore.balanceOf(users.steward));
        givenValidRedeemWithinThePoolDepth(isToken0, shares, poolState.liquidityPool);
        uint256 balanceBefore = almCore.balanceOf(users.steward);

        // And: A max swap cost of zero.
        setMaxSwapCost(0);

        // When: The holder redeems with a floor of one wei.
        vm.prank(users.steward);
        uint256 assets = vault.redeem(shares, controller, users.steward, 1);

        // Then: The shares are burned and the receiver got the asset paid out.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
        assertEq(ERC20Mock(vault.asset()).balanceOf(controller), assets);
    }

    function testFuzz_Success_redeem_AboveTheCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault, a holder that approved it and a per user cap of nothing.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        approveVault(users.steward, vault, shares);
        uint256 balanceBefore = almCore.balanceOf(users.steward);
        vm.prank(factory);
        almCore.setPerUserCap(0);

        givenValidRedeemWithinThePoolDepth(isToken0, shares, poolState.liquidityPool);

        // When: The holder redeems.
        vm.prank(users.steward);
        vault.redeem(shares, users.steward, users.steward, 0);

        // Then: It is not checked.
        assertEq(almCore.balanceOf(users.steward), balanceBefore - shares);
    }
}
