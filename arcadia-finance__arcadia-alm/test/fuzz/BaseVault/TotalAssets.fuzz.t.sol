/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { BaseVault_Fuzz_Test } from "./_BaseVault.fuzz.t.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";

/**
 * @notice Fuzz tests for the function "totalAssets" of contract "BaseVault", over both vault kinds.
 */
contract TotalAssets_BaseVault_Fuzz_Test is BaseVault_Fuzz_Test {
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

    function testFuzz_Revert_totalAssets_CoreNotDeployed(PoolState memory poolState, uint256 index) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[bound(index, 0, list.length - 1)];

        // When: Reading totalAssets() on one of its vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        IALMSyncExtension(vault).totalAssets();
    }

    function testFuzz_Revert_totalAssets_Reentrancy(
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

        // And: The core's lock is held.
        almCore.lock_();

        // When: Reading totalAssets().
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        IALMSyncExtension(address(vault)).totalAssets();
    }

    function testFuzz_Revert_totalAssets_WindowTooOld(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 index,
        uint32 window
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // And: A TWAP window reaching back past the pool's first observation.
        window = uint32(bound(window, Constants.TWAP_WINDOW + 1, type(uint32).max));
        vm.prank(factory);
        almCore.setDeviation(window, Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION);

        // When: Reading totalAssets.
        // Then: It reverts.
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "OLD"));
        IALMSyncExtension(address(vault)).totalAssets();
    }

    function testFuzz_Success_totalAssets_ZeroWhenNotInitialized(PoolState memory poolState, uint256 index) public {
        // Given: The four vaults over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // When: Reading totalAssets.
        // Then: The core holds nothing.
        assertEq(IALMSyncExtension(address(vault)).totalAssets(), 0);
    }

    function testFuzz_Success_totalAssets_LowerOfSpotAndMean(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 index,
        uint256 amountIn,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // And: Spot moved in the block by at most a 1% sale, unseen by the mean tick.
        {
            uint256 ceiling = (zeroForOne
                    ? uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPriceX96(pool))
                    : uint256(pool.liquidity()).fullMulDiv(sqrtPriceX96(pool), 1 << 96))
            .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR);
            amountIn = bound(amountIn, 1, ceiling);
        }
        ERC20Mock(zeroForOne ? address(token0) : address(token1)).mint(users.unprivilegedAddress, amountIn);
        pushPrice(pool, users.unprivilegedAddress, zeroForOne, amountIn);

        // When: Reading totalAssets.
        uint256 total = IALMSyncExtension(address(vault)).totalAssets();

        // Then: It is the holding at whichever of spot and the mean values it lowest.
        bool assetIsToken0 = vault.asset() == address(token0);
        uint256 spot = sqrtPriceX96(pool);
        uint256 mean = almCore.meanSqrtPriceX96_();
        uint160 price = uint160(assetIsToken0 ? FixedPointMathLib.max(spot, mean) : FixedPointMathLib.min(spot, mean));
        Range memory staged = almCore.getRange(0);
        uint256 idle0;
        uint256 idle1;
        {
            (uint256 fees0, uint256 fees1) = positionFees(pool, staged.unstakedTokenId);
            uint256 feeBps = almCore.protocolSwapFeeBps_();
            idle0 = almCore.bufferAmount0() + fees0 - fees0.fullMulDiv(feeBps, ConfigLib.BPS_DENOMINATOR);
            idle1 = almCore.bufferAmount1() + fees1 - fees1.fullMulDiv(feeBps, ConfigLib.BPS_DENOMINATOR);
        }
        uint128 liquidity = positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity;
        (uint256 amount0, uint256 amount1) = amountsRoundedDown(price, staged.tickLower, staged.tickUpper, liquidity);
        (amount0, amount1) = (amount0 + idle0, amount1 + idle1);
        assertEq(
            total, assetIsToken0 ? amount0 + token1ToToken0(price, amount1) : amount1 + token0ToToken1(price, amount0)
        );
    }

    function testFuzz_Revert_totalAssets_ObservationsOutrunTheWindow(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 index,
        uint256 count
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        BaseVault vault = vaults[bound(index, 0, vaults.length - 1)];

        // And: An observation per second, for at least the seconds the pool's ring holds.
        (,,,, uint16 cardinality,) = pool.slot0();
        count = bound(count, cardinality, uint256(cardinality) + 16);
        int24 tickUpper = bandTick(pool.tickSpacing());
        for (uint256 i; i < count; ++i) {
            vm.warp(vm.getBlockTimestamp() + 1);
            mintPosition(pool, users.liquidityProvider, -tickUpper, tickUpper, uint128(1e6));
        }

        // When: Reading totalAssets.
        // Then: It reverts.
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "OLD"));
        IALMSyncExtension(address(vault)).totalAssets();

        // And: It still reverts after a raise of the ring and one more observation.
        pool.increaseObservationCardinalityNext(2 * cardinality);
        vm.warp(vm.getBlockTimestamp() + 1);
        mintPosition(pool, users.liquidityProvider, -tickUpper, tickUpper, uint128(1e6));
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "OLD"));
        IALMSyncExtension(address(vault)).totalAssets();
    }
}
