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
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "previewRedeem" of contract "ALMVaultSync".
 */
contract PreviewRedeem_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
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

    function testFuzz_Revert_previewRedeem_CoreNotDeployed(PoolState memory poolState, bool isToken0, uint256 shares)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? 0 : 1];

        // When: Reading previewRedeem() on one of its synchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        ALMVaultSync(vault).previewRedeem(shares);
    }

    function testFuzz_Revert_previewRedeem_Reentrancy(
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
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: The core's lock is held.
        almCore.lock_();

        // When: Previewing a redeem.
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        vault.previewRedeem(shares);
    }

    function testFuzz_Revert_previewRedeem_NotInitialized(PoolState memory poolState, uint256 shares, bool isToken0)
        public
    {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Previewing a redeem.
        // Then: It reverts, there being no supply to quote against.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        vault.previewRedeem(shares);
    }

    function testFuzz_Success_previewRedeem_IsWhatRedeemPays(
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

        // And: A redeem of at most the holder's maxRedeem.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxRedeem(users.steward);
            // And: Where maxRedeem is zero, a hole no bound expresses.
            vm.assume(most > 0);
            shares = bound(shares, 1, most);
        }
        approveVault(users.steward, vault, shares);
        uint256 quoted = vault.previewRedeem(shares);

        // When: The holder redeems through the plain signature.
        vm.prank(users.steward);
        uint256 assets = vault.redeem(shares, users.steward, users.steward);

        // Then: It paid the preview.
        assertEq(assets, quoted);
    }

    function testFuzz_Success_previewRedeem_IsWhatRedeemPays_FeesOnManyRanges(
        PoolState memory poolState,
        CoreState memory coreState,
        uint256 count,
        uint128 liquidity,
        uint16 feeBps,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core seeded with up to a seed's amounts, its seed receiver holding aLP.
        coreState.supply = bound(coreState.supply, almCore.DEAD_SHARES_() + 1, Constants.SEED_AMOUNT);
        coreState.buffer0 = bound(coreState.buffer0, 1, Constants.SEED_AMOUNT);
        coreState.buffer1 = bound(coreState.buffer1, 1, Constants.SEED_AMOUNT);
        setCoreState(coreState);
        ALMVaultSync vault = vaultFor(false);

        // And: Two to the cap of ranges above spot, sharing their lower tick's room.
        count = bound(count, 2, ConfigLib.MAX_RANGE_CAP);
        int24 tickAbove = (poolState.tickCurrent / poolState.tickSpacing + 1) * poolState.tickSpacing;
        liquidity = uint128(
            bound(
                liquidity,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(tickAbove, tickAbove + poolState.tickSpacing, Constants.MIN_FUZZED_LIQUIDITY) / count
            )
        );
        RangeState memory range;
        for (uint256 i; i < count; ++i) {
            (range.tickLower, range.tickUpper, range.liquidity) =
            (tickAbove, tickAbove + int24(int256(i + 1)) * poolState.tickSpacing, liquidity);
            setRangeState(range);
        }

        // And: Trades through the ranges and back, leaving fees under a protocol share.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        uint16 emissionFeeBps = almCore.protocolEmissionFeeBps_();
        vm.prank(factory);
        almCore.setProtocolFees(emissionFeeBps, feeBps, users.feeRecipient);
        token1.mint(users.liquidityProvider, Constants.MAX_FUZZED_AMOUNT);
        {
            uint160 past = TickMath.getSqrtPriceAtTick(tickAbove + int24(int256(count + 1)) * poolState.tickSpacing);
            swapAsActor(
                pool, users.liquidityProvider, address(token1), address(token0), Constants.MAX_FUZZED_AMOUNT, past
            );
        }
        token0.mint(users.liquidityProvider, Constants.MAX_FUZZED_AMOUNT);
        swapAsActor(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            Constants.MAX_FUZZED_AMOUNT,
            uint160(poolState.sqrtPrice)
        );
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: A holder redeeming any of its shares, after approving the vault.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        approveVault(users.steward, vault, shares);
        uint256 quoted = vault.previewRedeem(shares);

        // When: The holder redeems, with no bound of its own.
        vm.prank(users.steward);
        uint256 assets = vault.redeem(shares, users.steward, users.steward, 0);

        // Then: It paid the preview.
        assertEq(assets, quoted);
    }
}
