/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { BaseVault_Fuzz_Test } from "./_BaseVault.fuzz.t.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";

/**
 * @notice Fuzz tests for the function "convertToShares" of contract "BaseVault", over both vault kinds.
 */
contract ConvertToShares_BaseVault_Fuzz_Test is BaseVault_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(BaseVault_Fuzz_Test) {
        BaseVault_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_convertToShares_CoreNotDeployed(PoolState memory poolState, uint256 index, uint256 assets)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[bound(index, 0, list.length - 1)];

        // When: Reading convertToShares() on one of its vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        IALMSyncExtension(vault).convertToShares(assets);
    }

    function testFuzz_Revert_convertToShares_Reentrancy(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        uint256 index
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // And: The core's lock is held.
        almCore.lock_();

        // When: Converting an asset amount.
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        IALMSyncExtension(address(vault)).convertToShares(assets);
    }

    function testFuzz_Success_convertToShares_ZeroWhenNotInitialized(
        PoolState memory poolState,
        uint256 index,
        uint256 assets
    ) public {
        // Given: The four vaults over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // When: Converting any asset amount.
        // Then: There is nothing to convert against.
        assertEq(IALMSyncExtension(address(vault)).convertToShares(assets), 0);
    }

    function testFuzz_Success_convertToShares_WholeHoldingIsTheSupply(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 index
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // And: The holding valued at whichever of spot and the mean values it lowest.
        bool assetIsToken0 = vault.asset() == address(token0);
        uint256 spot = sqrtPriceX96(pool);
        uint256 mean = almCore.meanSqrtPriceX96_();
        uint160 price = uint160(assetIsToken0 ? FixedPointMathLib.max(spot, mean) : FixedPointMathLib.min(spot, mean));
        uint128 liquidity = range.liquidity + range.liquidityStaked;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(price, range.tickLower, range.tickUpper, liquidity);
        (amount0, amount1) = (amount0 + almCore.bufferAmount0(), amount1 + almCore.bufferAmount1());
        uint256 total =
            assetIsToken0 ? amount0 + token1ToToken0(price, amount1) : amount1 + token0ToToken1(price, amount0);

        // When: Converting the whole holding.
        uint256 shares = IALMSyncExtension(address(vault)).convertToShares(total);

        // Then: It is the whole supply.
        assertEq(shares, almCore.totalSupply());
    }

    function testFuzz_Success_convertToShares_RoundTripRoundsDown(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 index,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // And: The holding valued at whichever of spot and the mean values it lowest.
        uint256 total;
        {
            bool assetIsToken0 = vault.asset() == address(token0);
            uint256 spot = sqrtPriceX96(pool);
            uint256 mean = almCore.meanSqrtPriceX96_();
            uint160 price =
                uint160(assetIsToken0 ? FixedPointMathLib.max(spot, mean) : FixedPointMathLib.min(spot, mean));
            uint128 liquidity = range.liquidity + range.liquidityStaked;
            (uint256 amount0, uint256 amount1) = amountsRoundedDown(price, range.tickLower, range.tickUpper, liquidity);
            (amount0, amount1) = (amount0 + almCore.bufferAmount0(), amount1 + almCore.bufferAmount1());
            total = assetIsToken0 ? amount0 + token1ToToken0(price, amount1) : amount1 + token0ToToken1(price, amount0);
        }

        // And: A share amount up to the supply.
        uint256 supply = almCore.totalSupply();
        shares = bound(shares, 0, supply);

        // When: Converting shares to assets and back.
        uint256 assets = IALMSyncExtension(address(vault)).convertToAssets(shares);
        uint256 roundTrip = IALMSyncExtension(address(vault)).convertToShares(assets);

        // Then: Each leg is pro rata against the holding, rounded down.
        assertEq(assets, shares.fullMulDiv(total, supply));
        assertEq(roundTrip, assets.fullMulDiv(supply, total));

        // And: No shares are created.
        assertLe(roundTrip, shares);
    }
}
