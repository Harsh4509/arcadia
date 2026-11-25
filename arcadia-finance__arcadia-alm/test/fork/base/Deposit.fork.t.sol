/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { Base_Fork_Test } from "./_Base.fork.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fork tests for the function "deposit" of contract "ALMVaultSync", on Base.
 */
contract Deposit_Base_Fork_Test is Base_Fork_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFork_Success_deposit_RangeAroundSpot(
        uint256 assets,
        bool isToken0,
        uint256 protocolSwapFeeBps,
        uint256 maxSwapCostBps
    ) public {
        // Given: A core worth 100k USDC of each token, in a range 20 spacings either side of spot.
        seedCore(CLMath.convert(sqrtPriceX96(pool), false, 100_000e6, false), 100_000e6);
        openRange(spacedTick(-20), spacedTick(20));
        setMaxSwapCost(maxSwapCostBps);

        // And: A protocol share of the core's swap fees.
        setProtocolSwapFeeBps(protocolSwapFeeBps);

        // And: A deposit from 10 USDC to 1M USDC of value, within maxDeposit.
        ALMVaultSync vault = isToken0 ? syncVault0 : syncVault1;
        assets = bound(
            assets,
            isToken0 ? CLMath.convert(sqrtPriceX96(pool), false, 10e6, false) : 10e6,
            FixedPointMathLib.min(
                IALMSyncExtension(address(vault)).maxDeposit(depositor),
                isToken0 ? CLMath.convert(sqrtPriceX96(pool), false, 1_000_000e6, false) : 1_000_000e6
            )
        );

        // When: Depositing.
        uint256 preview = vault.previewDeposit(assets);
        uint256 shares = deposit(vault, assets);

        // Then: It mints at least the preview.
        assertGt(shares, 0);
        assertGe(shares, preview);
    }

    function testFork_Success_deposit_SwapsIntoTheRangeAhead(
        uint256 assets,
        uint256 protocolSwapFeeBps,
        uint256 maxSwapCostBps
    ) public {
        // Given: A core holding 100k USDC in a range from 1 to 20 spacings below spot, seeded with a wei of WETH.
        seedCore(1, 100_000e6);
        openRange(spacedTick(-20), spacedTick(-1));

        // And: A max swap cost whose band reaches a spacing into the range.
        {
            uint256 deviation =
                uint256(sqrtPriceX96(pool)).fullMulDivUp(2e6, TickMath.getSqrtPriceAtTick(spacedTick(-2))) - 2e6;
            setMaxSwapCost(bound(maxSwapCostBps, (pool.fee() + deviation).divUp(100), ConfigLib.BPS_DENOMINATOR - 1));
        }

        // And: A protocol share of the core's swap fees.
        setProtocolSwapFeeBps(protocolSwapFeeBps);

        // And: A WETH deposit past the input to the range's edge, across the tick below spot, up to four times it.
        {
            (, int128 liquidityNet,,,,,,,,) = pool.ticks(spacedTick(0));
            uint160 sqrtPriceCrossed = TickMath.getSqrtPriceAtTick(spacedTick(0));
            uint256 toEdge = SqrtPriceMath.getAmount0Delta(sqrtPriceCrossed, sqrtPriceX96(pool), pool.liquidity(), true)
                + SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtPriceAtTick(spacedTick(-1)),
                    sqrtPriceCrossed,
                    uint128(int128(pool.liquidity()) - liquidityNet),
                    true
                );
            toEdge = toEdge.fullMulDivUp(1e6, 1e6 - pool.fee());
            assets = bound(
                assets,
                toEdge + 1,
                FixedPointMathLib.min(IALMSyncExtension(address(syncVault0)).maxDeposit(depositor), 4 * toEdge)
            );
        }

        // When: Depositing.
        uint256 preview = syncVault0.previewDeposit(assets);
        uint256 shares = deposit(syncVault0, assets);

        // Then: It mints at least the preview.
        assertGt(shares, 0);
        assertGe(shares, preview);
    }
}
