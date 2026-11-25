/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "previewDeposit" of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(unused-return)
contract PreviewDeposit_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
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

    function testFuzz_Revert_previewDeposit_CoreNotDeployed(PoolState memory poolState, bool isToken0, uint256 assets)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? 0 : 1];

        // When: Reading previewDeposit() on one of its synchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        ALMVaultSync(vault).previewDeposit(assets);
    }

    function testFuzz_Revert_previewDeposit_Reentrancy(
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

        // And: The core's lock is held.
        almCore.lock_();

        // When: Previewing a deposit.
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        vault.previewDeposit(assets);
    }

    function testFuzz_Success_previewDeposit_ZeroWhenNotInitialized(
        PoolState memory poolState,
        uint256 assets,
        bool isToken0
    ) public {
        // Given: A vault over a core never seeded, and a deposit up to the fuzzed cap.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);
        assets = bound(assets, 0, Constants.MAX_FUZZED_AMOUNT);

        // When: Previewing a deposit.
        // Then: It mints nothing, there being no supply to mint against.
        assertEq(vault.previewDeposit(assets), 0);
    }

    function testFuzz_Success_previewDeposit_ConsistentWithTheBoundedDeposit(
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

        // And: A funded caller, and the preview.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        uint256 quoted = vault.previewDeposit(assets);

        // When: The caller deposits with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, 0);

        // Then: The deposit mints exactly the preview, the two consistent.
        assertEq(shares, quoted);
    }

    function testFuzz_Success_previewDeposit_ConsistentWithThePlainDeposit(
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

        // And: A funded caller, and the preview.
        assets = fundDeposit(vault, assets, 0, type(uint256).max);
        uint256 quoted = vault.previewDeposit(assets);
        uint256 supplyBefore = almCore.totalSupply();

        // When: The caller deposits through the plain signature.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress);

        // Then: The core minted the preview, the two consistent.
        assertEq(shares, quoted);
        assertEq(almCore.totalSupply(), supplyBefore + quoted);
    }

    function testFuzz_Success_previewDeposit_MintsThePreviewPastAnInitializedTick(
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
        int24 foreignTick = range.tickUpper + poolState.tickSpacing;
        foreignLiquidity = uint128(
            bound(
                foreignLiquidity,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(foreignTick, foreignTick + 2 * poolState.tickSpacing, Constants.MIN_FUZZED_LIQUIDITY)
            )
        );
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPriceX96(pool), foreignTick, foreignTick + 2 * poolState.tickSpacing, foreignLiquidity
            );
            mintPosition(
                pool, users.liquidityProvider, foreignTick, foreignTick + 2 * poolState.tickSpacing, amount0, amount1
            );
        }

        // And: A deposit past that tick by its rounding, within the range and the buffer.
        {
            uint160 crossed = TickMath.getSqrtPriceAtTick(foreignTick);
            uint256 least;
            {
                int256 wordStart = (int256(currentTick(pool)) / poolState.tickSpacing) >> 8;
                int256 wordEnd = (int256(range.tickUpper) / poolState.tickSpacing) >> 8;
                least = (uint256(wordEnd > wordStart ? wordEnd - wordStart : wordStart - wordEnd) + 3)
                    * (uint256(pool.liquidity())
                            .fullMulDivUp(1 << 96, sqrtPriceX96(pool))
                            .divUp(TickMath.getSqrtPriceAtTick(range.tickUpper))
                        + 2);
            }
            least += SqrtPriceMath.getAmount0Delta(crossed, sqrtPriceX96(pool), pool.liquidity(), true)
                .fullMulDivUp(1e6, 1e6 - poolState.fee) + 1;

            // And: Past the edge's margins, u + 6 on the balance and 6 on the position.
            least += FixedPointMathLib.divUp(1 << 96, TickMath.getSqrtPriceAtTick(range.tickUpper)) + 12;
            uint256 most = (SqrtPriceMath.getAmount0Delta(crossed, sqrtPriceX96(pool), pool.liquidity(), false)
                    + SqrtPriceMath.getAmount0Delta(
                        TickMath.getSqrtPriceAtTick(range.tickUpper),
                        crossed,
                        pool.liquidity() - foreignLiquidity,
                        false
                    ))
            .fullMulDiv(1e6, 1e6 - poolState.fee);
            most = FixedPointMathLib.min(
                most, token1ToToken0(sqrtPriceX96(pool), Constants.MAX_FUZZED_AMOUNT - almCore.bufferAmount1())
            );
            assets = fundDeposit(vault, assets, least, most);
        }
        uint256 quoted = vault.previewDeposit(assets);

        // When: The caller deposits with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, 0);

        // Then: Its swap crossed the tick.
        assertLt(sqrtPriceX96(pool), TickMath.getSqrtPriceAtTick(foreignTick));

        // And: It minted exactly the preview.
        assertEq(shares, quoted);
    }
}
