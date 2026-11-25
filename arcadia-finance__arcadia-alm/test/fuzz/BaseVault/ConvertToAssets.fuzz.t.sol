/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { BaseVault_Fuzz_Test } from "./_BaseVault.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";

/**
 * @notice Fuzz tests for the function "convertToAssets" of contract "BaseVault", over both vault kinds.
 */
contract ConvertToAssets_BaseVault_Fuzz_Test is BaseVault_Fuzz_Test {
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

    function testFuzz_Revert_convertToAssets_CoreNotDeployed(PoolState memory poolState, uint256 index, uint256 shares)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[bound(index, 0, list.length - 1)];

        // When: Reading convertToAssets() on one of its vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        IALMSyncExtension(vault).convertToAssets(shares);
    }

    function testFuzz_Revert_convertToAssets_Reentrancy(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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

        // When: Converting a share amount.
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        IALMSyncExtension(address(vault)).convertToAssets(shares);
    }

    function testFuzz_Success_convertToAssets_ZeroWhenNotInitialized(
        PoolState memory poolState,
        uint256 index,
        uint256 shares
    ) public {
        // Given: The four vaults over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // When: Converting any share amount.
        // Then: There is nothing to convert against.
        assertEq(IALMSyncExtension(address(vault)).convertToAssets(shares), 0);
    }

    function testFuzz_Success_convertToAssets_WholeSupplyIsTotalAssets(
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

        // When: Converting the whole supply.
        uint256 assets = IALMSyncExtension(address(vault)).convertToAssets(almCore.totalSupply());

        // Then: It is the holding at whichever of spot and the mean values it lowest.
        bool assetIsToken0 = vault.asset() == address(token0);
        uint256 spot = sqrtPriceX96(pool);
        uint256 mean = almCore.meanSqrtPriceX96_();
        uint160 price = uint160(assetIsToken0 ? FixedPointMathLib.max(spot, mean) : FixedPointMathLib.min(spot, mean));
        uint128 liquidity = range.liquidity + range.liquidityStaked;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(price, range.tickLower, range.tickUpper, liquidity);
        (amount0, amount1) = (amount0 + almCore.bufferAmount0(), amount1 + almCore.bufferAmount1());
        assertEq(
            assets, assetIsToken0 ? amount0 + token1ToToken0(price, amount1) : amount1 + token0ToToken1(price, amount0)
        );
    }

    function testFuzz_Success_convertToAssets_SplittingNeverGainsAnything(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 index,
        uint256 shares,
        uint256 part
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

        // And: A share amount split in two.
        uint256 supply = almCore.totalSupply();
        shares = bound(shares, 0, supply);
        part = bound(part, 0, shares);

        // When: Converting the two parts and the whole.
        uint256 whole = IALMSyncExtension(address(vault)).convertToAssets(shares);
        uint256 parts = IALMSyncExtension(address(vault)).convertToAssets(part)
            + IALMSyncExtension(address(vault)).convertToAssets(shares - part);

        // Then: Each conversion is its pro rata part of the holding, rounded down.
        assertEq(whole, shares.fullMulDiv(total, supply));
        assertEq(parts, part.fullMulDiv(total, supply) + (shares - part).fullMulDiv(total, supply));

        // And: The parts never add up to more than the whole.
        assertLe(parts, whole);
    }

    function testFuzz_Success_convertToAssets_ZeroWithoutTheTwapWhenNotInitialized(
        PoolState memory poolState,
        uint256 index,
        uint256 shares,
        uint32 window
    ) public {
        // Given: The four vaults over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // And: A TWAP window reaching back past the pool's first observation.
        window = uint32(bound(window, Constants.TWAP_WINDOW + 1, type(uint32).max));
        vm.prank(factory);
        almCore.setDeviation(window, Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION);
        (bool readable,) = address(vault).staticcall(abi.encodeCall(IALMSyncExtension.totalAssets, ()));
        assertFalse(readable);

        // When: Converting any share amount.
        // Then: There is nothing to convert against, and the TWAP is never read.
        assertEq(IALMSyncExtension(address(vault)).convertToAssets(shares), 0);
    }
}
