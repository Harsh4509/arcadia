/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { Base_Fork_Test } from "./_Base.fork.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";

/**
 * @notice Fork tests for the function "withdraw" of contract "ALMVaultSync", on Base.
 */
contract Withdraw_Base_Fork_Test is Base_Fork_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFork_Success_withdraw_RangeAroundSpot(uint256 assets, bool isToken0, uint256 maxSwapCostBps) public {
        // Given: A core worth 100k USDC of each token, in a range 20 spacings either side of spot.
        seedCore(CLMath.convert(sqrtPriceX96(pool), false, 100_000e6, false), 100_000e6);
        openRange(spacedTick(-20), spacedTick(20));
        setMaxSwapCost(maxSwapCostBps);

        // And: A withdraw of one wei up to the steward's maxWithdraw.
        ALMVaultSync vault = isToken0 ? syncVault0 : syncVault1;
        uint256 most = IALMSyncExtension(address(vault)).maxWithdraw(steward);
        vm.assume(most > 0);
        assets = bound(assets, 1, most);
        uint256 preview = vault.previewWithdraw(assets);
        uint256 balanceBefore = almCore.balanceOf(steward);
        uint256 assetsBefore = IERC20(vault.asset()).balanceOf(steward);

        // When: The steward withdraws.
        vm.prank(steward);
        uint256 shares = vault.withdraw(assets, steward, steward);

        // Then: It paid at least the assets and burned the previewed shares.
        assertGe(IERC20(vault.asset()).balanceOf(steward) - assetsBefore, assets);
        assertEq(shares, preview);
        assertEq(balanceBefore - almCore.balanceOf(steward), shares);
    }
}
