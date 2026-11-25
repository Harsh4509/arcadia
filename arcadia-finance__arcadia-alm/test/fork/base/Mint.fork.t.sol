/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { Base_Fork_Test } from "./_Base.fork.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";

/**
 * @notice Fork tests for the function "mint" of contract "ALMVaultSync", on Base.
 */
contract Mint_Base_Fork_Test is Base_Fork_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFork_Success_mint_RangeAroundSpot(
        uint256 shares,
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

        // And: A mint of one share up to ten times the supply, within maxMint.
        ALMVaultSync vault = isToken0 ? syncVault0 : syncVault1;
        shares = bound(
            shares,
            1,
            FixedPointMathLib.min(IALMSyncExtension(address(vault)).maxMint(depositor), 10 * almCore.totalSupply())
        );
        uint256 preview = vault.previewMint(shares);

        // When: Minting.
        deal(vault.asset(), depositor, preview);
        vm.startPrank(depositor);
        IERC20(vault.asset()).approve(address(vault), preview);
        uint256 assets = vault.mint(shares, depositor);
        vm.stopPrank();

        // Then: It minted the shares for at most the preview.
        assertEq(almCore.balanceOf(depositor), shares);
        assertLe(assets, preview);
    }
}
